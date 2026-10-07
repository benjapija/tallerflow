begin;
create table private.fleet_state(workshop_id uuid primary key references private.workshops(id),data jsonb not null,
 check(jsonb_typeof(data)='object' and data ?& array['revision','groups'] and (data->>'revision')::bigint>=0 and jsonb_typeof(data->'groups')='array'));
alter table private.fleet_state enable row level security;revoke all on private.fleet_state from public,anon,authenticated;
create function private.fleet_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb;d jsonb;previous private.command_receipts%rowtype;old jsonb;value jsonb;event jsonb;rows jsonb;gid uuid;mid uuid;vid uuid;rev bigint;version jsonb;reason text;membership jsonb;vp private.vehicle_profiles%rowtype;result jsonb;
begin
 m:=private.photo_device(w,dev);if m->>'role' not in ('admin','office') then raise exception 'Office permission required' using errcode='42501';end if;
 if not private.photo_files_ready(w) then raise exception 'Recover original files before new work';end if;
 perform 1 from private.workshops where id=w for update;
 if cid is null or jsonb_typeof(p) is distinct from 'object' then raise exception 'Command and payload required';end if;
 select * into previous from private.command_receipts where workshop_id=w and id=cid;
 if found then if previous.actor_id<>auth.uid() or previous.device_id<>dev or previous.action<>action or previous.payload<>p then raise exception 'Command ID reused';end if;return previous.result;end if;
 select data into d from private.fleet_state where workshop_id=w;d:=coalesce(d,'{"revision":0,"groups":[]}');rev:=(d->>'revision')::bigint;
 if private.require_int(p->'revision',0,9007199254740991,'Revision')<>rev then raise exception 'Fleet revision conflict';end if;
 gid:=(p->>'id')::uuid;if gid is null then raise exception 'Fleet ID required';end if;
 reason:=private.require_text(p->>'reason','Reason',2000);event:=jsonb_build_object('id',cid,'kind',action,'actorId',auth.uid(),'at',now(),'reason',reason);
 select x into old from jsonb_array_elements(d->'groups') x where x->>'id'=gid::text;
 if action='fleet_group' then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','revision','name','organization','reason'])) then raise exception 'Unsupported fleet fields';end if;
  if old->>'status'='archived' then raise exception 'Create new fleet to preserve archive';end if;
  version:=jsonb_build_object('name',private.require_text(p->>'name','Fleet name',300),'organization',private.require_text(p->>'organization','Confirmed organization or manager',300),'actorId',auth.uid(),'at',now());
  value:=version||jsonb_build_object('id',gid,'status','active','versions',coalesce(old->'versions','[]')||jsonb_build_array(version),'memberships',coalesce(old->'memberships','[]'),'events',coalesce(old->'events','[]')||jsonb_build_array(event));
 else
  if old is null or old->>'status'<>'active' then raise exception 'Active fleet required';end if;value:=old;
  if action='fleet_attach' then
   if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','revision','membershipId','vehicleId','ownerId','reference','evidence','reason'])) then raise exception 'Unsupported membership fields';end if;
   mid:=(p->>'membershipId')::uuid;vid:=(p->>'vehicleId')::uuid;if mid is null or vid is null then raise exception 'Membership and vehicle IDs required';end if;
   if exists(select 1 from jsonb_array_elements(d->'groups') g,jsonb_array_elements(g->'memberships') x where x->>'id'=mid::text) then raise exception 'Membership ID already used';end if;
   select * into vp from private.vehicle_profiles where workshop_id=w and vehicle_id=vid;
   if not found or p->>'ownerId' is distinct from vp.owner_id::text then raise exception 'Review current vehicle and owner';end if;
   if exists(select 1 from jsonb_array_elements(d->'groups') g,jsonb_array_elements(g->'memberships') x where g->>'status'='active' and x->>'status'='active' and x->>'vehicleId'=vid::text) then raise exception 'Remove previous fleet membership first';end if;
   membership:=jsonb_build_object('id',mid,'vehicleId',vid,'ownerId',vp.owner_id,'ownerSnapshot',vp.owner_data,'reference',private.require_text(p->>'reference','Internal vehicle reference',100),'evidence',private.require_text(p->>'evidence','Membership verification',2000),'status','active','addedBy',auth.uid(),'addedAt',now(),'removedBy',null,'removedAt',null);
   value:=jsonb_set(value,'{memberships}',value->'memberships'||jsonb_build_array(membership));
  elsif action='fleet_detach' then
   if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','revision','membershipId','reason'])) then raise exception 'Unsupported removal fields';end if;
   mid:=(p->>'membershipId')::uuid;select x into membership from jsonb_array_elements(value->'memberships') x where x->>'id'=mid::text;
   if membership is null or membership->>'status'<>'active' then raise exception 'Active membership required';end if;
   select coalesce(jsonb_agg(case when x->>'id'=mid::text then x||jsonb_build_object('status','removed','removedBy',auth.uid(),'removedAt',now()) else x end),'[]') into rows from jsonb_array_elements(value->'memberships') x;value:=jsonb_set(value,'{memberships}',rows);
  elsif action='fleet_archive' then
   if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','revision','reason'])) or exists(select 1 from jsonb_array_elements(value->'memberships') x where x->>'status'='active') then raise exception 'Remove vehicles before archiving fleet';end if;
   value:=jsonb_set(value,'{status}','"archived"');
  else raise exception 'Unsupported fleet action';end if;
  value:=jsonb_set(value,'{events}',value->'events'||jsonb_build_array(event));
 end if;
 select coalesce(jsonb_agg(x),'[]') into rows from jsonb_array_elements(d->'groups') x where x->>'id'<>gid::text;
 d:=jsonb_build_object('revision',rev+1,'groups',rows||jsonb_build_array(value));insert into private.fleet_state values(w,d) on conflict(workshop_id) do update set data=excluded.data;
 result:=jsonb_build_object('saved',true,'revision',rev+1);insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,result);
 insert into private.audit(workshop_id,actor_id,operation_id,kind,before_data,after_data) values(w,auth.uid(),cid,action,old,value);return result;
end $$;
create function public.fleet_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.fleet_command($1,$2,$3,$4,$5)$$;
alter function private.snapshot(uuid) rename to snapshot_before_fleets;
create function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;r jsonb;d jsonb;begin m:=private.membership(w);r:=private.snapshot_before_fleets(w);
 if m->>'role'='technician' then d:='{"revision":0,"groups":[]}';else select data into d from private.fleet_state where workshop_id=w;d:=coalesce(d,'{"revision":0,"groups":[]}');end if;
 return r||jsonb_build_object('fleets',d);end $$;
alter function private.backup_tables() rename to backup_tables_before_fleets;
create function private.backup_tables() returns text[] language sql immutable set search_path='' as $$select private.backup_tables_before_fleets()||array['fleet_state']::text[]$$;
alter function private.export_workshop(uuid,uuid) rename to export_workshop_before_fleets;
create function private.export_workshop(w uuid,dev uuid) returns jsonb language sql security definer set search_path='' as $$select private.export_workshop_before_fleets(w,dev)||jsonb_build_object('databaseVersion',13)$$;
create function private.validate_fleets(w uuid,d jsonb) returns void language plpgsql security definer set search_path='' as $$
declare g jsonb;m jsonb;v jsonb;e jsonb;begin
 if jsonb_typeof(d) is distinct from 'object' or jsonb_typeof(d->'revision') is distinct from 'number' or jsonb_typeof(d->'groups') is distinct from 'array' then raise exception 'Malformed fleet state';end if;perform private.require_int(d->'revision',0,9007199254740991,'Fleet revision');
 if (select count(*) from jsonb_array_elements(d->'groups'))<>(select count(distinct x->>'id') from jsonb_array_elements(d->'groups') x) then raise exception 'Duplicate fleet';end if;
 if (select count(*) from jsonb_array_elements(d->'groups') qgrp,jsonb_array_elements(qgrp->'memberships') qmem)<>(select count(distinct qmem->>'id') from jsonb_array_elements(d->'groups') qgrp,jsonb_array_elements(qgrp->'memberships') qmem) then raise exception 'Duplicate membership';end if;
 if exists(select 1 from jsonb_array_elements(d->'groups') qgrp,jsonb_array_elements(qgrp->'memberships') qmem where qgrp->>'status'='active' and qmem->>'status'='active' group by qmem->>'vehicleId' having count(*)>1) then raise exception 'Duplicate active vehicle';end if;
 for g in select value from jsonb_array_elements(d->'groups') loop
  if (g->>'id')::uuid is null or g->>'status' is null or g->>'status' not in ('active','archived') or jsonb_typeof(g->'memberships') is distinct from 'array' or jsonb_typeof(g->'versions') is distinct from 'array' or jsonb_array_length(g->'versions')=0 or jsonb_typeof(g->'events') is distinct from 'array' or jsonb_array_length(g->'events')=0 then raise exception 'Malformed fleet';end if;
  perform private.require_text(g->>'name','Fleet name',300);perform private.require_text(g->>'organization','Organization',300);
  for v in select value from jsonb_array_elements(g->'versions') loop
   perform private.require_text(v->>'name','Version name',300);perform private.require_text(v->>'organization','Version organization',300);perform private.planning_date(v->'at');if not exists(select 1 from private.members where workshop_id=w and user_id=(v->>'actorId')::uuid) then raise exception 'Fleet version actor';end if;
  end loop;
  for e in select value from jsonb_array_elements(g->'events') loop
   perform private.require_text(e->>'reason','Event reason',2000);perform private.planning_date(e->'at');if (e->>'id')::uuid is null or e->>'kind' is null or e->>'kind' not in ('fleet_group','fleet_attach','fleet_detach','fleet_archive') or not exists(select 1 from private.members where workshop_id=w and user_id=(e->>'actorId')::uuid) then raise exception 'Fleet event';end if;
  end loop;
  for m in select value from jsonb_array_elements(g->'memberships') loop
   if (m->>'id')::uuid is null or (m->>'ownerId')::uuid is null or not exists(select 1 from private.vehicle_profiles where workshop_id=w and vehicle_id=(m->>'vehicleId')::uuid) or m->>'status' is null or m->>'status' not in ('active','removed') or jsonb_typeof(m->'ownerSnapshot') is distinct from 'object' or not exists(select 1 from private.members where workshop_id=w and user_id=(m->>'addedBy')::uuid) then raise exception 'Malformed fleet membership';end if;
   perform private.require_text(m->'ownerSnapshot'->>'name','Original owner',300);perform private.require_text(m->>'reference','Reference',100);perform private.require_text(m->>'evidence','Evidence',2000);perform private.planning_date(m->'addedAt');
   if m->>'status'='removed' then perform private.planning_date(m->'removedAt');if (m->>'removedAt')::timestamptz<(m->>'addedAt')::timestamptz or not exists(select 1 from private.members where workshop_id=w and user_id=(m->>'removedBy')::uuid) then raise exception 'Removal evidence';end if;
   elsif m->>'removedAt' is not null or m->>'removedBy' is not null or g->>'status'='archived' then raise exception 'Archived fleet has active membership';end if;
  end loop;
 end loop;
end $$;
alter function private.restore_workshop(uuid,uuid,uuid,jsonb) rename to restore_workshop_before_fleets;
create function private.restore_workshop(w uuid,dev uuid,rid uuid,a jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare normalized jsonb:=a;result jsonb;d jsonb;begin
 perform private.backup_admin(w,dev);
 if exists(select 1 from private.fleet_state where workshop_id=w) and not exists(select 1 from private.restores where workshop_id=w and id=rid) then raise exception 'Restore requires empty isolated fleet state';end if;
 if a->>'databaseVersion'='13' then if jsonb_typeof(a->'tables'->'fleet_state') is distinct from 'array' then raise exception 'Fleet table missing';end if;normalized:=a||jsonb_build_object('databaseVersion',12);
 elsif a->>'databaseVersion' in ('2','3','4','5','6','7','8','9','10','11','12') then normalized:=jsonb_set(a,'{tables,fleet_state}',coalesce(a->'tables'->'fleet_state','[]'));end if;
 result:=private.restore_workshop_before_fleets(w,dev,rid,normalized);for d in select data from private.fleet_state where workshop_id=w loop perform private.validate_fleets(w,d);end loop;return result;
end $$;
revoke all on function private.fleet_command(uuid,uuid,uuid,text,jsonb),public.fleet_command(uuid,uuid,uuid,text,jsonb),private.snapshot_before_fleets(uuid),private.snapshot(uuid),private.backup_tables_before_fleets(),private.backup_tables(),private.export_workshop_before_fleets(uuid,uuid),private.export_workshop(uuid,uuid),private.validate_fleets(uuid,jsonb),private.restore_workshop_before_fleets(uuid,uuid,uuid,jsonb),private.restore_workshop(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.fleet_command(uuid,uuid,uuid,text,jsonb),public.fleet_command(uuid,uuid,uuid,text,jsonb),private.snapshot(uuid),private.export_workshop(uuid,uuid),private.restore_workshop(uuid,uuid,uuid,jsonb) to authenticated;
commit;
