-- Auth provisioning is performed only by the server; passwords never enter SQL.
begin;
create table private.account_requests (
 workshop_id uuid not null references private.workshops(id),id uuid not null,actor_id uuid not null,
 device_id uuid not null,session_id uuid not null,payload jsonb not null,
 created_user uuid,requested_at timestamptz not null default now(),completed_at timestamptz,
 primary key(workshop_id,id),foreign key(workshop_id,device_id) references private.devices(workshop_id,id)
);
alter table private.account_requests enable row level security;
revoke all on private.account_requests from public,anon,authenticated;
create function private.prepare_account(w uuid,dev uuid,rid uuid,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare previous private.account_requests%rowtype;v jsonb;requested_email text;begin
 perform private.backup_admin(w,dev);perform 1 from private.workshops where id=w for update;
 if rid is null then raise exception 'Request ID required';end if;
 requested_email:=lower(trim(p->>'email'));
 if requested_email is null or length(requested_email)>254 or requested_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Valid account email required';end if;
 if p->>'role' is null or p->>'role' not in ('technician','office','admin') or jsonb_typeof(p->'seePrices') is distinct from 'boolean' or jsonb_typeof(p->'seeCosts') is distinct from 'boolean' then raise exception 'Invalid account permissions';end if;
 if p->>'role'='technician' and p->>'seeCosts'='true' and p->>'seePrices'<>'true' then raise exception 'Cost access requires price access';end if;
 v:=jsonb_build_object('email',requested_email,'name',private.require_text(p->>'name','Name',120),'role',p->>'role','seePrices',p->'seePrices','seeCosts',p->'seeCosts','reason',private.require_text(p->>'reason','Reason'));
 select * into previous from private.account_requests where workshop_id=w and id=rid;
 if found then
  if previous.actor_id<>auth.uid() or previous.device_id<>dev or previous.payload<>v then raise exception 'Account request ID reused';end if;
  return jsonb_build_object('prepared',true,'requestId',rid,'completed',previous.completed_at is not null,'userId',previous.created_user);
 end if;
 if exists(select 1 from auth.users where lower(auth.users.email)=requested_email) then raise exception 'An Auth account already uses this email; an administrator must review its existing identity';end if;
 insert into private.account_requests(workshop_id,id,actor_id,device_id,session_id,payload) values(w,rid,auth.uid(),dev,private.auth_session(),v);
 return jsonb_build_object('prepared',true,'requestId',rid,'completed',false,'userId',null);
end $$;
create function private.account_state(w uuid,rid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.account_requests%rowtype;uid uuid;begin
 select * into r from private.account_requests where workshop_id=w and id=rid;
 if not found then raise exception 'Prepared account request required';end if;
 if not exists(select 1 from private.members where workshop_id=w and user_id=r.actor_id and active and role='admin') or
  not exists(select 1 from private.devices where workshop_id=w and id=r.device_id and user_id=r.actor_id and retired_at is null and auth_session_id=r.session_id) or
  not exists(select 1 from auth.sessions where id=r.session_id and user_id=r.actor_id) then raise exception 'Request administrator or device is no longer authorized';end if;
 select id into uid from auth.users where raw_app_meta_data->>'tallerflow_request'=rid::text and raw_app_meta_data->>'tallerflow_workshop'=w::text and lower(email)=r.payload->>'email';
 return jsonb_build_object('payload',r.payload,'userId',uid,'completed',r.completed_at is not null);
end $$;
create function private.finish_account(w uuid,rid uuid,uid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.account_requests%rowtype;state jsonb;rev bigint;begin
 perform 1 from private.workshops where id=w for update;
 state:=private.account_state(w,rid);select * into r from private.account_requests where workshop_id=w and id=rid for update;
 if uid is null or state->>'userId' is distinct from uid::text then raise exception 'Auth identity does not match this creation request';end if;
 if r.completed_at is not null then return jsonb_build_object('created',true,'userId',r.created_user);end if;
 insert into private.members values(w,uid,r.payload->>'name',r.payload->>'role',(r.payload->>'seePrices')::boolean,true);
 insert into private.member_permissions values(w,uid,(r.payload->>'seeCosts')::boolean);
 insert into private.management_state values(w,1) on conflict(workshop_id) do update set revision=private.management_state.revision+1 returning revision into rev;
 update private.account_requests set created_user=uid,completed_at=now() where workshop_id=w and id=rid;
 update private.close_requests set status='invalidated' where workshop_id=w and status='active';
 insert into private.audit(workshop_id,actor_id,operation_id,kind,after_data) values(w,r.actor_id,rid,'account_created',jsonb_build_object('userId',uid,'name',r.payload->>'name','role',r.payload->>'role','reason',r.payload->>'reason','revision',rev));
 return jsonb_build_object('created',true,'userId',uid);
end $$;
create function public.prepare_account(workshop_id uuid,device_id uuid,request_id uuid,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.prepare_account($1,$2,$3,$4) $$;
create function public.account_provision_state(workshop_id uuid,request_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.account_state($1,$2) $$;
create function public.finish_account_provision(workshop_id uuid,request_id uuid,user_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.finish_account($1,$2,$3) $$;
revoke all on function private.prepare_account(uuid,uuid,uuid,jsonb),public.prepare_account(uuid,uuid,uuid,jsonb),private.account_state(uuid,uuid),private.finish_account(uuid,uuid,uuid),public.account_provision_state(uuid,uuid),public.finish_account_provision(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function private.prepare_account(uuid,uuid,uuid,jsonb),public.prepare_account(uuid,uuid,uuid,jsonb) to authenticated;
grant usage on schema private to service_role;
grant execute on function private.account_state(uuid,uuid),private.finish_account(uuid,uuid,uuid),public.account_provision_state(uuid,uuid),public.finish_account_provision(uuid,uuid,uuid) to service_role;

create or replace function private.backup_tables() returns text[] language sql immutable set search_path='' as $$
 select array['members','member_permissions','vehicles','catalog','catalog_details','templates','management_state','devices','device_sessions','orders','operations','time_sessions',
 'close_requests','order_devices','close_acknowledgements','resolutions','command_receipts','documents','account_requests','audit']::text[]
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
 return jsonb_build_object('serverFormat',1,'databaseVersion',4,'workshopId',w,
  'exportedAt',now(),'workshop',workshop,'tables',tables,
  'restorationHistory',coalesce((select jsonb_agg(to_jsonb(x)) from private.restores x where workshop_id=w),'[]'),
  'externalFiles','[]'::jsonb,'authExcluded',true);
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
 if a->>'serverFormat' is distinct from '1' or coalesce(a->>'databaseVersion','') not in ('2','3','4') or a->>'workshopId' is distinct from w::text
  or a->'workshop'->>'id' is distinct from w::text or a->>'authExcluded' is distinct from 'true' then raise exception 'Incompatible workshop archive'; end if;
 tables:=a->'tables';
 if a->>'databaseVersion' in ('2','3') then tables:=jsonb_build_object('account_requests','[]'::jsonb)||tables;end if;
 if a->>'databaseVersion'='2' then tables:=jsonb_build_object('member_permissions','[]'::jsonb,'catalog_details','[]'::jsonb,'templates','[]'::jsonb,'management_state','[]'::jsonb)||tables;end if;
 if jsonb_typeof(tables) is distinct from 'object' then raise exception 'Missing archive tables'; end if;
 if exists(select 1 from jsonb_object_keys(tables) k where not k=any(private.backup_tables())) then raise exception 'Unknown archive table'; end if;
 if exists(select 1 from private.orders where workshop_id=w) or exists(select 1 from private.operations where workshop_id=w)
  or exists(select 1 from private.documents where workshop_id=w) or exists(select 1 from private.catalog where workshop_id=w)
  or exists(select 1 from private.templates where workshop_id=w) or exists(select 1 from private.management_state where workshop_id=w)
  or exists(select 1 from private.vehicles where workshop_id=w) or exists(select 1 from private.restores where workshop_id=w)
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
 -- No Auth session or successful closure confirmation is restored as active authority.
 result:=jsonb_build_object('restored',true,'counts',result,'requiresDeviceReview',true,'restoreId',rid);
 insert into private.restores(workshop_id,id,actor_id,device_id,archive,result) values(w,rid,auth.uid(),dev,a,result);
 insert into private.audit(workshop_id,actor_id,kind,after_data) values(w,auth.uid(),'restore_workshop',
  jsonb_build_object('restoreId',rid,'counts',result->'counts','deviceId',dev,'originalClosureConfirmationsInvalidated',true));
 return result;
end $$;


commit;
