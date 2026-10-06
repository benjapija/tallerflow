-- Insert-only imports: preview is advisory; commit rechecks each row under the workshop lock.
begin;
create table private.clients (
 workshop_id uuid not null references private.workshops(id),id uuid not null,
 code text, data jsonb not null,active boolean not null default true,
 primary key(workshop_id,id),unique(workshop_id,code)
);
alter table private.clients enable row level security;
revoke all on private.clients from public,anon,authenticated;
create function private.seed_clients(w uuid) returns void language sql set search_path='' as $$
 insert into private.clients(workshop_id,id,data)
 select distinct on(workshop_id,owner_id) workshop_id,owner_id,
  owner_data||jsonb_build_object('email','','taxId','','address','')
 from private.vehicle_profiles where w is null or workshop_id=w order by workshop_id,owner_id,vehicle_id
 on conflict(workshop_id,id) do nothing
$$;
select private.seed_clients(null);
create function private.import_row(w uuid,kind text,rid uuid,d jsonb,writing boolean) returns jsonb language plpgsql set search_path='' as $$
declare existing uuid;owner private.clients%rowtype;cols text[];k text;plate_value text;vin_value text;country_value text;details jsonb;
begin
 if rid is null or jsonb_typeof(d) is distinct from 'object' then raise exception 'Datos de fila incompatibles';end if;
 cols:=case kind when 'clients' then array['code','name','phone','email','taxId','address']
  when 'vehicles' then array['plate','country','vin','vehicle','engine','km','clientCode']
  when 'catalog' then array['reference','description','unit','priceCents','costCents','costKnown','taxBps','stockMilli','minMilli','supplier'] else null end;
 if cols is null or exists(select 1 from jsonb_object_keys(d) x where not x=any(cols)) or exists(select 1 from unnest(cols) x where not d?x) then raise exception 'Columnas incompatibles';end if;
 for k in select unnest(cols) loop
  if k not in ('km','priceCents','costCents','taxBps','stockMilli','minMilli','costKnown') and jsonb_typeof(d->k) is distinct from 'string' then raise exception 'Campo de texto incompatible: %',k;end if;
 end loop;
 if kind='clients' then
  perform private.require_text(d->>'code','Código',120);perform private.require_text(d->>'name','Nombre',120);
  if length(d->>'phone')>100 or length(d->>'email')>254 or length(d->>'taxId')>30 or length(d->>'address')>1000 or
   (d->>'email'<>'' and d->>'email'!~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then raise exception 'Revisa teléfono, email, NIF y dirección';end if;
  d:=d||jsonb_build_object('code',upper(trim(d->>'code')),'taxId',upper(trim(d->>'taxId')),'email',lower(trim(d->>'email')));
  select id into existing from private.clients where workshop_id=w and (code=d->>'code' or (d->>'taxId'<>'' and data->>'taxId'=d->>'taxId')) order by id limit 1;
  if existing is not null then return jsonb_build_object('status','duplicate','recordId',existing,'message','Cliente duplicado: se conserva el registro existente');end if;
  if writing then insert into private.clients(workshop_id,id,code,data) values(w,rid,d->>'code',d-'code');end if;
 elsif kind='vehicles' then
  plate_value:=regexp_replace(upper(trim(d->>'plate')),'[^A-Z0-9]','','g');country_value:=upper(d->>'country');vin_value:=upper(trim(d->>'vin'));
  if plate_value!~ '^[A-Z0-9]{2,20}$' or country_value!~ '^[A-Z]{2}$' or length(vin_value)>50 then raise exception 'Revisa matrícula, país y VIN';end if;
  perform private.require_text(d->>'vehicle','Vehículo',200);if length(d->>'engine')>200 then raise exception 'Motorización demasiado larga';end if;
  perform private.require_int(d->'km',0,10000000,'Kilometraje');
  select * into owner from private.clients where workshop_id=w and code=upper(trim(d->>'clientCode')) and active;
  if not found then raise exception 'Importa primero el código de cliente';end if;
  existing:=private.find_vehicle(w,plate_value,country_value,vin_value);
  if existing is not null then return jsonb_build_object('status','duplicate','recordId',existing,'message','Vehículo duplicado: se conservan propietario, matrícula e historial');end if;
  if writing then
   insert into private.vehicles(workshop_id,id,plate,country,vin,technical) values(w,rid,plate_value,country_value,nullif(vin_value,''),jsonb_build_object('vehicle',d->>'vehicle','engine',d->>'engine'));
   insert into private.vehicle_profiles values(w,rid,0,owner.id,jsonb_build_object('name',owner.data->>'name','phone',owner.data->>'phone'),(d->>'km')::bigint);
   insert into private.vehicle_identifiers values(w,rid,'plate',country_value,plate_value);
   if vin_value<>'' then insert into private.vehicle_identifiers values(w,rid,'vin','',vin_value);end if;
  end if;
 else
  perform private.require_text(d->>'reference','Referencia',120);perform private.require_text(d->>'description','Descripción',300);perform private.require_text(d->>'unit','Unidad',20);
  perform private.require_int(d->'priceCents',0,10000000,'Precio');perform private.require_int(d->'costCents',0,10000000,'Coste');perform private.require_int(d->'taxBps',0,10000,'IVA');
  perform private.require_int(d->'stockMilli',0,100000000,'Existencias');perform private.require_int(d->'minMilli',0,100000000,'Stock mínimo');
  if jsonb_typeof(d->'costKnown') is distinct from 'boolean' or length(d->>'supplier')>200 then raise exception 'Revisa coste y proveedor';end if;
  select id into existing from private.catalog where workshop_id=w and upper(reference)=upper(trim(d->>'reference'));
  if existing is not null then return jsonb_build_object('status','duplicate','recordId',existing,'message','Referencia duplicada: se conservan precios y existencias');end if;
  if writing then
   insert into private.catalog(workshop_id,id,reference,description,unit,price_cents,cost_cents,stock_milli,min_milli)
    values(w,rid,upper(trim(d->>'reference')),d->>'description',d->>'unit',(d->>'priceCents')::bigint,(d->>'costCents')::bigint,(d->>'stockMilli')::bigint,(d->>'minMilli')::bigint);
   insert into private.catalog_details values(w,rid,(d->>'taxBps')::int,true,(d->>'costKnown')::boolean,d->>'supplier');
  end if;
 end if;
 return jsonb_build_object('status',case when writing then 'created' else 'ready' end,'recordId',rid,'message',case when writing then 'Importado' else 'Listo para importar' end);
end $$;
create function private.import_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb;old private.command_receipts%rowtype;kind text;r jsonb;result jsonb;rows jsonb:='[]';writing boolean;rid uuid;line_number bigint;message text;created int:=0;seen uuid[]:='{}';keys text[]:='{}';rowkeys text[];key text;
begin
 m:=private.photo_device(w,dev);kind:=p->>'kind';writing:=action='import_commit';
 if m->>'role' not in ('office','admin') or (kind='catalog' and m->>'role'<>'admin') then raise exception 'Perfil sin permiso de importación' using errcode='42501';end if;
 if action is null or kind is null or action not in ('import_preview','import_commit') or kind not in ('clients','vehicles','catalog') or jsonb_typeof(p) is distinct from 'object' or cid is null then raise exception 'Importación incompatible';end if;
 if exists(select 1 from jsonb_object_keys(p) x where x not in ('kind','reason','rows')) then raise exception 'Campo de importación inesperado';end if;
 perform private.require_text(p->>'reason','Motivo',2000);
 if jsonb_typeof(p->'rows') is distinct from 'array' or jsonb_array_length(p->'rows') not between 1 and 500 then raise exception 'Selecciona entre 1 y 500 filas';end if;
 perform 1 from private.workshops where id=w for update;
 if writing then
  select * into old from private.command_receipts where workshop_id=w and id=cid;
  if found then
   if old.actor_id<>auth.uid() or old.device_id<>dev or old.action<>action or old.payload<>p then raise exception 'Command ID reused';end if;
   return old.result;
  end if;
 end if;
 for r in select value from jsonb_array_elements(p->'rows') loop
  if jsonb_typeof(r) is distinct from 'object' or exists(select 1 from jsonb_object_keys(r) x where x not in ('id','line','data')) then raise exception 'Fila incompatible';end if;
  rid:=(r->>'id')::uuid;line_number:=private.require_int(r->'line',2,1000000,'Fila');
  if rid is null or rid=any(seen) then raise exception 'Identificador de fila repetido';end if;seen:=array_append(seen,rid);
  begin
   result:=private.import_row(w,kind,rid,r->'data',writing);
   if not writing and result->>'status'='ready' then
    rowkeys:=case kind when 'clients' then array['code/'||upper(trim(r->'data'->>'code')),case when r->'data'->>'taxId'<>'' then 'tax/'||upper(trim(r->'data'->>'taxId')) else null end]
     when 'vehicles' then array['plate/'||upper(r->'data'->>'country')||'/'||regexp_replace(upper(r->'data'->>'plate'),'[^A-Z0-9]','','g'),case when r->'data'->>'vin'<>'' then 'vin/'||upper(trim(r->'data'->>'vin')) else null end]
     else array['reference/'||upper(trim(r->'data'->>'reference'))] end;
    if rowkeys && keys then result:=result||jsonb_build_object('status','duplicate','message','Duplicado dentro del archivo: se conserva la primera fila');
    else keys:=keys||array_remove(rowkeys,null);end if;
   end if;
   if result->>'status'='created' then
    created:=created+1;
    insert into private.audit(workshop_id,actor_id,operation_id,kind,after_data) values(w,auth.uid(),rid,'csv_row_imported',jsonb_build_object('batchId',cid,'kind',kind,'line',line_number,'data',r->'data','reason',p->>'reason'));
   end if;
  exception when others then
   get stacked diagnostics message=message_text;
   result:=jsonb_build_object('status','error','message',case when sqlstate in ('23505','23503','22P02') then 'Identificador o referencia incompatible; revisa la fila' else message end);
  end;
  rows:=rows||jsonb_build_array(result||jsonb_build_object('id',rid,'line',line_number));
 end loop;
 result:=jsonb_build_object('rows',rows,'created',created,'batchId',cid,'kind',kind);
 if writing then
  if kind='catalog' and created>0 then insert into private.management_state values(w,1) on conflict(workshop_id) do update set revision=private.management_state.revision+1;end if;
  insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,result);
  insert into private.audit(workshop_id,actor_id,operation_id,kind,after_data) values(w,auth.uid(),cid,'csv_import',jsonb_build_object('kind',kind,'created',created,'rows',rows,'reason',p->>'reason'));
 end if;
 return result;
end $$;
create function public.import_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.import_command($1,$2,$3,$4,$5) $$;
revoke all on function private.seed_clients(uuid),private.import_row(uuid,text,uuid,jsonb,boolean),private.import_command(uuid,uuid,uuid,text,jsonb),public.import_command(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.import_command(uuid,uuid,uuid,text,jsonb),public.import_command(uuid,uuid,uuid,text,jsonb) to authenticated;
alter function private.snapshot(uuid) rename to snapshot_before_clients;
create function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;r jsonb;
begin
 m:=private.membership(w);r:=private.snapshot_before_clients(w);
 return r||jsonb_build_object('clients',case when m->>'role' in ('office','admin') then
  (select coalesce(jsonb_agg(data||jsonb_build_object('id',id,'code',code,'active',active)), '[]') from private.clients where workshop_id=w) else '[]'::jsonb end);
end $$;
revoke all on function private.snapshot_before_clients(uuid),private.snapshot(uuid) from public,anon,authenticated;
grant execute on function private.snapshot(uuid) to authenticated;

create or replace function private.backup_tables() returns text[] language sql immutable set search_path='' as $$
 select array['clients','members','member_permissions','vehicles','vehicle_profiles','vehicle_identifiers','vehicle_changes','catalog','catalog_details','templates','management_state','devices','device_sessions','orders','order_recipient_refs','operations','time_sessions',
 'close_requests','order_devices','close_acknowledgements','resolutions','command_receipts','documents','account_requests','audit','order_photos']::text[]
$$;
create or replace function private.export_workshop(w uuid,dev uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare t text; rows jsonb; tables jsonb:='{}'; workshop jsonb;
begin
 perform private.backup_admin(w,dev);
 select to_jsonb(x) into workshop from private.workshops x where id=w for update;
 foreach t in array private.backup_tables() loop
  execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from private.%I x where workshop_id=$1',t)
   into rows using w;
  tables:=tables||jsonb_build_object(t,rows);
 end loop;
 return jsonb_build_object('serverFormat',1,'databaseVersion',7,'workshopId',w,
  'exportedAt',now(),'workshop',workshop,'tables',tables,
  'restorationHistory',coalesce((select jsonb_agg(to_jsonb(x)) from private.restores x where workshop_id=w),'[]'),
  'externalFiles','[]'::jsonb,'authExcluded',true,'photoFiles',(select coalesce(jsonb_agg(private.photo_json(p)||jsonb_build_object('filePresent',exists(select 1 from storage.objects where bucket_id='tallerflow-photos' and name=p.path))), '[]'::jsonb) from private.order_photos p where p.workshop_id=w));
end $$;
create or replace function private.restore_workshop(w uuid,dev uuid,rid uuid,a jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare previous private.restores%rowtype; t text; r jsonb; tables jsonb; cols text; result jsonb:='{}'; n bigint;
begin
 perform private.backup_admin(w,dev);
 perform 1 from private.workshops where id=w for update;
 if rid is null then raise exception 'Stable restore ID required'; end if;
 select * into previous from private.restores where workshop_id=w and id=rid;
 if found then
  if previous.archive<>a or previous.actor_id<>auth.uid() then raise exception 'Restore ID reused'; end if;
  return previous.result;
 end if;
 if a->>'serverFormat' is distinct from '1' or coalesce(a->>'databaseVersion','') not in ('2','3','4','5','6','7') or a->>'workshopId' is distinct from w::text
  or a->'workshop'->>'id' is distinct from w::text or a->>'authExcluded' is distinct from 'true' then raise exception 'Incompatible workshop archive'; end if;
 tables:=a->'tables';
 if a->>'databaseVersion'<>'7' then tables:=tables||jsonb_build_object('clients','[]'::jsonb);end if;
 if a->>'databaseVersion' in ('2','3','4','5') then tables:=tables||jsonb_build_object('order_photos','[]'::jsonb);end if;
 if a->>'databaseVersion' in ('2','3','4') then tables:=jsonb_build_object('vehicle_profiles','[]'::jsonb,'vehicle_identifiers','[]'::jsonb,'vehicle_changes','[]'::jsonb,'order_recipient_refs','[]'::jsonb)||tables;end if;
 if a->>'databaseVersion' in ('2','3') then tables:=jsonb_build_object('account_requests','[]'::jsonb)||tables;end if;
 if a->>'databaseVersion'='2' then tables:=jsonb_build_object('member_permissions','[]'::jsonb,'catalog_details','[]'::jsonb,'templates','[]'::jsonb,'management_state','[]'::jsonb)||tables;end if;
 if jsonb_typeof(tables) is distinct from 'object' then raise exception 'Missing archive tables'; end if;
 if exists(select 1 from jsonb_object_keys(tables) k where not k=any(private.backup_tables())) then raise exception 'Unknown archive table'; end if;
 if exists(select 1 from private.clients where workshop_id=w) or exists(select 1 from private.order_photos where workshop_id=w) or exists(select 1 from private.orders where workshop_id=w) or exists(select 1 from private.operations where workshop_id=w)
  or exists(select 1 from private.documents where workshop_id=w) or exists(select 1 from private.catalog where workshop_id=w)
  or exists(select 1 from private.templates where workshop_id=w) or exists(select 1 from private.management_state where workshop_id=w)
  or exists(select 1 from private.vehicle_profiles where workshop_id=w) or exists(select 1 from private.vehicle_changes where workshop_id=w) or exists(select 1 from private.vehicles where workshop_id=w) or exists(select 1 from private.restores where workshop_id=w)
  or exists(select 1 from private.devices where workshop_id=w and id<>dev)
  or exists(select 1 from private.members where workshop_id=w and user_id<>auth.uid()) then
  raise exception 'Restore requires an empty isolated workshop with only its bootstrap administrator and current device';
 end if;
 foreach t in array private.backup_tables() loop
  if jsonb_typeof(tables->t) is distinct from 'array' then raise exception 'Missing or invalid archive table: %',t; end if;
  for r in select value from jsonb_array_elements(tables->t) loop
   if r->>'workshop_id'<>w::text or r->>'workshop_id' is null then raise exception 'Cross-workshop archive row'; end if;
  end loop;
 end loop;
 if not exists(select 1 from jsonb_array_elements(tables->'members') m where m->>'user_id'=auth.uid()::text
  and m->>'role'='admin' and (m->>'active')::boolean) then raise exception 'Bootstrap administrator must remain active'; end if;
 if exists(select 1 from jsonb_array_elements(tables->'members') m where not exists(select 1 from auth.users u where u.id=(m->>'user_id')::uuid)) then
  raise exception 'Auth identities must exist with their original IDs before restoring application data';
 end if;
 if exists(select 1 from jsonb_array_elements(tables->'devices') d where d->>'id'=dev::text) then
  raise exception 'Use a new authenticated device identity in the recovery environment';
 end if;
 update private.workshops set name=a->'workshop'->>'name',billing_country=a->'workshop'->>'billing_country',
  settings=a->'workshop'->'settings' where id=w;
 insert into private.members select * from jsonb_populate_recordset(null::private.members,tables->'members')
  on conflict(workshop_id,user_id) do update set display_name=excluded.display_name,role=excluded.role,
   see_prices=excluded.see_prices,active=excluded.active;
 foreach t in array private.backup_tables() loop
  if t='members' then continue; end if;
  if t='devices' then
   insert into private.devices(workshop_id,id,user_id,last_seen,auth_session_id,retired_at,retirement_reason)
    select workshop_id,id,user_id,last_seen,null,coalesce(retired_at,now()),
     coalesce(retirement_reason,'Identidad histórica restaurada; requiere recuperación y revisión, no acredita sincronización')
    from jsonb_populate_recordset(null::private.devices,tables->t);
  elsif t='close_requests' then
   insert into private.close_requests select workshop_id,id,order_id,revision,
    case when status='active' then 'invalidated' else status end,requested_by,requested_at,exception_reason,retired_devices
    from jsonb_populate_recordset(null::private.close_requests,tables->t);
  elsif t='order_photos' then
   if exists(select 1 from jsonb_array_elements(tables->t) x where x->>'status'='attached' and not exists(select 1 from jsonb_array_elements(coalesce(a->'photoFiles','[]'::jsonb)) f where f->>'id'=x->>'id' and f->>'sha256'=x->>'sha256' and f->>'filePresent'='true')) then raise exception 'Attached photo file manifest missing';end if;
   insert into private.order_photos(workshop_id,id,order_id,actor_id,device_id,original_device_id,sha256,byte_size,mime,caption,captured_at,created_at,status,verified_at,recovery,restored,restore_file_expected,restore_upload_device_id)
    select workshop_id,id,order_id,actor_id,device_id,original_device_id,sha256,byte_size,mime,caption,captured_at,created_at,
     case when status='pending' then 'review' else status end,verified_at,true,true,
     exists(select 1 from jsonb_array_elements(coalesce(a->'photoFiles','[]'::jsonb)) f where f->>'id'=p.id::text and f->>'filePresent'='true'),dev
    from jsonb_populate_recordset(null::private.order_photos,tables->t) p;
  elsif t='audit' then
   insert into private.audit(workshop_id,actor_id,operation_id,order_id,occurred_at,kind,before_data,after_data,source_id)
    select workshop_id,actor_id,operation_id,order_id,occurred_at,kind,before_data,after_data,coalesce(source_id,id)
    from jsonb_populate_recordset(null::private.audit,tables->t);
  else
   select string_agg(quote_ident(column_name),',' order by ordinal_position) into cols from information_schema.columns
    where table_schema='private' and table_name=t and is_generated='NEVER';
   execute format('insert into private.%I (%s) select %s from jsonb_populate_recordset(null::private.%I,$1)',t,cols,cols,t)
    using tables->t;
  end if;
  get diagnostics n=row_count;
  result:=result||jsonb_build_object(t,n);
 end loop;
 perform private.seed_vehicle_history(w);
 perform private.seed_clients(w);
 -- No Auth session or successful closure confirmation is restored as active authority.
 result:=jsonb_build_object('restored',true,'counts',result,'requiresDeviceReview',true,'restoreId',rid);
 insert into private.restores(workshop_id,id,actor_id,device_id,archive,result) values(w,rid,auth.uid(),dev,a,result);
 insert into private.audit(workshop_id,actor_id,kind,after_data) values(w,auth.uid(),'restore_workshop',
  jsonb_build_object('restoreId',rid,'counts',result->'counts','deviceId',dev,'originalClosureConfirmationsInvalidated',true));
 return result;
end $$;





commit;
