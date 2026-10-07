begin;
create table private.maintenance_state(workshop_id uuid primary key references private.workshops(id),data jsonb not null,
 check(jsonb_typeof(data)='object' and data ?& array['revision','plans'] and (data->>'revision')::bigint>=0 and jsonb_typeof(data->'plans')='array'));
alter table private.maintenance_state enable row level security;revoke all on private.maintenance_state from public,anon,authenticated;
create function private.maintenance_day(v jsonb) returns text language plpgsql immutable set search_path='' as $$
declare t text;begin
 if jsonb_typeof(v) is distinct from 'string' or (v#>>'{}') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Calendar date required';end if;
 t:=v#>>'{}';perform private.planning_date(to_jsonb(t||'T00:00:00Z'));return t;
end $$;
create function private.maintenance_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb;d jsonb;previous private.command_receipts%rowtype;old jsonb;value jsonb;event jsonb;rows jsonb;planid uuid;vid uuid;oid uuid;rev bigint;version jsonb;reason text;due text;km bigint;months bigint;interval_km bigint;performed timestamptz;last_completion jsonb;completion jsonb;next_date text;next_km bigint;result jsonb;zone text;local_date date;
begin
 m:=private.photo_device(w,dev);if m->>'role' not in ('admin','office') then raise exception 'Office permission required' using errcode='42501';end if;
 if not private.photo_files_ready(w) then raise exception 'Recover original files before new work';end if;
 perform 1 from private.workshops where id=w for update;
 if cid is null or jsonb_typeof(p) is distinct from 'object' then raise exception 'Command and payload required';end if;
 select * into previous from private.command_receipts where workshop_id=w and id=cid;
 if found then if previous.actor_id<>auth.uid() or previous.device_id<>dev or previous.action<>action or previous.payload<>p then raise exception 'Command ID reused';end if;return previous.result;end if;
 select data into d from private.maintenance_state where workshop_id=w;d:=coalesce(d,'{"revision":0,"plans":[]}');rev:=(d->>'revision')::bigint;
 if private.require_int(p->'revision',0,9007199254740991,'Revision')<>rev then raise exception 'Maintenance revision conflict';end if;
 planid:=(p->>'id')::uuid;if planid is null then raise exception 'Plan ID required';end if;
 reason:=private.require_text(p->>'reason','Reason',2000);event:=jsonb_build_object('id',cid,'kind',action,'actorId',auth.uid(),'at',now(),'reason',reason);
 select x into old from jsonb_array_elements(d->'plans') x where x->>'id'=planid::text;
 if action='care_plan' then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','revision','vehicleId','title','source','dueDate','dueKm','intervalMonths','intervalKm','zone','reason'])) then raise exception 'Unsupported maintenance fields';end if;
  vid:=(p->>'vehicleId')::uuid;if vid is null or not exists(select 1 from private.vehicle_profiles where workshop_id=w and vehicle_id=vid) then raise exception 'Workshop vehicle required';end if;
  if old is not null and (old->>'vehicleId'<>vid::text or old->>'status'<>'active') then raise exception 'Keep original vehicle or create a new plan';end if;
  zone:=p->>'zone';if zone is null or zone not in ('Europe/Madrid','Atlantic/Canary') then raise exception 'Spanish timezone required';end if;
  due:=case when p->>'dueDate' is null then null else private.maintenance_day(p->'dueDate') end;
  km:=case when p->>'dueKm' is null then null else private.require_int(p->'dueKm',0,9999999,'Due mileage') end;
  if due is null and km is null then raise exception 'Due date or mileage required';end if;
  months:=case when p->>'intervalMonths' is null then null else private.require_int(p->'intervalMonths',1,120,'Months interval') end;
  interval_km:=case when p->>'intervalKm' is null then null else private.require_int(p->'intervalKm',1,2000000,'Mileage interval') end;
  if (months is not null and due is null) or (interval_km is not null and km is null) then raise exception 'Recurrence requires initial due threshold';end if;
  version:=jsonb_build_object('zone',zone,'title',private.require_text(p->>'title','Maintenance title',300),'source',private.require_text(p->>'source','Confirmed source or manual criteria',2000),'dueDate',due,'dueKm',km,'intervalMonths',months,'intervalKm',interval_km,'actorId',auth.uid(),'at',now());
  value:=version||jsonb_build_object('id',planid,'vehicleId',vid,'status','active','versions',coalesce(old->'versions','[]')||jsonb_build_array(version),'completions',coalesce(old->'completions','[]'),'events',coalesce(old->'events','[]')||jsonb_build_array(event));
 elsif action='care_complete' then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','revision','performedAt','km','orderId','evidence','reason'])) then raise exception 'Unsupported completion fields';end if;
  if old is null or old->>'status'<>'active' then raise exception 'Active maintenance plan required';end if;
  performed:=private.planning_date(p->'performedAt');km:=private.require_int(p->'km',0,9999999,'Performed mileage');
  if performed>now()+interval '2 minutes' then raise exception 'Future maintenance cannot be completed';end if;
  last_completion:=old->'completions'->-1;
  if last_completion is not null and (performed<=(last_completion->>'performedAt')::timestamptz or km<(last_completion->>'km')::bigint) then raise exception 'Preserve chronological dates and mileage';end if;
  oid:=(p->>'orderId')::uuid;if oid is not null and not exists(select 1 from private.orders where workshop_id=w and id=oid and data->>'vehicleId'=old->>'vehicleId') then raise exception 'Completion repair must belong to same vehicle and workshop';end if;
  zone:=old->>'zone';local_date:=(performed at time zone zone)::date;
  completion:=jsonb_build_object('id',cid,'performedAt',performed,'performedDate',to_char(local_date,'YYYY-MM-DD'),'km',km,'orderId',oid,'evidence',private.require_text(p->>'evidence','Human completion evidence',2000),'valueSource','manual','actorId',auth.uid(),'planVersion',jsonb_array_length(old->'versions'),'dueDate',old->'dueDate','dueKm',old->'dueKm');
  months:=(old->>'intervalMonths')::bigint;interval_km:=(old->>'intervalKm')::bigint;
  next_date:=case when months is null then null else to_char(local_date+make_interval(months=>months::int),'YYYY-MM-DD') end;
  if next_date is not null then perform private.maintenance_day(to_jsonb(next_date));end if;
  next_km:=case when interval_km is null then null else private.require_int(to_jsonb(km+interval_km),0,9999999,'Next mileage') end;
  value:=old||jsonb_build_object('dueDate',next_date,'dueKm',next_km,'status',case when months is null and interval_km is null then 'completed' else 'active' end,'completions',old->'completions'||jsonb_build_array(completion),'events',old->'events'||jsonb_build_array(event));
  update private.vehicle_profiles set max_km=greatest(max_km,km) where workshop_id=w and vehicle_id=(old->>'vehicleId')::uuid;
 elsif action='care_pause' then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','revision','reason'])) or old is null or old->>'status'<>'active' then raise exception 'Current active plan required';end if;
  value:=old||jsonb_build_object('status','paused','events',old->'events'||jsonb_build_array(event));
 else raise exception 'Unsupported maintenance action';end if;
 select coalesce(jsonb_agg(x),'[]') into rows from jsonb_array_elements(d->'plans') x where x->>'id'<>planid::text;
 d:=jsonb_build_object('revision',rev+1,'plans',rows||jsonb_build_array(value));
 insert into private.maintenance_state values(w,d) on conflict(workshop_id) do update set data=excluded.data;
 result:=jsonb_build_object('saved',true,'revision',rev+1);insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,result);
 insert into private.audit(workshop_id,actor_id,operation_id,kind,before_data,after_data) values(w,auth.uid(),cid,action,old,value);return result;
end $$;
create function public.maintenance_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.maintenance_command($1,$2,$3,$4,$5)$$;
alter function private.snapshot(uuid) rename to snapshot_before_maintenance;
create function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;r jsonb;d jsonb;plans jsonb;completions jsonb;p jsonb;begin
 m:=private.membership(w);r:=private.snapshot_before_maintenance(w);select data into d from private.maintenance_state where workshop_id=w;d:=coalesce(d,'{"revision":0,"plans":[]}');
 if m->>'role'='technician' then
  plans:='[]';for p in select value from jsonb_array_elements(d->'plans') loop
   if exists(select 1 from jsonb_array_elements(r->'orders') o where o->>'vehicleId'=p->>'vehicleId') then
    select coalesce(jsonb_agg(x||jsonb_build_object('orderId',case when exists(select 1 from jsonb_array_elements(r->'orders') o where o->>'id'=x->>'orderId') then x->'orderId' else 'null'::jsonb end)),'[]') into completions from jsonb_array_elements(p->'completions') x;
    plans:=plans||jsonb_build_array(p||jsonb_build_object('events','[]'::jsonb,'versions','[]'::jsonb,'completions',completions));
   end if;
  end loop;d:=jsonb_set(d,'{plans}',plans);
 end if;return r||jsonb_build_object('maintenance',d);
end $$;
alter function private.backup_tables() rename to backup_tables_before_maintenance;
create function private.backup_tables() returns text[] language sql immutable set search_path='' as $$select private.backup_tables_before_maintenance()||array['maintenance_state']::text[]$$;
alter function private.export_workshop(uuid,uuid) rename to export_workshop_before_maintenance;
create function private.export_workshop(w uuid,dev uuid) returns jsonb language sql security definer set search_path='' as $$select private.export_workshop_before_maintenance(w,dev)||jsonb_build_object('databaseVersion',12)$$;
create function private.validate_maintenance(w uuid,d jsonb) returns void language plpgsql security definer set search_path='' as $$
declare p jsonb;c jsonb;v jsonb;e jsonb;last_time timestamptz;last_km bigint;begin
 if jsonb_typeof(d->'plans') is distinct from 'array' or jsonb_typeof(d->'revision') is distinct from 'number' or (d->>'revision')::bigint<0 then raise exception 'Malformed maintenance archive';end if;
 if (select count(*) from jsonb_array_elements(d->'plans'))<>(select count(distinct x->>'id') from jsonb_array_elements(d->'plans') x) then raise exception 'Duplicate maintenance plans';end if;
 for p in select value from jsonb_array_elements(d->'plans') loop
  if (p->>'id')::uuid is null or not exists(select 1 from private.vehicle_profiles where workshop_id=w and vehicle_id=(p->>'vehicleId')::uuid) or p->>'status' is null or p->>'status' not in ('active','completed','paused') or p->>'zone' is null or p->>'zone' not in ('Europe/Madrid','Atlantic/Canary') or jsonb_typeof(p->'versions') is distinct from 'array' or jsonb_array_length(p->'versions')=0 or jsonb_typeof(p->'events') is distinct from 'array' or jsonb_typeof(p->'completions') is distinct from 'array' then raise exception 'Malformed maintenance plan or foreign vehicle';end if;
  perform private.require_text(p->>'title','Title',300);perform private.require_text(p->>'source','Source',2000);
  if p->>'dueDate' is not null then perform private.maintenance_day(p->'dueDate');end if;
  if p->>'dueKm' is not null then perform private.require_int(p->'dueKm',0,9999999,'Due mileage');end if;
  if p->>'intervalMonths' is not null then perform private.require_int(p->'intervalMonths',1,120,'Month interval');end if;
  if p->>'intervalKm' is not null then perform private.require_int(p->'intervalKm',1,2000000,'Mileage interval');end if;
  if p->>'status'='active' and p->>'dueDate' is null and p->>'dueKm' is null then raise exception 'Active plan needs due threshold';end if;
  for v in select value from jsonb_array_elements(p->'versions') loop
   if not exists(select 1 from private.members where workshop_id=w and user_id=(v->>'actorId')::uuid) or v->>'zone' is null or v->>'zone' not in ('Europe/Madrid','Atlantic/Canary') then raise exception 'Malformed maintenance version actor or zone';end if;
   perform private.require_text(v->>'title','Version title',300);perform private.require_text(v->>'source','Version source',2000);perform private.planning_date(v->'at');
   if v->>'dueDate' is not null then perform private.maintenance_day(v->'dueDate');end if;
   if v->>'dueKm' is not null then perform private.require_int(v->'dueKm',0,9999999,'Version mileage');end if;
   if v->>'dueDate' is null and v->>'dueKm' is null then raise exception 'Version needs due threshold';end if;
   if v->>'intervalMonths' is not null then perform private.require_int(v->'intervalMonths',1,120,'Version months');if v->>'dueDate' is null then raise exception 'Version months need date';end if;end if;
   if v->>'intervalKm' is not null then perform private.require_int(v->'intervalKm',1,2000000,'Version interval');if v->>'dueKm' is null then raise exception 'Version interval needs mileage';end if;end if;
  end loop;
  if jsonb_array_length(p->'events')=0 then raise exception 'Maintenance history missing';end if;
  for e in select value from jsonb_array_elements(p->'events') loop
   if (e->>'id')::uuid is null or not exists(select 1 from private.members where workshop_id=w and user_id=(e->>'actorId')::uuid) or e->>'kind' is null or e->>'kind' not in ('care_plan','care_complete','care_pause') then raise exception 'Malformed maintenance event';end if;
   perform private.planning_date(e->'at');perform private.require_text(e->>'reason','Event reason',2000);
  end loop;
  if (select count(*) from jsonb_array_elements(p->'completions'))<>(select count(distinct x->>'id') from jsonb_array_elements(p->'completions') x) then raise exception 'Duplicate maintenance completion';end if;
  last_time:=null;last_km:=null;
  for c in select value from jsonb_array_elements(p->'completions') loop
   if (c->>'id')::uuid is null or not exists(select 1 from private.members where workshop_id=w and user_id=(c->>'actorId')::uuid) then raise exception 'Malformed completion actor';end if;
   perform private.planning_date(c->'performedAt');perform private.maintenance_day(c->'performedDate');perform private.require_int(c->'km',0,9999999,'Completion mileage');perform private.require_int(c->'planVersion',1,jsonb_array_length(p->'versions'),'Version');perform private.require_text(c->>'evidence','Evidence',2000);
   v:=p->'versions'->((c->>'planVersion')::int-1);
   if c->>'valueSource' is distinct from 'manual' or c->>'performedDate'<>to_char((c->>'performedAt')::timestamptz at time zone (v->>'zone'),'YYYY-MM-DD') then raise exception 'Completion local date or evidence source invalid';end if;
   if last_time is not null and ((c->>'performedAt')::timestamptz<=last_time or (c->>'km')::bigint<last_km) then raise exception 'Completion chronology invalid';end if;
   if c->>'orderId' is not null and not exists(select 1 from private.orders where workshop_id=w and id=(c->>'orderId')::uuid and data->>'vehicleId'=p->>'vehicleId') then raise exception 'Cross-workshop completion repair';end if;
   last_time:=(c->>'performedAt')::timestamptz;last_km:=(c->>'km')::bigint;
  end loop;
 end loop;
end $$;
alter function private.restore_workshop(uuid,uuid,uuid,jsonb) rename to restore_workshop_before_maintenance;
create function private.restore_workshop(w uuid,dev uuid,rid uuid,a jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare normalized jsonb:=a;result jsonb;d jsonb;begin
 perform private.backup_admin(w,dev);
 if exists(select 1 from private.maintenance_state where workshop_id=w) and not exists(select 1 from private.restores where workshop_id=w and id=rid) then raise exception 'Restore requires empty isolated maintenance state';end if;
 if a->>'databaseVersion'='12' then
  if jsonb_typeof(a->'tables'->'maintenance_state') is distinct from 'array' then raise exception 'Maintenance table missing';end if;normalized:=a||jsonb_build_object('databaseVersion',11);
 elsif a->>'databaseVersion' in ('2','3','4','5','6','7','8','9','10','11') then normalized:=jsonb_set(a,'{tables,maintenance_state}',coalesce(a->'tables'->'maintenance_state','[]'));
 end if;
 result:=private.restore_workshop_before_maintenance(w,dev,rid,normalized);for d in select data from private.maintenance_state where workshop_id=w loop perform private.validate_maintenance(w,d);end loop;return result;
end $$;
revoke all on function private.maintenance_day(jsonb),private.maintenance_command(uuid,uuid,uuid,text,jsonb),public.maintenance_command(uuid,uuid,uuid,text,jsonb),private.snapshot_before_maintenance(uuid),private.snapshot(uuid),private.backup_tables_before_maintenance(),private.backup_tables(),private.export_workshop_before_maintenance(uuid,uuid),private.export_workshop(uuid,uuid),private.validate_maintenance(uuid,jsonb),private.restore_workshop_before_maintenance(uuid,uuid,uuid,jsonb),private.restore_workshop(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.maintenance_command(uuid,uuid,uuid,text,jsonb),public.maintenance_command(uuid,uuid,uuid,text,jsonb),private.snapshot(uuid),private.export_workshop(uuid,uuid),private.restore_workshop(uuid,uuid,uuid,jsonb) to authenticated;
commit;
