begin;
create table private.inventory_state (
 workshop_id uuid primary key references private.workshops(id),
 data jsonb not null default '{"revision":0,"orders":[],"movements":[],"receipts":[]}',
 check(jsonb_typeof(data)='object' and data ?& array['revision','orders','movements','receipts'] and
  jsonb_typeof(data->'revision')='number' and (data->>'revision')::numeric between 0 and 9007199254740991 and
  (data->>'revision')::numeric=trunc((data->>'revision')::numeric) and
  jsonb_typeof(data->'orders')='array' and jsonb_typeof(data->'movements')='array' and jsonb_typeof(data->'receipts')='array')
);
alter table private.inventory_state enable row level security;
revoke all on private.inventory_state from public,anon,authenticated;
create function private.purchase_quantity(packages bigint,size bigint) returns bigint language plpgsql immutable set search_path='' as $$
begin
 if packages<1 or packages>1000000000 or size<1 or size>1000000000 or packages*size%1000<>0 or packages*size/1000>1000000000 then raise exception 'Exact quantity with at most three decimal places required';end if;
 return packages*size/1000;
end $$;
create function private.inventory_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb;d jsonb;previous private.command_receipts%rowtype;reason text;at_time timestamptz;pid uuid;lid uuid;itemid uuid;linked uuid;purchase jsonb;line jsonb;v jsonb;lines jsonb:='[]';record jsonb;size bigint;packages bigint;q bigint;received bigint;returned bigint;available bigint;c private.catalog%rowtype;result jsonb;rev bigint;before_value jsonb;begin
 m:=private.photo_device(w,dev);
 if m->>'role' not in ('admin','office') or (m->>'role'<>'admin' and not coalesce((m->>'seeCosts')::boolean,false)) then raise exception 'Office cost-management permission required' using errcode='42501';end if;
 if not private.photo_files_ready(w) then raise exception 'Recover original files before new work';end if;
 perform 1 from private.workshops where id=w for update;
 if cid is null or jsonb_typeof(p) is distinct from 'object' then raise exception 'Command and payload required';end if;
 select * into previous from private.command_receipts where workshop_id=w and id=cid;
 if found then
  if previous.actor_id<>auth.uid() or previous.device_id<>dev or previous.action<>action or previous.payload<>p then raise exception 'Command ID reused';end if;return previous.result;
 end if;
 insert into private.inventory_state(workshop_id) values(w) on conflict do nothing;
 select data into d from private.inventory_state where workshop_id=w for update;before_value:=d;rev:=(d->>'revision')::bigint;
 if private.require_int(p->'revision',0,9007199254740991,'Revision')<>rev then raise exception 'Inventory revision conflict; review current stock';end if;
 reason:=private.require_text(p->>'reason','Reason',2000);at_time:=(p->>'at')::timestamptz;
 if at_time is null or at_time>now()+interval '2 minutes' then raise exception 'Actual movement date required';end if;
 if action='purchase_create' then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['revision','at','reason','id','supplier','reference','expectedAt','orderId','lines'])) then raise exception 'Unsupported purchase fields';end if;
  pid:=(p->>'id')::uuid;linked:=(p->>'orderId')::uuid;
  if pid is null or exists(select 1 from jsonb_array_elements(d->'orders') x where x->>'id'=pid::text) then raise exception 'Duplicate or absent purchase ID';end if;
  if linked is not null and not exists(select 1 from private.orders where workshop_id=w and id=linked) then raise exception 'Repair order outside workshop';end if;
  if (p->>'expectedAt')::timestamptz is null then raise exception 'Expected date required';end if;
  if jsonb_typeof(p->'lines') is distinct from 'array' or jsonb_array_length(p->'lines') not between 1 and 100 then raise exception 'Select one to one hundred purchase lines';end if;
  for v in select value from jsonb_array_elements(p->'lines') loop
   if jsonb_typeof(v) is distinct from 'object' or exists(select 1 from jsonb_object_keys(v) k where not k=any(array['id','itemId','packageSizeMilli','packagesMilli','unitCostCents'])) then raise exception 'Unsupported purchase line';end if;
   lid:=(v->>'id')::uuid;itemid:=(v->>'itemId')::uuid;
   if lid is null or exists(select 1 from jsonb_array_elements(lines) x where x->>'id'=lid::text) then raise exception 'Duplicate or absent line ID';end if;
   select * into c from private.catalog where workshop_id=w and id=itemid;
   if not found or exists(select 1 from private.catalog_details cd where cd.workshop_id=w and cd.item_id=itemid and not cd.active) then raise exception 'Active catalog item required';end if;
   size:=private.require_int(v->'packageSizeMilli',1,1000000000,'Package size');packages:=private.require_int(v->'packagesMilli',1,1000000000,'Packages');q:=private.purchase_quantity(packages,size);
   lines:=lines||jsonb_build_array(jsonb_build_object('id',lid,'itemId',itemid,'reference',c.reference,'description',c.description,'unit',c.unit,'packageSizeMilli',size,'requestedPackagesMilli',packages,'requestedMilli',q,'unitCostCents',private.require_int(v->'unitCostCents',0,1000000000,'Unit cost')));
  end loop;
  record:=jsonb_build_object('id',pid,'supplier',private.require_text(p->>'supplier','Supplier',300),'reference',private.require_text(p->>'reference','Purchase reference',300),'expectedAt',(p->>'expectedAt')::timestamptz,'orderId',linked,'lines',lines,'actorId',auth.uid(),'createdAt',at_time,'reason',reason);
  d:=jsonb_set(d,'{orders}',d->'orders'||jsonb_build_array(record));
 elsif action in ('purchase_receive','supplier_return') then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['revision','at','reason','purchaseId','lineId','packagesMilli','reference'])) then raise exception 'Unsupported movement fields';end if;
  pid:=(p->>'purchaseId')::uuid;lid:=(p->>'lineId')::uuid;
  select x into purchase from jsonb_array_elements(d->'orders') x where x->>'id'=pid::text;
  select x into line from jsonb_array_elements(purchase->'lines') x where x->>'id'=lid::text;
  if line is null then raise exception 'Original purchase line required';end if;itemid:=(line->>'itemId')::uuid;
  if at_time<(purchase->>'createdAt')::timestamptz then raise exception 'Movement predates purchase';end if;
  select * into c from private.catalog where workshop_id=w and id=itemid for update;
  if not found or c.unit is distinct from line->>'unit' then raise exception 'Catalog unit changed; review';end if;
  packages:=private.require_int(p->'packagesMilli',1,1000000000,'Packages');q:=private.purchase_quantity(packages,(line->>'packageSizeMilli')::bigint);
  select coalesce(sum(case when x->>'kind'='receive' then (x->>'quantityMilli')::bigint else 0 end),0),coalesce(sum(case when x->>'kind'='supplier_return' then (x->>'quantityMilli')::bigint else 0 end),0) into received,returned from jsonb_array_elements(d->'movements') x where x->>'purchaseId'=pid::text and x->>'lineId'=lid::text;
  if action='purchase_receive' and received+q>(line->>'requestedMilli')::bigint then raise exception 'Receipt exceeds requested quantity';end if;
  select c.stock_milli-coalesce(sum(case when part->>'kind' in ('consume','reserve') then (part->>'quantityMilli')::bigint when part->>'kind'='return' then -(part->>'quantityMilli')::bigint else 0 end),0) into available from private.orders o cross join lateral jsonb_array_elements(o.data->'parts') part where o.workshop_id=w and part->>'itemId'=itemid::text;
  if action='supplier_return' and (q>received-returned or q>available) then raise exception 'Supplier return exceeds received or available unreserved stock';end if;
  update private.catalog set stock_milli=stock_milli+case when action='purchase_receive' then q else -q end where workshop_id=w and id=itemid;
  record:=jsonb_build_object('id',cid,'purchaseId',pid,'lineId',lid,'itemId',itemid,'kind',case when action='purchase_receive' then 'receive' else 'supplier_return' end,'packagesMilli',packages,'quantityMilli',q,'unit',line->'unit','unitCostCents',line->'unitCostCents','costCents',(q*(line->>'unitCostCents')::bigint+500)/1000,'reference',private.require_text(p->>'reference','Delivery reference',300),'reason',reason,'actorId',auth.uid(),'at',at_time);
  d:=jsonb_set(d,'{movements}',d->'movements'||jsonb_build_array(record));
 else raise exception 'Unsupported inventory action';end if;
 d:=d||jsonb_build_object('revision',rev+1,'receipts',d->'receipts'||jsonb_build_array(jsonb_build_object('id',cid,'actorId',auth.uid(),'action',action,'payload',p)));
 update private.inventory_state set data=d where workshop_id=w;
 result:=jsonb_build_object('saved',true,'revision',rev+1);
 insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,result);
 insert into private.audit(workshop_id,actor_id,operation_id,kind,before_data,after_data) values(w,auth.uid(),cid,action,before_value,d);
 return result;
end $$;
create function public.inventory_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.inventory_command($1,$2,$3,$4,$5) $$;
alter function private.snapshot(uuid) rename to snapshot_before_purchases;
create function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;r jsonb;begin
 m:=private.membership(w);r:=private.snapshot_before_purchases(w);
 if m->>'role'='admin' or (m->>'role'='office' and coalesce((m->>'seeCosts')::boolean,false)) then r:=r||jsonb_build_object('purchaseLedger',coalesce((select data from private.inventory_state where workshop_id=w),'{"revision":0,"orders":[],"movements":[],"receipts":[]}'::jsonb));end if;
 return r;
end $$;
alter function private.backup_tables() rename to backup_tables_before_purchases;
create function private.backup_tables() returns text[] language sql immutable set search_path='' as $$ select private.backup_tables_before_purchases()||array['inventory_state']::text[] $$;
alter function private.export_workshop(uuid,uuid) rename to export_workshop_before_purchases;
create function private.export_workshop(w uuid,dev uuid) returns jsonb language sql security definer set search_path='' as $$ select private.export_workshop_before_purchases(w,dev)||jsonb_build_object('databaseVersion',8) $$;
alter function private.restore_workshop(uuid,uuid,uuid,jsonb) rename to restore_workshop_before_purchases;
create function private.restore_workshop(w uuid,dev uuid,rid uuid,a jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare normalized jsonb:=a;begin
 perform private.backup_admin(w,dev);
 if exists(select 1 from private.inventory_state where workshop_id=w) and not exists(select 1 from private.restores where workshop_id=w and id=rid) then raise exception 'Restore requires an empty isolated workshop with no inventory records';end if;
 if a->>'databaseVersion'='8' then
  if jsonb_typeof(a->'tables'->'inventory_state') is distinct from 'array' then raise exception 'Inventory table missing';end if;
  normalized:=a||jsonb_build_object('databaseVersion',7);
 elsif a->>'databaseVersion' in ('2','3','4','5','6','7') then
  normalized:=jsonb_set(a,'{tables,inventory_state}',coalesce(a->'tables'->'inventory_state','[]'));
 end if;
 return private.restore_workshop_before_purchases(w,dev,rid,normalized);
end $$;
revoke all on function private.purchase_quantity(bigint,bigint),private.inventory_command(uuid,uuid,uuid,text,jsonb),public.inventory_command(uuid,uuid,uuid,text,jsonb),private.snapshot_before_purchases(uuid),private.snapshot(uuid),private.backup_tables_before_purchases(),private.backup_tables(),private.export_workshop_before_purchases(uuid,uuid),private.export_workshop(uuid,uuid),private.restore_workshop_before_purchases(uuid,uuid,uuid,jsonb),private.restore_workshop(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.inventory_command(uuid,uuid,uuid,text,jsonb),public.inventory_command(uuid,uuid,uuid,text,jsonb),private.snapshot(uuid),private.export_workshop(uuid,uuid),private.restore_workshop(uuid,uuid,uuid,jsonb) to authenticated;
commit;
