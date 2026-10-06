-- Portable application archives. Auth passwords, tokens and sessions are excluded.
begin;
create table private.restores (
 workshop_id uuid not null references private.workshops(id), id uuid not null,
 actor_id uuid not null, device_id uuid not null, archive jsonb not null,
 result jsonb not null, restored_at timestamptz not null default now(),
 primary key(workshop_id,id)
);
alter table private.restores enable row level security;
revoke all on private.restores from public,anon,authenticated;
create trigger restores_immutable before update or delete on private.restores
 for each row execute function private.immutable_document();
alter table private.audit add column source_id bigint;
create function private.backup_tables() returns text[] language sql immutable set search_path='' as $$
 select array['members','vehicles','catalog','devices','device_sessions','orders','operations','time_sessions',
 'close_requests','order_devices','close_acknowledgements','resolutions','command_receipts','documents','audit']::text[]
$$;
create function private.backup_admin(w uuid,dev uuid) returns void language plpgsql security definer set search_path='' as $$
declare m jsonb;
begin
 m:=private.membership(w);
 if m->>'role'<>'admin' then raise exception 'Administrator required' using errcode='42501'; end if;
 if not exists(select 1 from private.devices where workshop_id=w and id=dev and user_id=auth.uid()
  and retired_at is null and auth_session_id=private.auth_session()) then
  raise exception 'Active authenticated device required' using errcode='42501';
 end if;
end $$;
create function private.export_workshop(w uuid,dev uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare t text; rows jsonb; tables jsonb:='{}'; workshop jsonb;
begin
 perform private.backup_admin(w,dev);
 select to_jsonb(x) into workshop from private.workshops x where id=w for update;
 foreach t in array private.backup_tables() loop
  execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from private.%I x where workshop_id=$1',t)
   into rows using w;
  tables:=tables||jsonb_build_object(t,rows);
 end loop;
 return jsonb_build_object('serverFormat',1,'databaseVersion',2,'workshopId',w,
  'exportedAt',now(),'workshop',workshop,'tables',tables,
  'restorationHistory',coalesce((select jsonb_agg(to_jsonb(x)) from private.restores x where workshop_id=w),'[]'),
  'externalFiles','[]'::jsonb,'authExcluded',true);
end $$;
create function private.restore_workshop(w uuid,dev uuid,rid uuid,a jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
 if a->>'serverFormat'<>'1' or a->>'databaseVersion'<>'2' or a->>'workshopId'<>w::text
  or a->'workshop'->>'id'<>w::text or a->>'authExcluded'<>'true' then raise exception 'Incompatible workshop archive'; end if;
 tables:=a->'tables';
 if jsonb_typeof(tables)<>'object' then raise exception 'Missing archive tables'; end if;
 if exists(select 1 from jsonb_object_keys(tables) k where not k=any(private.backup_tables())) then raise exception 'Unknown archive table'; end if;
 if exists(select 1 from private.orders where workshop_id=w) or exists(select 1 from private.operations where workshop_id=w)
  or exists(select 1 from private.documents where workshop_id=w) or exists(select 1 from private.catalog where workshop_id=w)
  or exists(select 1 from private.vehicles where workshop_id=w) or exists(select 1 from private.restores where workshop_id=w)
  or exists(select 1 from private.devices where workshop_id=w and id<>dev)
  or exists(select 1 from private.members where workshop_id=w and user_id<>auth.uid()) then
  raise exception 'Restore requires an empty isolated workshop with only its bootstrap administrator and current device';
 end if;
 foreach t in array private.backup_tables() loop
  if jsonb_typeof(tables->t)<>'array' then raise exception 'Missing or invalid archive table: %',t; end if;
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
create function public.export_workshop(workshop_id uuid,device_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.export_workshop($1,$2) $$;
create function public.restore_workshop(workshop_id uuid,device_id uuid,restore_id uuid,archive jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.restore_workshop($1,$2,$3,$4) $$;
revoke all on function private.backup_tables(),private.backup_admin(uuid,uuid),private.export_workshop(uuid,uuid),private.restore_workshop(uuid,uuid,uuid,jsonb),public.export_workshop(uuid,uuid),public.restore_workshop(uuid,uuid,uuid,jsonb) from public,anon;
grant execute on function private.export_workshop(uuid,uuid),private.restore_workshop(uuid,uuid,uuid,jsonb),public.export_workshop(uuid,uuid),public.restore_workshop(uuid,uuid,uuid,jsonb) to authenticated;
commit;
