begin;
create table private.planning_state(
 workshop_id uuid primary key references private.workshops(id), data jsonb not null,
 check(jsonb_typeof(data)='object' and data ?& array['revision','resources','bookings'] and (data->>'revision')::bigint>=0 and jsonb_typeof(data->'resources')='array' and jsonb_typeof(data->'bookings')='array')
);
alter table private.planning_state enable row level security;
revoke all on private.planning_state from public,anon,authenticated;
create function private.planning_date(v jsonb) returns timestamptz language plpgsql immutable set search_path='' as $$
declare t text;d timestamptz;begin
 if jsonb_typeof(v) is distinct from 'string' then raise exception 'Explicit date and timezone required';end if;t:=v#>>'{}';
 if t !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})$' or substring(t,1,4)::int not between 2000 and 2100 or substring(t,12,2)::int>23 or substring(t,15,2)::int>59 or (substring(t,17,1)=':' and substring(t,18,2)::int>59) then raise exception 'Invalid date and timezone';end if;
 if right(t,1)<>'Z' and (substring(t,length(t)-4,2)::int>14 or right(t,2)::int>59) then raise exception 'Invalid timezone';end if;
 d:=t::timestamptz;return d;
end $$;
create function private.planning_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb;d jsonb;rev bigint;previous private.command_receipts%rowtype;recordid uuid;reason text;event jsonb;old jsonb;entry jsonb;rows jsonb;start_time timestamptz;end_time timestamptz;lift uuid;oid uuid;v jsonb;result jsonb;before_value jsonb;
begin
 m:=private.photo_device(w,dev);if m->>'role' not in ('admin','office') then raise exception 'Office permission required' using errcode='42501';end if;
 if not private.photo_files_ready(w) then raise exception 'Recover original files before new work';end if;
 perform 1 from private.workshops where id=w for update;
 if cid is null or jsonb_typeof(p) is distinct from 'object' then raise exception 'Command and payload required';end if;
 select * into previous from private.command_receipts where workshop_id=w and id=cid;
 if found then if previous.actor_id<>auth.uid() or previous.device_id<>dev or previous.action<>action or previous.payload<>p then raise exception 'Command ID reused';end if;return previous.result;end if;
 select data into d from private.planning_state where workshop_id=w;
 d:=coalesce(d,'{"revision":0,"resources":[],"bookings":[]}');before_value:=d;rev:=(d->>'revision')::bigint;
 if private.require_int(p->'revision',0,9007199254740991,'Revision')<>rev then raise exception 'Agenda revision conflict';end if;
 recordid:=(p->>'id')::uuid;if recordid is null then raise exception 'Record ID required';end if;
 reason:=private.require_text(p->>'reason','Reason',2000);
 event:=jsonb_build_object('id',cid,'actorId',auth.uid(),'at',now(),'kind',action,'reason',reason);
 if action='schedule_resource' then
  if m->>'role'<>'admin' then raise exception 'Administrator configures lifts' using errcode='42501';end if;
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','revision','name','active','reason'])) or jsonb_typeof(p->'active') is distinct from 'boolean' then raise exception 'Lift fields required';end if;
  if p->'active'='false'::jsonb and exists(select 1 from jsonb_array_elements(d->'bookings') b where b->>'liftId'=recordid::text and b->>'status'='planned' and (b->>'end')::timestamptz>now()) then raise exception 'Reassign or cancel lift reservations';end if;
  select x into old from jsonb_array_elements(d->'resources') x where x->>'id'=recordid::text;
  entry:=jsonb_build_object('id',recordid,'name',private.require_text(p->>'name','Lift name',120),'active',p->'active','events',coalesce(old->'events','[]')||jsonb_build_array(event));
  select coalesce(jsonb_agg(x),'[]') into rows from jsonb_array_elements(d->'resources') x where x->>'id'<>recordid::text;
  d:=jsonb_set(d,'{resources}',rows||jsonb_build_array(entry));
 elsif action='schedule_booking' then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','revision','title','start','end','kind','assignees','liftId','orderId','reason'])) then raise exception 'Unsupported booking fields';end if;
  start_time:=private.planning_date(p->'start');end_time:=private.planning_date(p->'end');
  if end_time-start_time<interval '1 minute' or end_time-start_time>interval '7 days' then raise exception 'Reservation interval must be between one minute and seven days';end if;
  if p->>'kind' is null or p->>'kind' not in ('appointment','unavailable') or jsonb_typeof(p->'assignees') is distinct from 'array' or jsonb_array_length(p->'assignees')>50 then raise exception 'Booking type and assignees required';end if;
  if (select count(*) from jsonb_array_elements(p->'assignees'))<>(select count(distinct x) from jsonb_array_elements(p->'assignees') x) then raise exception 'Duplicate assignees';end if;
  for v in select value from jsonb_array_elements(p->'assignees') loop
   if jsonb_typeof(v)<>'string' or not exists(select 1 from private.members where workshop_id=w and user_id=(v#>>'{}')::uuid and active and role='technician') then raise exception 'Active workshop technicians required';end if;
  end loop;
  lift:=(p->>'liftId')::uuid;oid:=(p->>'orderId')::uuid;
  if lift is not null and not exists(select 1 from jsonb_array_elements(d->'resources') r where r->>'id'=lift::text and r->'active'='true'::jsonb) then raise exception 'Available workshop lift required';end if;
  if lift is null and jsonb_array_length(p->'assignees')=0 then raise exception 'Reserve technician or lift';end if;
  if oid is not null and not exists(select 1 from private.orders where workshop_id=w and id=oid) then raise exception 'Order must belong to workshop';end if;
  if oid is not null and p->>'kind'='unavailable' then raise exception 'Unavailable interval cannot link a repair';end if;
  select x into old from jsonb_array_elements(d->'bookings') x where x->>'id'=recordid::text;
  if old is not null and old->>'status'<>'planned' then raise exception 'Keep finished reservation and create new one';end if;
  if exists(select 1 from jsonb_array_elements(d->'bookings') b where b->>'id'<>recordid::text and b->>'status'='planned' and (b->>'start')::timestamptz<end_time and (b->>'end')::timestamptz>start_time and ((lift is not null and b->>'liftId'=lift::text) or exists(select 1 from jsonb_array_elements_text(p->'assignees') a where b->'assignees' ? a))) then raise exception 'Overlapping technician or lift reservation';end if;
  entry:=jsonb_build_object('id',recordid,'title',private.require_text(p->>'title','Booking title',300),'start',start_time,'end',end_time,'kind',p->'kind','assignees',p->'assignees','liftId',lift,'orderId',oid,'status','planned');
  entry:=entry||jsonb_build_object('versions',coalesce(old->'versions','[]')||jsonb_build_array(entry||(event-'kind')||jsonb_build_object('commandKind',action)),'events',coalesce(old->'events','[]')||jsonb_build_array(event));
  select coalesce(jsonb_agg(x),'[]') into rows from jsonb_array_elements(d->'bookings') x where x->>'id'<>recordid::text;
  d:=jsonb_set(d,'{bookings}',rows||jsonb_build_array(entry));
 elsif action='schedule_status' then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','revision','status','reason'])) then raise exception 'Unsupported status fields';end if;
  select x into old from jsonb_array_elements(d->'bookings') x where x->>'id'=recordid::text;
  if old is null or old->>'status'<>'planned' or p->>'status' is null or p->>'status' not in ('done','cancelled') then raise exception 'Current planned reservation required';end if;
  entry:=old||jsonb_build_object('status',p->'status','events',old->'events'||jsonb_build_array(event||jsonb_build_object('status',p->'status')));
  select coalesce(jsonb_agg(x),'[]') into rows from jsonb_array_elements(d->'bookings') x where x->>'id'<>recordid::text;
  d:=jsonb_set(d,'{bookings}',rows||jsonb_build_array(entry));
 else raise exception 'Unsupported planning action';end if;
 d:=d||jsonb_build_object('revision',rev+1);
 insert into private.planning_state values(w,d) on conflict(workshop_id) do update set data=excluded.data;
 result:=jsonb_build_object('saved',true,'revision',rev+1);
 insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,result);
 insert into private.audit(workshop_id,actor_id,operation_id,kind,before_data,after_data) values(w,auth.uid(),cid,action,before_value,d);
 return result;
end $$;
create function public.planning_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.planning_command($1,$2,$3,$4,$5)$$;
alter function private.snapshot(uuid) rename to snapshot_before_planning;
create function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;r jsonb;d jsonb;rows jsonb;begin
 m:=private.membership(w);r:=private.snapshot_before_planning(w);
 select data into d from private.planning_state where workshop_id=w;d:=coalesce(d,'{"revision":0,"resources":[],"bookings":[]}');
 if m->>'role'='technician' then
  select coalesce(jsonb_agg(jsonb_build_object('id',b->'id','title',b->'title','start',b->'start','end',b->'end','kind',b->'kind','assignees',b->'assignees','liftId',b->'liftId','orderId',case when exists(select 1 from jsonb_array_elements(r->'orders') o where o->>'id'=b->>'orderId') then b->'orderId' else 'null'::jsonb end,'status',b->'status','versions','[]'::jsonb,'events','[]'::jsonb)),'[]') into rows from jsonb_array_elements(d->'bookings') b where b->'assignees' ? auth.uid()::text;
  d:=jsonb_set(d,'{bookings}',rows);
  select coalesce(jsonb_agg(x-'events'),'[]') into rows from jsonb_array_elements(d->'resources') x;d:=jsonb_set(d,'{resources}',rows);
 end if;
 return r||jsonb_build_object('planning',d);
end $$;
alter function private.backup_tables() rename to backup_tables_before_planning;
create function private.backup_tables() returns text[] language sql immutable set search_path='' as $$select private.backup_tables_before_planning()||array['planning_state']::text[]$$;
alter function private.export_workshop(uuid,uuid) rename to export_workshop_before_planning;
create function private.export_workshop(w uuid,dev uuid) returns jsonb language sql security definer set search_path='' as $$select private.export_workshop_before_planning(w,dev)||jsonb_build_object('databaseVersion',11)$$;
create function private.validate_planning(w uuid,d jsonb) returns void language plpgsql security definer set search_path='' as $$
declare b jsonb;r jsonb;v jsonb;s timestamptz;e timestamptz;begin
 if jsonb_typeof(d->'resources') is distinct from 'array' or jsonb_typeof(d->'bookings') is distinct from 'array' or jsonb_typeof(d->'revision') is distinct from 'number' or (d->>'revision')::bigint<0 then raise exception 'Malformed planning archive';end if;
 if (select count(*) from jsonb_array_elements(d->'resources'))<>(select count(distinct x->>'id') from jsonb_array_elements(d->'resources') x) or (select count(*) from jsonb_array_elements(d->'bookings'))<>(select count(distinct x->>'id') from jsonb_array_elements(d->'bookings') x) then raise exception 'Duplicate planning records';end if;
 for r in select value from jsonb_array_elements(d->'resources') loop
  if (r->>'id')::uuid is null or jsonb_typeof(r->'active') is distinct from 'boolean' or jsonb_typeof(r->'events') is distinct from 'array' then raise exception 'Malformed lift';end if;perform private.require_text(r->>'name','Lift',120);
 end loop;
 for b in select value from jsonb_array_elements(d->'bookings') loop
  if (b->>'id')::uuid is null or b->>'status' is null or b->>'status' not in ('planned','done','cancelled') or b->>'kind' is null or b->>'kind' not in ('appointment','unavailable') or jsonb_typeof(b->'assignees') is distinct from 'array' or jsonb_typeof(b->'events') is distinct from 'array' or jsonb_typeof(b->'versions') is distinct from 'array' or jsonb_array_length(b->'versions')=0 then raise exception 'Malformed booking';end if;
  perform private.require_text(b->>'title','Title',300);s:=private.planning_date(b->'start');e:=private.planning_date(b->'end');if e-s<interval '1 minute' or e-s>interval '7 days' then raise exception 'Invalid planning interval';end if;
  for v in select value from jsonb_array_elements(b->'assignees') loop
   if not exists(select 1 from private.members where workshop_id=w and user_id=(v#>>'{}')::uuid) then raise exception 'Cross-workshop planning member';end if;
  end loop;
  if b->>'orderId' is not null and not exists(select 1 from private.orders where workshop_id=w and id=(b->>'orderId')::uuid) then raise exception 'Cross-workshop planning order';end if;
  if b->>'liftId' is not null and not exists(select 1 from jsonb_array_elements(d->'resources') lift_row where lift_row->>'id'=b->>'liftId') then raise exception 'Missing planning lift';end if;
  if jsonb_array_length(b->'assignees')=0 and b->>'liftId' is null then raise exception 'Empty planning reservation';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(d->'bookings') first_booking cross join jsonb_array_elements(d->'bookings') second_booking where first_booking->>'id'<second_booking->>'id' and first_booking->>'status'='planned' and second_booking->>'status'='planned' and (first_booking->>'start')::timestamptz<(second_booking->>'end')::timestamptz and (first_booking->>'end')::timestamptz>(second_booking->>'start')::timestamptz and ((first_booking->>'liftId' is not null and first_booking->>'liftId'=second_booking->>'liftId') or exists(select 1 from jsonb_array_elements_text(first_booking->'assignees') u where second_booking->'assignees' ? u))) then raise exception 'Overlapping planning archive';end if;
end $$;
alter function private.restore_workshop(uuid,uuid,uuid,jsonb) rename to restore_workshop_before_planning;
create function private.restore_workshop(w uuid,dev uuid,rid uuid,a jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare normalized jsonb:=a;result jsonb;d jsonb;begin
 perform private.backup_admin(w,dev);
 if exists(select 1 from private.planning_state where workshop_id=w) and not exists(select 1 from private.restores where workshop_id=w and id=rid) then raise exception 'Restore requires an empty isolated workshop with no planning records';end if;
 if a->>'databaseVersion'='11' then
  if jsonb_typeof(a->'tables'->'planning_state') is distinct from 'array' then raise exception 'Planning table missing';end if;
  normalized:=a||jsonb_build_object('databaseVersion',10);
 elsif a->>'databaseVersion' in ('2','3','4','5','6','7','8','9','10') then normalized:=jsonb_set(a,'{tables,planning_state}',coalesce(a->'tables'->'planning_state','[]'));
 end if;
 result:=private.restore_workshop_before_planning(w,dev,rid,normalized);
 for d in select data from private.planning_state where workshop_id=w loop perform private.validate_planning(w,d);end loop;
 return result;
end $$;
revoke all on function private.planning_date(jsonb),private.planning_command(uuid,uuid,uuid,text,jsonb),public.planning_command(uuid,uuid,uuid,text,jsonb),private.snapshot_before_planning(uuid),private.snapshot(uuid),private.backup_tables_before_planning(),private.backup_tables(),private.export_workshop_before_planning(uuid,uuid),private.export_workshop(uuid,uuid),private.validate_planning(uuid,jsonb),private.restore_workshop_before_planning(uuid,uuid,uuid,jsonb),private.restore_workshop(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.planning_command(uuid,uuid,uuid,text,jsonb),public.planning_command(uuid,uuid,uuid,text,jsonb),private.snapshot(uuid),private.export_workshop(uuid,uuid),private.restore_workshop(uuid,uuid,uuid,jsonb) to authenticated;
commit;
