-- Stable vehicle identity and immutable recipient references. Customer-facing
-- access is never inferred from the current vehicle owner, registration or VIN.
begin;
create table private.vehicle_profiles (
 workshop_id uuid not null,vehicle_id uuid not null,revision bigint not null default 0,
 owner_id uuid not null,owner_data jsonb not null,max_km bigint not null default 0,
 primary key(workshop_id,vehicle_id),
 foreign key(workshop_id,vehicle_id) references private.vehicles(workshop_id,id)
);
create table private.vehicle_identifiers (
 workshop_id uuid not null,vehicle_id uuid not null,kind text not null check(kind in ('plate','vin')),
 country text not null,value text not null,
 primary key(workshop_id,kind,country,value),
 foreign key(workshop_id,vehicle_id) references private.vehicles(workshop_id,id)
);
create table private.order_recipient_refs (
 workshop_id uuid not null,order_id uuid not null,owner_id uuid not null,snapshot jsonb not null,
 primary key(workshop_id,order_id),
 foreign key(workshop_id,order_id) references private.orders(workshop_id,id)
);
create table private.vehicle_changes (
 workshop_id uuid not null,id uuid not null,vehicle_id uuid not null,actor_id uuid not null,
 changed_at timestamptz not null default now(),payload jsonb not null,before_data jsonb not null,after_data jsonb not null,
 primary key(workshop_id,id),foreign key(workshop_id,vehicle_id) references private.vehicles(workshop_id,id)
);
do $$ declare t text;begin
 foreach t in array array['vehicle_profiles','vehicle_identifiers','order_recipient_refs','vehicle_changes'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;
end $$;
create trigger vehicle_identifiers_immutable before update or delete on private.vehicle_identifiers for each row execute function private.immutable_document();
create trigger order_recipients_immutable before update or delete on private.order_recipient_refs for each row execute function private.immutable_document();
create trigger vehicle_changes_immutable before update or delete on private.vehicle_changes for each row execute function private.immutable_document();

create function private.seed_vehicle_history(w uuid) returns void language plpgsql security definer set search_path='' as $$
declare v private.vehicles%rowtype;o private.orders%rowtype;begin
 for v in select * from private.vehicles where w is null or workshop_id=w loop
  select x.* into o from private.orders x where x.workshop_id=v.workshop_id and x.vehicle_id=v.id
   order by coalesce((select max(received_at) from private.operations p where p.workshop_id=x.workshop_id and p.order_id=x.id and p.operation->>'kind'='receive'),'-infinity'::timestamptz) desc,x.id desc limit 1;
  insert into private.vehicle_profiles values(v.workshop_id,v.id,0,coalesce(nullif(o.data->>'ownerId','')::uuid,o.id,v.id),
   jsonb_build_object('name',coalesce(o.data->>'client','Cliente por confirmar'),'phone',coalesce(o.data->>'phone','')),
   coalesce((select max((data->>'km')::bigint) from private.orders where workshop_id=v.workshop_id and vehicle_id=v.id),0)) on conflict do nothing;
  insert into private.vehicle_identifiers values(v.workshop_id,v.id,'plate',v.country,v.plate) on conflict do nothing;
  if v.vin is not null then insert into private.vehicle_identifiers values(v.workshop_id,v.id,'vin','',v.vin) on conflict do nothing;end if;
 end loop;
 insert into private.order_recipient_refs
 select workshop_id,id,coalesce(nullif(data->>'ownerId','')::uuid,id),jsonb_build_object('name',data->>'client','phone',coalesce(data->>'phone',''))
 from private.orders where w is null or workshop_id=w on conflict do nothing;
end $$;
select private.seed_vehicle_history(null);

create function private.find_vehicle(w uuid,plate_value text,country_value text,vin_value text) returns uuid language plpgsql stable security definer set search_path='' as $$
declare ids uuid[];begin
 select array_agg(distinct id) into ids from (
  select vehicle_id id from private.vehicle_identifiers where workshop_id=w and
   ((kind='plate' and country=country_value and value=plate_value) or (kind='vin' and vin_value<>'' and value=vin_value))
  union select id from private.vehicles where workshop_id=w and ((country=country_value and plate=plate_value) or (vin_value<>'' and vin=vin_value))
 ) matches;
 if cardinality(ids)>1 then raise exception 'Registration and VIN identify different vehicles';end if;
 return ids[1];
end $$;

create function private.attach_vehicle(w uuid,vid uuid,p jsonb,oid uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare vp private.vehicle_profiles%rowtype;v private.vehicles%rowtype;name_value text;phone_value text;begin
 select * into v from private.vehicles where workshop_id=w and id=vid;
 select * into vp from private.vehicle_profiles where workshop_id=w and vehicle_id=vid for update;
 name_value:=private.require_text(p->>'client','Client',300);phone_value:=coalesce(p->>'phone','');
 if length(phone_value)>100 then raise exception 'Phone too long';end if;
 if vp.vehicle_id is null then
  if v.plate<>regexp_replace(upper(p->>'plate'),'[[:space:]-]','','g') or v.country<>p->>'country' then raise exception 'Confirm registration change in vehicle profile';end if;
  insert into private.vehicle_profiles values(w,vid,0,oid,jsonb_build_object('name',name_value,'phone',phone_value),(p->>'km')::bigint);
  insert into private.vehicle_identifiers values(w,vid,'plate',v.country,v.plate) on conflict do nothing;
  if v.vin is not null then insert into private.vehicle_identifiers values(w,vid,'vin','',v.vin) on conflict do nothing;end if;
  return oid;
 end if;
 if not exists(select 1 from private.vehicle_identifiers where workshop_id=w and vehicle_id=vid and kind='plate' and country=p->>'country' and value=regexp_replace(upper(p->>'plate'),'[[:space:]-]','','g')) then raise exception 'Confirm registration change in vehicle profile';end if;
 if coalesce(p->>'vin','')<>'' and not exists(select 1 from private.vehicle_identifiers where workshop_id=w and vehicle_id=vid and kind='vin' and value=p->>'vin') then raise exception 'Different VIN; review vehicle profile';end if;
 if lower(trim(vp.owner_data->>'name'))<>lower(trim(name_value)) or coalesce(vp.owner_data->>'phone','')<>phone_value then raise exception 'Confirm owner change in vehicle profile before reception';end if;
 update private.vehicle_profiles set revision=revision+1,max_km=greatest(max_km,(p->>'km')::bigint) where workshop_id=w and vehicle_id=vid;
 return vp.owner_id;
end $$;

create function private.technical_history(d jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb;k text;begin
 select coalesce(jsonb_object_agg(key,value),'{}') into result from jsonb_each(d) where key=any(array[
  'id','number','vehicleId','plate','country','vin','vehicle','engine','km','symptom','status','receivedAt','notes','dtcs','diagnoses','photos']);
 select result||jsonb_build_object('tasks',coalesce(jsonb_agg((select jsonb_object_agg(key,value) from jsonb_each(t) where key=any(array['id','title','done','cancelled','estimateMinutes','assignees']))),'[]')) into result from jsonb_array_elements(d->'tasks') t;
 select result||jsonb_build_object('times',coalesce(jsonb_agg((select jsonb_object_agg(key,value) from jsonb_each(t) where key=any(array['id','taskId','actorId','start','end','source']))),'[]')) into result from jsonb_array_elements(d->'times') t;
 select result||jsonb_build_object('parts',coalesce(jsonb_agg((select jsonb_object_agg(key,value) from jsonb_each(t) where key=any(array['id','taskId','itemId','description','reference','unit','quantityMilli','kind','actorId']))),'[]')) into result from jsonb_array_elements(d->'parts') t;
 return result;
end $$;

create function private.vehicle_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb;vp private.vehicle_profiles%rowtype;v private.vehicles%rowtype;prior private.command_receipts%rowtype;
 vid uuid;before_value jsonb;result jsonb;plate_value text;country_value text;vin_value text;owner_value uuid;
begin
 m:=private.membership(w);
 if not exists(select 1 from private.devices where workshop_id=w and id=dev and user_id=auth.uid() and retired_at is null and auth_session_id=private.auth_session()) then raise exception 'Active authenticated device required' using errcode='42501';end if;
 if m->>'role'='technician' then raise exception 'Office permission required' using errcode='42501';end if;
 if action is distinct from 'vehicle_change' or cid is null or jsonb_typeof(p) is distinct from 'object' then raise exception 'Invalid vehicle command';end if;
 if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['vehicleId','revision','change','reason','plate','country','vin','ownerId','name','phone'])) then raise exception 'Unexpected vehicle fields';end if;
 perform 1 from private.workshops where id=w for update;
 select * into prior from private.command_receipts where workshop_id=w and id=cid;
 if found then
  if prior.actor_id<>auth.uid() or prior.device_id<>dev or prior.action<>action or prior.payload<>p then raise exception 'Command ID reused';end if;
  return prior.result;
 end if;
 vid:=(p->>'vehicleId')::uuid;select * into vp from private.vehicle_profiles where workshop_id=w and vehicle_id=vid for update;
 select * into v from private.vehicles where workshop_id=w and id=vid;
 if vp.vehicle_id is null or p->>'revision' is null or (p->>'revision')::bigint<>vp.revision then raise exception 'Vehicle revision conflict';end if;
 perform private.require_text(p->>'reason','Reason');before_value:=jsonb_build_object('vehicle',to_jsonb(v),'profile',to_jsonb(vp));
 if p->>'change'='registration' then
  plate_value:=regexp_replace(upper(private.require_text(p->>'plate','Registration',30)),'[[:space:]-]','','g');
  country_value:=upper(private.require_text(p->>'country','Country',2));
  if country_value!~'^[A-Z]{2}$' then raise exception 'Two-letter country required';end if;
  vin_value:=upper(trim(coalesce(nullif(p->>'vin',''),v.vin,'')));
  if length(vin_value)>50 then raise exception 'VIN too long';end if;
  if exists(select 1 from private.vehicle_identifiers where workshop_id=w and vehicle_id<>vid and
   ((kind='plate' and country=country_value and value=plate_value) or (kind='vin' and vin_value<>'' and value=vin_value))) then raise exception 'Identifier belongs to another vehicle';end if;
  insert into private.vehicle_identifiers values(w,vid,'plate',country_value,plate_value) on conflict do nothing;
  if vin_value<>'' then insert into private.vehicle_identifiers values(w,vid,'vin','',vin_value) on conflict do nothing;end if;
  update private.vehicles set plate=plate_value,country=country_value,vin=nullif(vin_value,'') where workshop_id=w and id=vid;
 elsif p->>'change'='owner' then
  owner_value:=(p->>'ownerId')::uuid;
  if owner_value is null or exists(select 1 from private.vehicle_profiles where workshop_id=w and owner_id=owner_value)
   or exists(select 1 from private.order_recipient_refs where workshop_id=w and owner_id=owner_value)
   or exists(select 1 from private.vehicle_changes where workshop_id=w and after_data->'profile'->>'owner_id'=owner_value::text) then raise exception 'New recipient identity required';end if;
  if length(coalesce(p->>'phone',''))>100 then raise exception 'Phone too long';end if;
  update private.vehicle_profiles set owner_id=owner_value,owner_data=jsonb_build_object('name',private.require_text(p->>'name','Owner',300),'phone',trim(coalesce(p->>'phone',''))) where workshop_id=w and vehicle_id=vid;
 else raise exception 'Unknown vehicle change';end if;
 update private.vehicle_profiles set revision=revision+1 where workshop_id=w and vehicle_id=vid;
 select * into vp from private.vehicle_profiles where workshop_id=w and vehicle_id=vid;
 select * into v from private.vehicles where workshop_id=w and id=vid;
 result:=jsonb_build_object('saved',true,'vehicleId',vid,'revision',vp.revision);
 insert into private.vehicle_changes values(w,cid,vid,auth.uid(),now(),p,before_value,jsonb_build_object('vehicle',to_jsonb(v),'profile',to_jsonb(vp)));
 update private.close_requests set status='invalidated' where workshop_id=w and status='active' and order_id in(select id from private.orders where workshop_id=w and vehicle_id=vid);
 insert into private.audit(workshop_id,actor_id,operation_id,kind,before_data,after_data) values(w,auth.uid(),cid,action,before_value,jsonb_build_object('vehicleId',vid,'reason',p->>'reason','revision',vp.revision));
 insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,result);return result;
end $$;
create function public.vehicle_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.vehicle_command($1,$2,$3,$4,$5) $$;
revoke all on function private.seed_vehicle_history(uuid),private.find_vehicle(uuid,text,text,text),private.attach_vehicle(uuid,uuid,jsonb,uuid),private.technical_history(jsonb),private.vehicle_command(uuid,uuid,uuid,text,jsonb),public.vehicle_command(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.vehicle_command(uuid,uuid,uuid,text,jsonb),public.vehicle_command(uuid,uuid,uuid,text,jsonb) to authenticated;

create or replace function private.apply_record(w uuid, dev uuid, op jsonb, effective_actor uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  m jsonb; opid uuid; oid uuid; kind text; p jsonb; at_time timestamptz; d jsonb; before_doc jsonb;
  tid uuid; t jsonb; task_index int; entry jsonb; item private.catalog%rowtype;
  q bigint; sid uuid; n bigint; amount bigint; vid uuid; canonical_plate text;
  session private.time_sessions%rowtype; previous private.operations%rowtype;
  reason text; response_status text := 'accepted'; settings jsonb; current_revision bigint;
begin
  select jsonb_build_object('id',user_id,'name',display_name,'role',role,'seePrices',see_prices) into m from private.members where workshop_id=w and user_id=effective_actor and active;
  if m is null then raise exception 'Membership required'; end if;
  if (op->>'actorId') is distinct from effective_actor::text then raise exception 'Actor mismatch' using errcode='42501'; end if;
  opid := (op->>'id')::uuid; oid := (op->>'orderId')::uuid; kind := op->>'kind'; p := op->'payload'; at_time := (op->>'at')::timestamptz;
  if opid is null or oid is null or kind is null or jsonb_typeof(p) <> 'object' then raise exception 'Malformed operation'; end if;
  if at_time is null or at_time > now()+interval '2 minutes' then raise exception 'Invalid device time'; end if;
  -- Serializes mutations inside a workshop and user timers across workshops.
  perform pg_advisory_xact_lock(hashtextextended(effective_actor::text,0));
  select s.settings into settings from private.workshops s where s.id=w for update;
  select * into previous from private.operations where workshop_id=w and id=opid;
  if found then
    if previous.actor_id <> effective_actor or previous.operation <> op then raise exception 'Idempotency key reused with different data'; end if;
    return jsonb_build_object('status',previous.status,'reason',previous.reason);
  end if;
  insert into private.devices(workshop_id,id,user_id) values(w,dev,effective_actor)
    on conflict(workshop_id,id) do update set last_seen=now() where private.devices.user_id=effective_actor;
  if not exists(select 1 from private.devices where workshop_id=w and id=dev and user_id=effective_actor) then raise exception 'Device belongs to another user' using errcode='42501'; end if;
  if kind in ('receive','authorize','billable','review_parts','issue','deliver') and m->>'role'='technician' then raise exception 'Office permission required' using errcode='42501'; end if;
  select data,revision into d,current_revision from private.orders where workshop_id=w and id=oid for update;
  before_doc := d;
  if kind <> 'receive' then
    if d is null then raise exception 'Order not found'; end if;
    if m->>'role'='technician' and not exists(select 1 from jsonb_array_elements(d->'tasks') z where z->'assignees' ? effective_actor::text) then raise exception 'Order not assigned' using errcode='42501'; end if;
    if d->'document' is not null and d->'document' <> 'null'::jsonb and kind <> 'deliver' then
      insert into private.operations values(w,opid,oid,effective_actor,dev,now(),op,'late','Registro recibido después de emitir la nota');
      return '{"status":"late"}';
    end if;
  end if;
  -- Validation failures roll back only the mutation, retaining the incoming evidence.
  begin
    if kind in ('start','manual_time','part','finish_task','authorize','billable') then
      tid := (p->>'taskId')::uuid;
      select x.value,(x.ordinality-1)::int into t,task_index from jsonb_array_elements(d->'tasks') with ordinality x where x.value->>'id'=tid::text;
      if t is null then raise exception 'Task not found'; end if;
      if m->>'role'='technician' and not(t->'assignees' ? effective_actor::text) then raise exception 'Task not assigned'; end if;
      if kind in ('start','manual_time','part','finish_task') and coalesce((t->>'authorized')::boolean,false)=false then raise exception 'Task authorization required'; end if;
    end if;
    if kind in ('authorize','billable','quality','review_parts','deliver','task_add','task_edit','task_cancel','task_reopen','task_block','task_unblock','order_plan','unblock','template_apply') and (op->>'baseRevision')::bigint is distinct from current_revision then raise exception 'Revision conflict; review latest order'; end if;
    case kind
      when 'receive' then
        if d is not null then raise exception 'Order already exists'; end if;
        p:=p||jsonb_build_object('country',upper(trim(p->>'country')),'vin',upper(trim(coalesce(p->>'vin',''))));
        canonical_plate := regexp_replace(upper(p->>'plate'),'[[:space:]-]','','g');
        if coalesce(p->>'country','')!~'^[A-Z]{2}$' or length(p->>'vin')>50 then raise exception 'Review country and VIN';end if;
        if coalesce(canonical_plate,'')='' or coalesce(trim(p->>'symptom'),'')='' or coalesce(trim(p->>'client'),'')='' then raise exception 'Reception fields required'; end if;
        vid:=private.find_vehicle(w,canonical_plate,p->>'country',coalesce(p->>'vin',''));
        if vid is null then
          vid := gen_random_uuid();
          insert into private.vehicles(workshop_id,id,plate,country,vin,technical) values(w,vid,canonical_plate,p->>'country',nullif(upper(p->>'vin'),''),jsonb_build_object('vehicle',p->>'vehicle','engine',p->>'engine'));
        end if;
        if jsonb_typeof(p->'tasks') is distinct from 'array' or jsonb_array_length(p->'tasks') not between 1 and 40 then raise exception 'Reception requires 1 to 40 tasks';end if;
        perform private.require_int(p->'km',0,2147483647,'Mileage');
        select coalesce(jsonb_object_agg(k,v),'{}') into d from jsonb_each(p) e(k,v) where k=any(array['plate','country','vin','vehicle','engine','client','phone','km','symptom','location','keys','due','priority']);
        d := d || jsonb_build_object('id',oid,'vehicleId',vid,'plate',canonical_plate,'number','OT-'||upper(left(oid::text,8)),'status','pending','times','[]'::jsonb,'parts','[]'::jsonb,'notes','[]'::jsonb);
        -- Office can define tasks, never forge authorization or monetary snapshots.
        select jsonb_agg(private.new_task(w,z,settings)) into entry from jsonb_array_elements(p->'tasks') z;
        if (select count(distinct z->>'id') from jsonb_array_elements(entry) z)<>jsonb_array_length(entry) then raise exception 'Duplicate reception tasks';end if;
        if exists(select 1 from jsonb_array_elements(entry) z cross join lateral jsonb_array_elements_text(z->'assignees') a where not exists(select 1 from private.members mm where mm.workshop_id=w and mm.user_id::text=a and mm.active)) then raise exception 'Assignee outside workshop'; end if;
        d := jsonb_set(d,'{tasks}',entry);
        d:=d||jsonb_build_object('ownerId',private.attach_vehicle(w,vid,p,oid),'receivedAt',at_time);
        d:=d||coalesce((select jsonb_build_object('plate',plate,'country',country,'vin',coalesce(vin,'')) from private.vehicles where workshop_id=w and id=vid),'{}');
        insert into private.orders(workshop_id,id,vehicle_id,data) values(w,oid,vid,d);
        insert into private.order_recipient_refs values(w,oid,(d->>'ownerId')::uuid,jsonb_build_object('name',d->>'client','phone',coalesce(d->>'phone','')));
        current_revision := 0;
      when 'start' then
        if (t->'block' is not null and t->'block'<>'null') or (d->'block' is not null and d->'block'<>'null') then raise exception 'Resolve block before starting';end if;
        if (t->>'done')::boolean then raise exception 'Task already completed'; end if;
        if exists(select 1 from private.time_sessions where actor_id=effective_actor and (ended_at is null or ended_at>at_time)) then raise exception 'Incompatible timer session'; end if;
        insert into private.time_sessions values(w,opid,oid,tid,effective_actor,dev,at_time,null);
        entry := jsonb_build_object('id',opid,'taskId',tid,'actorId',effective_actor,'start',at_time,'end',null,'source','timer');
        d := jsonb_set(d,'{times}',d->'times'||jsonb_build_array(entry));
        d := d || '{"status":"repair","quality":null}';
      when 'stop' then
        sid := (p->>'sessionId')::uuid;
        select * into session from private.time_sessions where workshop_id=w and id=sid and order_id=oid for update;
        if session.actor_id is distinct from effective_actor or session.ended_at is not null or session.started_at>at_time then raise exception 'Invalid timer stop'; end if;
        update private.time_sessions set ended_at=at_time where workshop_id=w and id=sid;
        select jsonb_agg(case when z->>'id'=sid::text then z||jsonb_build_object('end',at_time) else z end) into entry from jsonb_array_elements(d->'times') z;
        d := jsonb_set(d,'{times}',entry);
      when 'manual_time' then
        if coalesce(trim(p->>'reason'),'')='' or (p->>'end')::timestamptz>(at_time+interval '2 minutes') or (p->>'end')::timestamptz<=(p->>'start')::timestamptz then raise exception 'Invalid manual time or missing reason'; end if;
        if exists(select 1 from private.time_sessions where actor_id=effective_actor and started_at<(p->>'end')::timestamptz and coalesce(ended_at,'infinity'::timestamptz)>(p->>'start')::timestamptz) then raise exception 'Time interval overlaps an existing session'; end if;
        insert into private.time_sessions values(w,opid,oid,tid,effective_actor,dev,(p->>'start')::timestamptz,(p->>'end')::timestamptz);
        entry := jsonb_build_object('id',opid,'taskId',tid,'actorId',effective_actor,'start',p->>'start','end',p->>'end','reason',p->>'reason','source','manual');
        d := jsonb_set(d,'{times}',d->'times'||jsonb_build_array(entry));
        d := jsonb_set(d,'{quality}','null');
      when 'part' then
        q := (p->>'quantityMilli')::bigint;
        if q is null or q<=0 or p->>'kind' not in ('consume','reserve','customer') then raise exception 'Invalid part movement'; end if;
        select * into item from private.catalog where workshop_id=w and id=(p->>'itemId')::uuid;
        if not found then raise exception 'Catalog reference not found'; end if;
        if exists(select 1 from private.catalog_details where workshop_id=w and item_id=item.id and not active) then raise exception 'Catalog reference deactivated';end if;
        entry := jsonb_build_object('id',opid,'taskId',tid,'itemId',item.id,'description',item.description,'reference',item.reference,'unit',item.unit,'quantityMilli',q,'priceCents',item.price_cents,'costCents',item.cost_cents,'taxBps',coalesce((select tax_bps from private.catalog_details where workshop_id=w and item_id=item.id),(settings->>'taxBps')::int),'costKnown',coalesce((select cost_known from private.catalog_details where workshop_id=w and item_id=item.id),false),'kind',p->>'kind','charge',p->>'kind'='consume','reviewed',false,'actorId',effective_actor);
        d := jsonb_set(d,'{parts}',d->'parts'||jsonb_build_array(entry));
        d := jsonb_set(d,'{quality}','null');
      when 'return' then
        select z into entry from jsonb_array_elements(d->'parts') z where z->>'id'=p->>'sourceId' and z->>'kind'='consume';
        if entry is null then raise exception 'Consumption not found'; end if;
        if m->>'role'='technician' and not exists(select 1 from jsonb_array_elements(d->'tasks') z where z->>'id'=entry->>'taskId' and z->'assignees' ? effective_actor::text) then raise exception 'Task not assigned'; end if;
        select coalesce(sum((z->>'quantityMilli')::bigint),0) into n from jsonb_array_elements(d->'parts') z where z->>'sourceId'=entry->>'id';
        q := (p->>'quantityMilli')::bigint;
        if q is null or q<=0 or q+n>(entry->>'quantityMilli')::bigint then raise exception 'Return exceeds consumption'; end if;
        entry := entry||jsonb_build_object('id',opid,'kind','return','sourceId',entry->>'id','quantityMilli',q,'charge',false,'reviewed',false,'actorId',effective_actor);
        d := jsonb_set(d,'{parts}',d->'parts'||jsonb_build_array(entry));
      when 'note' then
        if coalesce(trim(p->>'text'),'')='' then raise exception 'Empty observation'; end if;
        entry := jsonb_build_object('id',opid,'text',p->>'text','author',m->>'name','at',at_time);
        d := jsonb_set(d,'{notes}',d->'notes'||jsonb_build_array(entry));
      when 'finish_task' then
        if (t->'block' is not null and t->'block'<>'null') or coalesce((t->>'cancelled')::boolean,false) then raise exception 'Blocked or cancelled task';end if;
        if exists(select 1 from private.time_sessions where workshop_id=w and order_id=oid and task_id=tid and ended_at is null) then raise exception 'Task has active timers'; end if;
        t := t||'{"done":true}';
        d := jsonb_set(d,array['tasks',task_index::text],t);
        if not exists(select 1 from jsonb_array_elements(d->'tasks') z where (z->>'authorized')::boolean and not(z->>'done')::boolean) then d := d||'{"status":"finished"}'; end if;
        d := jsonb_set(d,'{quality}','null');
      when 'authorize' then
        if coalesce((t->>'cancelled')::boolean,false) then raise exception 'Task cancelled';end if;
        amount := (p->>'approvedCents')::bigint;
        if amount is null or amount<0 or coalesce(trim(p->>'customer'),'')='' or coalesce(trim(p->>'evidence'),'')='' or coalesce((p->>'version')::int,0)<=0 then raise exception 'Authorization evidence required'; end if;
        t := t||jsonb_build_object('authorized',true,'approvedCents',amount,'authorization',p||jsonb_build_object('actorId',effective_actor,'at',at_time));
        d := jsonb_set(d,array['tasks',task_index::text],t);
      when 'billable' then
        n := (p->>'minutes')::bigint;
        if n is null or n<0 or n>14400 or coalesce(trim(p->>'reason'),'')='' then raise exception 'Invalid billable minutes or missing reason'; end if;
        if n>0 and not(t->>'authorized')::boolean then raise exception 'Task authorization required'; end if;
        d := jsonb_set(d,array['tasks',task_index::text,'billableMinutes'],to_jsonb(n));
      when 'review_parts' then
        select coalesce(jsonb_agg(z||'{"reviewed":true}'),'[]') into entry from jsonb_array_elements(d->'parts') z;
        d := jsonb_set(d,'{parts}',entry);
      when 'quality' then
        if coalesce(trim(p->>'result'),'')='' or exists(select 1 from jsonb_array_elements(d->'tasks') z where (z->>'authorized')::boolean and not(z->>'done')::boolean) or exists(select 1 from private.time_sessions where workshop_id=w and order_id=oid and ended_at is null) then raise exception 'Final check requires completed work and stopped timers'; end if;
        d := d||jsonb_build_object('status','verified','quality',p||jsonb_build_object('actorId',effective_actor,'at',at_time));
      when 'block' then
        if coalesce(trim(p->>'reason'),'')='' then raise exception 'Block reason required'; end if;
        d := d||jsonb_build_object('status','parts','block',p->>'reason','nextAction',p->>'nextAction');
      when 'task_add','task_edit','task_cancel','task_reopen','task_block','task_unblock','order_plan','unblock','template_apply' then
        d:=private.task_change(w,d,kind,p,effective_actor,at_time,settings);
      when 'issue' then
        -- Deliberately fail closed until device reconciliation barriers are implemented.
        raise exception 'Cloud document issuing disabled until all-device reconciliation is validated';
      when 'deliver' then
        if d->'document' is null or d->'document'='null'::jsonb or coalesce(trim(p->>'reason'),'')='' then raise exception 'Issued note and delivery reason required'; end if;
        d := d||jsonb_build_object('status','delivered','delivery',p||jsonb_build_object('actorId',effective_actor,'at',at_time));
      else raise exception 'Unsupported operation';
    end case;
    update private.orders set data=d,revision=current_revision+1 where workshop_id=w and id=oid;
    insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,before_data,after_data) values(w,effective_actor,opid,oid,kind,before_doc,d);
  exception when others then
    get stacked diagnostics reason = message_text;
    response_status := 'conflict';
  end;
  insert into private.operations values(w,opid,oid,effective_actor,dev,now(),op,response_status,reason);
  return jsonb_build_object('status',response_status,'reason',reason);
end $$;



create or replace function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb; orders_json jsonb; catalog_json jsonb; audit_json jsonb; incidents_json jsonb; show_prices boolean; show_costs boolean; settings_json jsonb;result jsonb;profiles jsonb;history jsonb;
begin
  m := private.membership(w);
  show_costs:=(m->>'seeCosts')::boolean;
  show_prices := (m->>'role') in ('office','admin') or (m->>'seePrices')::boolean;
  select coalesce(jsonb_agg(o.data || jsonb_build_object('revision',o.revision)),'[]') into orders_json
    from private.orders o where o.workshop_id=w and ((m->>'role') in ('office','admin') or exists (
      select 1 from jsonb_array_elements(o.data->'tasks') t where t->'assignees' ? auth.uid()::text));
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'reference',c.reference,'description',c.description,'unit',c.unit,
    'priceCents',c.price_cents,'costCents',c.cost_cents,'stockMilli',c.stock_milli-coalesce((select sum(case when p->>'kind'='consume' then (p->>'quantityMilli')::bigint when p->>'kind'='return' then -(p->>'quantityMilli')::bigint else 0 end) from private.orders hidden cross join lateral jsonb_array_elements(hidden.data->'parts') p where hidden.workshop_id=w and p->>'itemId'=c.id::text and (m->>'role')='technician' and not exists(select 1 from jsonb_array_elements(hidden.data->'tasks') ht where ht->'assignees' ? auth.uid()::text)),0),'minMilli',c.min_milli,'taxBps',cd.tax_bps,'costKnown',coalesce(cd.cost_known,false),'active',coalesce(cd.active,true),'supplier',coalesce(cd.supplier,''))),'[]') into catalog_json
    from private.catalog c left join private.catalog_details cd on cd.workshop_id=c.workshop_id and cd.item_id=c.id where c.workshop_id=w;
  select coalesce(jsonb_agg(jsonb_build_object('id',a.operation_id,'orderId',a.order_id,'actorId',a.actor_id,
    'actor',coalesce(u.display_name,'Usuario'),'kind',a.kind,'at',a.occurred_at)),'[]') into audit_json
    from private.audit a left join private.members u on u.workshop_id=a.workshop_id and u.user_id=a.actor_id
    where a.workshop_id=w and ((m->>'role') in ('office','admin') or a.actor_id=auth.uid());
  select coalesce(jsonb_agg(jsonb_build_object('operation',o.operation,'reason',o.reason,'status',o.status)),'[]') into incidents_json
    from private.operations o where o.workshop_id=w and o.status <> 'accepted' and ((m->>'role') in ('office','admin') or o.actor_id=auth.uid());
  if not show_prices then
    orders_json := private.redact_prices(orders_json);
    catalog_json := private.redact_prices(catalog_json);
    incidents_json := private.redact_prices(incidents_json);
  end if;
  if not show_costs then catalog_json:=private.redact_costs(catalog_json);orders_json:=private.redact_costs(orders_json);incidents_json:=private.redact_costs(incidents_json);end if;
  select settings into settings_json from private.workshops where id=w;
  if not show_prices then settings_json:=private.redact_prices(settings_json);end if;
  if not show_costs then settings_json:=private.redact_costs(settings_json);end if;
  result:=jsonb_build_object('workshopId',w,'orders',orders_json,'catalog',catalog_json,'members',(select coalesce(jsonb_agg(jsonb_build_object('id',user_id,'name',display_name,'role',role,'seePrices',see_prices,'seeCosts',coalesce((select see_costs from private.member_permissions mp where mp.workshop_id=w and mp.user_id=private.members.user_id),false),'active',active)),'[]') from private.members where workshop_id=w and (active or m->>'role'='admin')),'audit',audit_json,'applied','[]'::jsonb,'incidents',incidents_json,'settings',settings_json,'managementRevision',coalesce((select revision from private.management_state where workshop_id=w),0),
 'templates',case when m->>'role'='technician' then '[]'::jsonb else (select coalesce(jsonb_agg(data),'[]') from private.templates where workshop_id=w) end);
 select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'country',v.country,'vin',coalesce(v.vin,''),
 'vehicle',v.technical->>'vehicle','engine',v.technical->>'engine','km',vp.max_km,'revision',vp.revision,
 'ownerId',case when m->>'role'<>'technician' then vp.owner_id end,'owner',case when m->>'role'<>'technician' then vp.owner_data end,
 'identifiers',(select coalesce(jsonb_agg(jsonb_build_object('kind',i.kind,'country',i.country,'value',i.value)),'[]') from private.vehicle_identifiers i where i.workshop_id=w and i.vehicle_id=v.id))),'[]') into profiles
 from private.vehicles v join private.vehicle_profiles vp on vp.workshop_id=v.workshop_id and vp.vehicle_id=v.id
 where v.workshop_id=w and (m->>'role'<>'technician' or exists(select 1 from private.orders o cross join lateral jsonb_array_elements(o.data->'tasks') t where o.workshop_id=w and o.vehicle_id=v.id and t->'assignees' ? auth.uid()::text));
 select coalesce(jsonb_agg(private.technical_history(o.data)||case when m->>'role'='technician' then '{}'::jsonb else jsonb_build_object('ownerId',rr.owner_id,'recipient',rr.snapshot,'document',o.data->'document') end order by coalesce(o.data->>'receivedAt',''),o.id),'[]') into history
 from private.orders o left join private.order_recipient_refs rr on rr.workshop_id=o.workshop_id and rr.order_id=o.id
 where o.workshop_id=w and exists(select 1 from jsonb_array_elements(profiles) p where p->>'id'=o.vehicle_id::text);
 if not show_costs then history:=private.redact_costs(history);end if;
 return result||jsonb_build_object('vehicleProfiles',profiles,'vehicleHistory',history);
end $$;



create or replace function private.backup_tables() returns text[] language sql immutable set search_path='' as $$
 select array['members','member_permissions','vehicles','vehicle_profiles','vehicle_identifiers','vehicle_changes','catalog','catalog_details','templates','management_state','devices','device_sessions','orders','order_recipient_refs','operations','time_sessions',
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
 return jsonb_build_object('serverFormat',1,'databaseVersion',5,'workshopId',w,
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
 if a->>'serverFormat' is distinct from '1' or coalesce(a->>'databaseVersion','') not in ('2','3','4','5') or a->>'workshopId' is distinct from w::text
  or a->'workshop'->>'id' is distinct from w::text or a->>'authExcluded' is distinct from 'true' then raise exception 'Incompatible workshop archive'; end if;
 tables:=a->'tables';
 if a->>'databaseVersion' in ('2','3','4') then tables:=jsonb_build_object('vehicle_profiles','[]'::jsonb,'vehicle_identifiers','[]'::jsonb,'vehicle_changes','[]'::jsonb,'order_recipient_refs','[]'::jsonb)||tables;end if;
 if a->>'databaseVersion' in ('2','3') then tables:=jsonb_build_object('account_requests','[]'::jsonb)||tables;end if;
 if a->>'databaseVersion'='2' then tables:=jsonb_build_object('member_permissions','[]'::jsonb,'catalog_details','[]'::jsonb,'templates','[]'::jsonb,'management_state','[]'::jsonb)||tables;end if;
 if jsonb_typeof(tables) is distinct from 'object' then raise exception 'Missing archive tables'; end if;
 if exists(select 1 from jsonb_object_keys(tables) k where not k=any(private.backup_tables())) then raise exception 'Unknown archive table'; end if;
 if exists(select 1 from private.orders where workshop_id=w) or exists(select 1 from private.operations where workshop_id=w)
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
 -- No Auth session or successful closure confirmation is restored as active authority.
 result:=jsonb_build_object('restored',true,'counts',result,'requiresDeviceReview',true,'restoreId',rid);
 insert into private.restores(workshop_id,id,actor_id,device_id,archive,result) values(w,rid,auth.uid(),dev,a,result);
 insert into private.audit(workshop_id,actor_id,kind,after_data) values(w,auth.uid(),'restore_workshop',
  jsonb_build_object('restoreId',rid,'counts',result->'counts','deviceId',dev,'originalClosureConfirmationsInvalidated',true));
 return result;
end $$;



commit;
