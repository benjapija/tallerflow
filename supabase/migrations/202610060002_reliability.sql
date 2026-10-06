-- TallerFlow 0.2. Apply after core. All modifying APIs serialize on the workshop.
begin;
alter table private.devices add column auth_session_id uuid;
create unique index device_auth_session on private.devices(workshop_id,auth_session_id) where auth_session_id is not null;
alter table private.devices add column retired_at timestamptz;
alter table private.devices add column retirement_reason text;
create table private.device_sessions (
 workshop_id uuid not null, session_id uuid not null, device_id uuid not null,
 primary key(workshop_id,session_id), foreign key(workshop_id,device_id) references private.devices(workshop_id,id)
);
create table private.order_devices (
  workshop_id uuid not null, order_id uuid not null, device_id uuid not null,
  enrolled_at timestamptz not null default now(),
  primary key(workshop_id,order_id,device_id),
  foreign key(workshop_id,order_id) references private.orders(workshop_id,id),
  foreign key(workshop_id,device_id) references private.devices(workshop_id,id)
);
create table private.close_requests (
  workshop_id uuid not null, id uuid not null default gen_random_uuid(), order_id uuid not null,
  revision bigint not null, status text not null check(status in ('active','invalidated','issued')),
  requested_by uuid not null, requested_at timestamptz not null default now(),
  exception_reason text, retired_devices jsonb not null default '[]',
  primary key(workshop_id,id), foreign key(workshop_id,order_id) references private.orders(workshop_id,id)
);
create unique index one_live_close on private.close_requests(workshop_id,order_id) where status='active';
create table private.close_acknowledgements (
  workshop_id uuid not null, request_id uuid not null, device_id uuid not null,
  revision bigint not null, confirmed_by uuid not null, confirmed_at timestamptz not null default now(),
  primary key(workshop_id,request_id,device_id),
  foreign key(workshop_id,request_id) references private.close_requests(workshop_id,id),
  foreign key(workshop_id,device_id) references private.devices(workshop_id,id)
);
create table private.resolutions (
  workshop_id uuid not null, operation_id uuid not null, responsible_id uuid not null,
  reason text not null check(length(trim(reason))>0), outcome text not null check(outcome in ('archive','retry')),
  correction_id uuid, resolved_at timestamptz not null default now(),
  primary key(workshop_id,operation_id), foreign key(workshop_id,operation_id) references private.operations(workshop_id,id)
);
create table private.command_receipts (
  workshop_id uuid not null, id uuid not null, actor_id uuid not null, device_id uuid not null,
  action text not null, payload jsonb not null, result jsonb not null,
  primary key(workshop_id,id)
);
do $$ declare t text; begin
 foreach t in array array['device_sessions','order_devices','close_requests','close_acknowledgements','resolutions','command_receipts'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;
end $$;
create function private.preserve_document() returns trigger language plpgsql set search_path='' as $$
begin
 if old.data->'document' is not null and old.data->'document'<>'null'::jsonb then
  if TG_OP='DELETE' then raise exception 'Issued order cannot be deleted'; end if;
  if new.data->'document' is distinct from old.data->'document' then raise exception 'Issued document is immutable'; end if;
 end if;
 return new;
end $$;
create trigger orders_document_immutable before update or delete on private.orders for each row execute function private.preserve_document();
create trigger operations_immutable before update or delete on private.operations for each row execute function private.immutable_document();
create trigger resolutions_immutable before update or delete on private.resolutions for each row execute function private.immutable_document();

create function private.auth_session() returns uuid language plpgsql stable set search_path='' as $$
declare s uuid;
begin
 s:=nullif(coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'session_id','')::uuid;
 if s is null then raise exception 'Authenticated session_id required' using errcode='42501'; end if;
 if not exists(select 1 from auth.sessions where id=s and user_id=auth.uid()) then raise exception 'Auth session no longer exists' using errcode='42501'; end if;
 return s;
end $$;
create or replace function private.membership(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m private.members%rowtype;
begin
  perform private.auth_session();
  select * into m from private.members where workshop_id=w and user_id=auth.uid() and active;
  if not found then raise exception 'Membership required' using errcode='42501'; end if;
  return jsonb_build_object('id',m.user_id,'name',m.display_name,'role',m.role,'seePrices',m.see_prices);
end $$;

create function private.invalidate_close(w uuid,oid uuid) returns void language sql security definer set search_path='' as $$
 update private.close_requests set status='invalidated' where workshop_id=w and order_id=oid and status='active'
$$;
create function private.stock_valid(w uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from private.catalog c where c.workshop_id=w and c.stock_milli < coalesce((
  select sum(case when p->>'kind'='consume' then (p->>'quantityMilli')::bigint when p->>'kind'='return' then -(p->>'quantityMilli')::bigint else 0 end)
  from private.orders o cross join lateral jsonb_array_elements(o.data->'parts') p where o.workshop_id=w and p->>'itemId'=c.id::text),0))
$$;

-- Internal record helper: explicit actor is selected only by authenticated wrappers.
-- Never grant this helper to application roles.
create function private.apply_record(w uuid, dev uuid, op jsonb, effective_actor uuid) returns jsonb language plpgsql security definer set search_path='' as $$
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
    if kind in ('authorize','billable','quality','review_parts','deliver') and (op->>'baseRevision')::bigint is distinct from current_revision then raise exception 'Revision conflict; review latest order'; end if;
    case kind
      when 'receive' then
        if d is not null then raise exception 'Order already exists'; end if;
        canonical_plate := regexp_replace(upper(p->>'plate'),'[[:space:]-]','','g');
        if coalesce(canonical_plate,'')='' or coalesce(trim(p->>'symptom'),'')='' or coalesce(trim(p->>'client'),'')='' then raise exception 'Reception fields required'; end if;
        select id into vid from private.vehicles where workshop_id=w and ((coalesce(p->>'vin','')<>'' and vin=upper(p->>'vin')) or (country=p->>'country' and plate=canonical_plate));
        if vid is null then
          vid := gen_random_uuid();
          insert into private.vehicles(workshop_id,id,plate,country,vin,technical) values(w,vid,canonical_plate,p->>'country',nullif(upper(p->>'vin'),''),jsonb_build_object('vehicle',p->>'vehicle','engine',p->>'engine'));
        end if;
        if jsonb_array_length(p->'tasks')=0 then raise exception 'At least one task required'; end if;
        d := p - 'document' - 'quality' - 'delivery';
        d := d || jsonb_build_object('id',oid,'vehicleId',vid,'plate',canonical_plate,'number','OT-'||upper(left(oid::text,8)),'status','pending','times','[]'::jsonb,'parts','[]'::jsonb,'notes','[]'::jsonb);
        -- Office can define tasks, never forge authorization or monetary snapshots.
        select jsonb_agg(z || jsonb_build_object('authorized',false,'done',false,'billableMinutes',0,'approvedCents',0,'rateCents',(settings->>'hourlyRateCents')::bigint,'taxBps',(settings->>'taxBps')::int,'authorization',null)) into entry from jsonb_array_elements(p->'tasks') z;
        if exists(select 1 from jsonb_array_elements(entry) z cross join lateral jsonb_array_elements_text(z->'assignees') a where not exists(select 1 from private.members mm where mm.workshop_id=w and mm.user_id::text=a and mm.active)) then raise exception 'Assignee outside workshop'; end if;
        d := jsonb_set(d,'{tasks}',entry);
        insert into private.orders(workshop_id,id,vehicle_id,data) values(w,oid,vid,d);
        current_revision := 0;
      when 'start' then
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
        entry := jsonb_build_object('id',opid,'taskId',tid,'itemId',item.id,'description',item.description,'reference',item.reference,'unit',item.unit,'quantityMilli',q,'priceCents',item.price_cents,'costCents',item.cost_cents,'taxBps',(settings->>'taxBps')::int,'kind',p->>'kind','charge',p->>'kind'='consume','reviewed',false,'actorId',effective_actor);
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
        if exists(select 1 from private.time_sessions where workshop_id=w and order_id=oid and task_id=tid and ended_at is null) then raise exception 'Task has active timers'; end if;
        t := t||'{"done":true}';
        d := jsonb_set(d,array['tasks',task_index::text],t);
        if not exists(select 1 from jsonb_array_elements(d->'tasks') z where (z->>'authorized')::boolean and not(z->>'done')::boolean) then d := d||'{"status":"finished"}'; end if;
        d := jsonb_set(d,'{quality}','null');
      when 'authorize' then
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


create or replace function private.apply(w uuid,dev uuid,op jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb; device private.devices%rowtype; previous private.operations%rowtype;
 r jsonb; oid uuid := (op->>'orderId')::uuid; opid uuid := (op->>'id')::uuid; reason text;
begin
 m:=private.membership(w);
 if op->>'actorId' is distinct from auth.uid()::text then raise exception 'Actor mismatch' using errcode='42501'; end if;
 perform 1 from private.workshops where id=w for update;
 select * into device from private.devices where workshop_id=w and id=dev;
 if not found or device.user_id<>auth.uid() then raise exception 'Device not registered to account' using errcode='42501'; end if;
 select * into previous from private.operations where workshop_id=w and id=opid;
 if found then
  if previous.operation<>op or previous.device_id<>dev or previous.actor_id<>auth.uid() then raise exception 'Idempotency key reused with different data'; end if;
  return jsonb_build_object('status',previous.status,'reason',previous.reason);
 end if;
 if device.retired_at is not null then
  if op->>'kind'<>'receive' and not exists(select 1 from private.order_devices where workshop_id=w and order_id=oid and device_id=dev) then raise exception 'Order not enrolled on retired device' using errcode='42501'; end if;
  insert into private.operations values(w,opid,oid,auth.uid(),dev,now(),op,'late','Dispositivo retirado: registro recuperado para revisión');
  perform private.invalidate_close(w,oid);
  return jsonb_build_object('status','late','reason','Dispositivo retirado: registro conservado');
 end if;
 if not exists(select 1 from private.order_devices where workshop_id=w and order_id=oid and device_id=dev) and op->>'kind'<>'receive' then raise exception 'Order not enrolled on device' using errcode='42501'; end if;
 if device.auth_session_id is distinct from private.auth_session() then raise exception 'Device session mismatch' using errcode='42501'; end if;
 if op->>'kind' in ('receive','authorize','billable','review_parts','issue','deliver') and m->>'role'='technician' then raise exception 'Office permission required' using errcode='42501'; end if;
 if op->>'kind'='issue' then raise exception 'Use atomic closure API; legacy issuing disabled'; end if;
 begin
  r:=private.apply_record(w,dev,op,auth.uid());
  if r->>'status'='accepted' and not private.stock_valid(w) then raise exception 'Conflicto de stock: consumo conservado para revisión'; end if;
 exception when others then
  get stacked diagnostics reason=message_text;
  insert into private.operations values(w,opid,oid,auth.uid(),dev,now(),op,'conflict',reason);
  r:=jsonb_build_object('status','conflict','reason',reason);
 end;
 if op->>'kind'='receive' and r->>'status'='accepted' then
  insert into private.order_devices(workshop_id,order_id,device_id) values(w,oid,dev) on conflict do nothing;
 end if;
 perform private.invalidate_close(w,oid);
 return r;
end $$;

create function private.redact_costs(value jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb; k text; v jsonb;
begin
 if jsonb_typeof(value)='array' then select coalesce(jsonb_agg(private.redact_costs(x)),'[]') into result from jsonb_array_elements(value) x; return result;
 elsif jsonb_typeof(value)='object' then
  result:='{}';for k,v in select * from jsonb_each(value) loop
   if k not in ('costCents','internalHourlyCostCents') then result:=result||jsonb_build_object(k,private.redact_costs(v));end if;
  end loop;return result;
 end if;return value;
end $$;

create or replace function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb; orders_json jsonb; catalog_json jsonb; audit_json jsonb; incidents_json jsonb; show_prices boolean;
begin
  m := private.membership(w);
  show_prices := (m->>'role') in ('office','admin') or (m->>'seePrices')::boolean;
  select coalesce(jsonb_agg(o.data || jsonb_build_object('revision',o.revision)),'[]') into orders_json
    from private.orders o where o.workshop_id=w and ((m->>'role') in ('office','admin') or exists (
      select 1 from jsonb_array_elements(o.data->'tasks') t where t->'assignees' ? auth.uid()::text));
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'reference',c.reference,'description',c.description,'unit',c.unit,
    'priceCents',c.price_cents,'costCents',c.cost_cents,'stockMilli',c.stock_milli-coalesce((select sum(case when p->>'kind'='consume' then (p->>'quantityMilli')::bigint when p->>'kind'='return' then -(p->>'quantityMilli')::bigint else 0 end) from private.orders hidden cross join lateral jsonb_array_elements(hidden.data->'parts') p where hidden.workshop_id=w and p->>'itemId'=c.id::text and (m->>'role')='technician' and not exists(select 1 from jsonb_array_elements(hidden.data->'tasks') ht where ht->'assignees' ? auth.uid()::text)),0),'minMilli',c.min_milli)),'[]') into catalog_json
    from private.catalog c where c.workshop_id=w;
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
  elsif m->>'role' <> 'admin' then
    select coalesce(jsonb_agg(x - 'costCents'),'[]') into catalog_json from jsonb_array_elements(catalog_json) x;
    -- Cost visibility is limited to administrator in this initial server policy.
    select coalesce(jsonb_agg(jsonb_set(x,'{parts}',coalesce((select jsonb_agg(p-'costCents') from jsonb_array_elements(x->'parts') p),'[]'))),'[]') into orders_json from jsonb_array_elements(orders_json) x;
  end if;
  if m->>'role'='office' then incidents_json:=private.redact_costs(incidents_json); end if;
  return jsonb_build_object('workshopId',w,'orders',orders_json,'catalog',catalog_json,'members',(select coalesce(jsonb_agg(jsonb_build_object('id',user_id,'name',display_name,'role',role,'seePrices',false)),'[]') from private.members where workshop_id=w and active),'audit',audit_json,'applied','[]'::jsonb,'incidents',incidents_json);
end $$;

create function private.device_snapshot(w uuid,dev uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb; s jsonb; d private.devices%rowtype; o record; inserted int; receipts jsonb; closures jsonb; devices jsonb;
begin
 m:=private.membership(w);
 if dev is null then raise exception 'Device required'; end if;
 perform 1 from private.workshops where id=w for update;
 select * into d from private.devices where workshop_id=w and id=dev;
 if found and d.user_id<>auth.uid() then raise exception 'Device belongs to another user' using errcode='42501'; end if;
 if found and d.retired_at is not null then raise exception 'Device retired' using errcode='42501'; end if;
 if found and d.auth_session_id is not null and d.auth_session_id<>private.auth_session() then
  update private.close_requests set status='invalidated' where workshop_id=w and status='active' and order_id in (select order_id from private.order_devices where workshop_id=w and device_id=dev);
  insert into private.audit(workshop_id,actor_id,kind,after_data) values(w,auth.uid(),'session_rebound',jsonb_build_object('deviceId',dev));
 end if;
 if exists(select 1 from private.device_sessions ds join private.devices dv on dv.workshop_id=ds.workshop_id and dv.id=ds.device_id where ds.workshop_id=w and ds.session_id=private.auth_session() and dv.retired_at is not null) then raise exception 'Session belongs to retired device; fresh login required' using errcode='42501'; end if;
 if exists(select 1 from private.device_sessions where workshop_id=w and session_id=private.auth_session() and device_id<>dev) then raise exception 'Session already bound to another device' using errcode='42501'; end if;
 insert into private.devices(workshop_id,id,user_id,auth_session_id) values(w,dev,auth.uid(),private.auth_session()) on conflict(workshop_id,id) do update set last_seen=now(),auth_session_id=private.auth_session();
 insert into private.device_sessions values(w,private.auth_session(),dev) on conflict do nothing;
 s:=private.snapshot(w);
 for o in select value from jsonb_array_elements(s->'orders') loop
  insert into private.order_devices(workshop_id,order_id,device_id) values(w,(o.value->>'id')::uuid,dev) on conflict do nothing;
  get diagnostics inserted=row_count;
  if inserted>0 then perform private.invalidate_close(w,(o.value->>'id')::uuid); end if;
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'status',p.status,'reason',p.reason,'resolved',r.operation_id is not null)),'[]') into receipts
 from private.operations p left join private.resolutions r on r.workshop_id=p.workshop_id and r.operation_id=p.id
 where p.workshop_id=w and p.device_id=dev and p.actor_id=auth.uid();
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'orderId',c.order_id,'revision',c.revision,'status',c.status,'exceptionReason',c.exception_reason,
 'retiredDevices',c.retired_devices,'requiredDevices',(select coalesce(jsonb_agg(od.device_id),'[]') from private.order_devices od where od.workshop_id=w and od.order_id=c.order_id and not(c.retired_devices ? od.device_id::text)),
 'confirmedDevices',(select coalesce(jsonb_agg(a.device_id),'[]') from private.close_acknowledgements a where a.workshop_id=w and a.request_id=c.id))), '[]') into closures
 from private.close_requests c where c.workshop_id=w and exists(select 1 from jsonb_array_elements(s->'orders') v where v->>'id'=c.order_id::text);
 select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'userId',v.user_id,'lastSeen',v.last_seen,'retiredAt',v.retired_at,'reason',v.retirement_reason)),'[]') into devices
 from private.devices v where v.workshop_id=w and ((m->>'role') in ('office','admin') or v.user_id=auth.uid());
 -- Keep original evidence; resolution metadata is appended, never written over it.
 s:=jsonb_set(s,'{incidents}',coalesce((select jsonb_agg(i.value || jsonb_build_object('resolution',case when r.operation_id is null then null else jsonb_build_object('responsibleId',r.responsible_id,'reason',r.reason,'outcome',r.outcome,'correctionId',r.correction_id,'at',r.resolved_at) end))
 from jsonb_array_elements(s->'incidents') i left join private.resolutions r on r.workshop_id=w and r.operation_id=(i.value->'operation'->>'id')::uuid),'[]'));
 return s || jsonb_build_object('actor',m,'serverTime',now(),'receipts',receipts,'closures',closures,'devices',devices,'retiredTimers',case when m->>'role' in ('office','admin') then (select coalesce(jsonb_agg(jsonb_build_object('id',ts.id,'orderId',ts.order_id,'actorId',ts.actor_id,'deviceId',ts.device_id,'start',ts.started_at)),'[]') from private.time_sessions ts join private.devices dv on dv.workshop_id=ts.workshop_id and dv.id=ts.device_id where ts.workshop_id=w and ts.ended_at is null and dv.retired_at is not null) else '[]'::jsonb end);
end $$;

create function private.note_snapshot(d jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare t jsonb; p jsonb; l jsonb; lines jsonb:='[]'; net bigint; tax bigint; q bigint; returned bigint; total_net bigint:=0; total_tax bigint:=0;
begin
 for t in select value from jsonb_array_elements(d->'tasks') loop
  if (t->>'billableMinutes')::bigint>0 then
   if not coalesce((t->>'authorized')::boolean,false) or coalesce((t->>'rateCents')::bigint,0)<=0 then raise exception 'Unauthorized or unpriced labor'; end if;
   net:=((t->>'billableMinutes')::bigint*(t->>'rateCents')::bigint+30)/60;
   tax:=(net*(t->>'taxBps')::bigint+5000)/10000;
   lines:=lines||jsonb_build_array(jsonb_build_object('taskId',t->>'id','description',t->>'title','quantity',(t->>'billableMinutes')||' min','netCents',net,'taxCents',tax));
  end if;
 end loop;
 for p in select value from jsonb_array_elements(d->'parts') loop
  if p->>'kind'='consume' and (p->>'charge')::boolean then
   if (p->>'priceCents')::bigint<0 then raise exception 'Missing price'; end if;
   if not exists(select 1 from jsonb_array_elements(d->'tasks') x where x->>'id'=p->>'taskId' and (x->>'authorized')::boolean) then raise exception 'Unauthorized consumption'; end if;
   select coalesce(sum((x->>'quantityMilli')::bigint),0) into returned from jsonb_array_elements(d->'parts') x where x->>'kind'='return' and x->>'sourceId'=p->>'id';
   q:=(p->>'quantityMilli')::bigint-returned;
   if q<0 then raise exception 'Invalid return'; end if;
   if q>0 then
    net:=(q*(p->>'priceCents')::bigint+500)/1000; tax:=(net*(p->>'taxBps')::bigint+5000)/10000;
    lines:=lines||jsonb_build_array(jsonb_build_object('taskId',p->>'taskId','description',p->>'description','quantity',replace(trim(trailing '.' from trim(trailing '0' from to_char(q::numeric/1000,'FM999999999990.000'))),'.',',')||' '||(p->>'unit'),'netCents',net,'taxCents',tax));
   end if;
  end if;
 end loop;
 for t in select value from jsonb_array_elements(d->'tasks') loop
  select coalesce(sum((x->>'netCents')::bigint+(x->>'taxCents')::bigint),0) into net from jsonb_array_elements(lines) x where x->>'taskId'=t->>'id';
  if net>coalesce((t->>'approvedCents')::bigint,0) then raise exception 'Amount exceeds task authorization'; end if;
 end loop;
 for l in select value from jsonb_array_elements(lines) loop total_net:=total_net+(l->>'netCents')::bigint; total_tax:=total_tax+(l->>'taxCents')::bigint; end loop;
 return jsonb_build_object('netCents',total_net,'taxCents',total_tax,'totalCents',total_net+total_tax,'lines',lines);
end $$;

create function private.reliability_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb; own_device private.devices%rowtype; old_receipt private.command_receipts%rowtype;
 oid uuid:=(p->>'orderId')::uuid; req private.close_requests%rowtype; d jsonb; rev bigint; r jsonb:='{}'; retired jsonb;
 ts private.time_sessions%rowtype; end_time timestamptz; entry jsonb;
 original private.operations%rowtype; correction jsonb; correction_id uuid; correction_result jsonb; target uuid; doc jsonb;
begin
 m:=private.membership(w);
 if cid is null or jsonb_typeof(p)<>'object' then raise exception 'Malformed command'; end if;
 perform 1 from private.workshops where id=w for update;
 select * into own_device from private.devices where workshop_id=w and id=dev and user_id=auth.uid();
 if not found or (own_device.retired_at is not null and action<>'replace_device') then raise exception 'Active registered device required' using errcode='42501'; end if;
 if action<>'replace_device' and own_device.auth_session_id is distinct from private.auth_session() then raise exception 'Device session mismatch' using errcode='42501'; end if;
 if action not in ('ack_close','replace_device') and m->>'role'='technician' then raise exception 'Office permission required' using errcode='42501'; end if;
 select * into old_receipt from private.command_receipts where workshop_id=w and id=cid;
 if found then
  if old_receipt.actor_id<>auth.uid() or old_receipt.device_id<>dev or old_receipt.action<>action or old_receipt.payload<>p then raise exception 'Command id reused'; end if;
  if m->>'role'='technician' and not (m->>'seePrices')::boolean then return private.redact_prices(old_receipt.result); end if;
  return old_receipt.result;
 end if;
 if action not in ('ack_close','replace_device') and m->>'role'='technician' then raise exception 'Office permission required' using errcode='42501'; end if;
 if action in ('request_close','ack_close','issue') then
  select data,revision into d,rev from private.orders where workshop_id=w and id=oid;
  if not found or not exists(select 1 from private.order_devices where workshop_id=w and order_id=oid and device_id=dev) then raise exception 'Order not enrolled'; end if;
  if m->>'role'='technician' and not exists(select 1 from jsonb_array_elements(d->'tasks') t where t->'assignees' ? auth.uid()::text) then raise exception 'Order not assigned' using errcode='42501'; end if;
 end if;
 case action
 when 'replace_device' then
  if own_device.retired_at is null then raise exception 'Only replace a retired device'; end if;
  if own_device.auth_session_id is null then raise exception 'Legacy device requires server Auth session revocation and supervised migration'; end if;
  if own_device.auth_session_id=private.auth_session() or exists(select 1 from private.device_sessions where workshop_id=w and session_id=private.auth_session()) then raise exception 'Fresh login required for replacement' using errcode='42501'; end if;
  target:=(p->>'newDeviceId')::uuid;
  if target is null or exists(select 1 from private.devices where workshop_id=w and id=target) then raise exception 'New unique device identity required'; end if;
  insert into private.devices(workshop_id,id,user_id,auth_session_id) values(w,target,auth.uid(),private.auth_session());
  insert into private.device_sessions values(w,private.auth_session(),target);
  r:=jsonb_build_object('newDeviceId',target,'previousCommands',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'result',c.result)) from private.command_receipts c where c.workshop_id=w and c.device_id=dev and c.actor_id=auth.uid()),'[]'));
 when 'request_close' then
  if d->'document' is not null and d->'document'<>'null'::jsonb then raise exception 'Already issued'; end if;
  if rev is distinct from (p->>'revision')::bigint then raise exception 'Revision changed'; end if;
  select coalesce(jsonb_agg(v.id),'[]') into retired from private.order_devices od join private.devices v on v.workshop_id=od.workshop_id and v.id=od.device_id where od.workshop_id=w and od.order_id=oid and v.retired_at is not null;
  if jsonb_array_length(retired)>0 then
   if m->>'role'<>'admin' or coalesce(trim(p->>'exceptionReason'),'')='' then raise exception 'Retired devices require explicit administrator closure exception'; end if;
  elsif coalesce(trim(p->>'exceptionReason'),'')<>'' then raise exception 'No retired devices to exempt'; end if;
  perform private.invalidate_close(w,oid);
  insert into private.close_requests(workshop_id,order_id,revision,status,requested_by,exception_reason,retired_devices)
   values(w,oid,rev,'active',auth.uid(),nullif(trim(p->>'exceptionReason'),''),retired) returning * into req;
  r:=jsonb_build_object('requestId',req.id,'revision',rev);
 when 'ack_close' then
  select * into req from private.close_requests where workshop_id=w and id=(p->>'requestId')::uuid and order_id=oid;
  if not found or req.status<>'active' or req.revision<>rev or req.revision is distinct from (p->>'revision')::bigint then raise exception 'Obsolete closure confirmation'; end if;
  if coalesce((p->>'locallyFrozen')::boolean,false)=false then raise exception 'Persist local freeze before confirmation'; end if;
  if exists(select 1 from private.time_sessions where workshop_id=w and order_id=oid and actor_id=auth.uid() and ended_at is null) then raise exception 'Stop timers and renew closure request'; end if;
  if exists(select 1 from private.operations o where o.workshop_id=w and o.device_id=dev and o.order_id=oid and o.status<>'accepted' and not exists(select 1 from private.resolutions rr where rr.workshop_id=w and rr.operation_id=o.id)) then raise exception 'Unresolved device records'; end if;
  insert into private.close_acknowledgements values(w,req.id,dev,rev,auth.uid(),now()) on conflict do nothing;
  r:=jsonb_build_object('confirmed',true);
 when 'issue' then
  select * into req from private.close_requests where workshop_id=w and id=(p->>'requestId')::uuid and order_id=oid;
  if not found or req.status<>'active' or req.revision<>rev then raise exception 'Active reconciled revision required'; end if;
  if exists(select 1 from private.order_devices od where od.workshop_id=w and od.order_id=oid and not(req.retired_devices ? od.device_id::text) and not exists(select 1 from private.close_acknowledgements a where a.workshop_id=w and a.request_id=req.id and a.device_id=od.device_id and a.revision=rev)) then raise exception 'Unreconciled device blocks closure'; end if;
  if exists(select 1 from private.order_devices od join private.devices v on v.workshop_id=od.workshop_id and v.id=od.device_id where od.workshop_id=w and od.order_id=oid and v.retired_at is not null and not(req.retired_devices ? v.id::text)) then raise exception 'Retired device requires explicit exception'; end if;
  if exists(select 1 from private.operations o where o.workshop_id=w and o.order_id=oid and o.status<>'accepted' and not exists(select 1 from private.resolutions rr where rr.workshop_id=w and rr.operation_id=o.id)) then raise exception 'Unresolved records block closure'; end if;
  if exists(select 1 from private.time_sessions where workshop_id=w and order_id=oid and ended_at is null) then raise exception 'Active timers'; end if;
  if exists(select 1 from jsonb_array_elements(d->'tasks') t where (t->>'authorized')::boolean and not(t->>'done')::boolean) then raise exception 'Incomplete authorized task'; end if;
  if d->'quality' is null or d->'quality'='null'::jsonb then raise exception 'Final check required'; end if;
  if exists(select 1 from jsonb_array_elements(d->'parts') t where coalesce((t->>'reviewed')::boolean,false)=false) then raise exception 'Unreviewed movement'; end if;
  if not private.stock_valid(w) then raise exception 'Stock discrepancy'; end if;
  doc:=private.note_snapshot(d)||jsonb_build_object('type','work_note','issuedAt',now(),'issuedBy',auth.uid(),'revision',rev,'clientSnapshot',d->>'client','plateSnapshot',d->>'plate','closureRequestId',req.id,'closureException',req.exception_reason,'retiredDevices',req.retired_devices);
  insert into private.documents(workshop_id,order_id,type,version,recipient_id,snapshot) values(w,oid,'work_note',1,gen_random_uuid(),doc);
  update private.orders set data=jsonb_set(data,'{document}',doc),revision=revision+1 where workshop_id=w and id=oid;
  update private.close_requests set status='issued' where workshop_id=w and id=req.id;
  r:=jsonb_build_object('document',doc);
 when 'end_retired_timer' then
  select * into ts from private.time_sessions where workshop_id=w and id=(p->>'sessionId')::uuid and ended_at is null;
  if not found or not exists(select 1 from private.devices where workshop_id=w and id=ts.device_id and retired_at is not null) then raise exception 'Active timer from retired device required'; end if;
  end_time:=(p->>'end')::timestamptz;
  if end_time is null or end_time<ts.started_at or end_time>now() or coalesce(trim(p->>'reason'),'')='' then raise exception 'Actual stop time and reason required'; end if;
  oid:=ts.order_id;
  select data into d from private.orders where workshop_id=w and id=oid;
  if d->'document' is not null and d->'document'<>'null'::jsonb then raise exception 'Issued document is immutable'; end if;
  update private.time_sessions set ended_at=end_time where workshop_id=w and id=ts.id;
  select jsonb_agg(case when t->>'id'=ts.id::text then t||jsonb_build_object('end',end_time,'recoveryAuthor',auth.uid(),'recoveryReason',p->>'reason') else t end) into entry from jsonb_array_elements(d->'times') t;
  update private.orders set data=jsonb_set(jsonb_set(data,'{times}',entry),'{quality}','null'),revision=revision+1 where workshop_id=w and id=oid;
  perform private.invalidate_close(w,oid);
  r:=jsonb_build_object('stopped',true,'sessionId',ts.id,'end',end_time);
 when 'retire_device' then
  if coalesce(trim(p->>'reason'),'')='' then raise exception 'Retirement reason required'; end if;
  target:=(p->>'deviceId')::uuid;
  if target=dev then raise exception 'Retire this device from another office device'; end if;
  if not exists(select 1 from private.devices where workshop_id=w and id=target) then raise exception 'Device not in workshop'; end if;
  if exists(select 1 from private.devices where workshop_id=w and id=target and retired_at is not null) then raise exception 'Already retired'; end if;
  update private.devices set retired_at=now(),retirement_reason=p->>'reason' where workshop_id=w and id=target;
  update private.close_requests set status='invalidated' where workshop_id=w and status='active' and order_id in (select order_id from private.order_devices where workshop_id=w and device_id=target);
  r:=jsonb_build_object('retired',true,'deviceId',target);
 when 'resolve' then
  if coalesce(trim(p->>'reason'),'')='' or p->>'outcome' not in ('archive','retry') then raise exception 'Resolution reason and outcome required'; end if;
  select * into original from private.operations where workshop_id=w and id=(p->>'operationId')::uuid and status<>'accepted';
  if not found or exists(select 1 from private.resolutions where workshop_id=w and operation_id=original.id) then raise exception 'Unresolved record not found'; end if;
  oid:=original.order_id;
  select data,revision into d,rev from private.orders where workshop_id=w and id=oid;
  if rev is distinct from (p->>'revision')::bigint then raise exception 'Review current order before resolution'; end if;
  if p->>'outcome'='retry' then
   if d->'document' is not null and d->'document'<>'null'::jsonb then raise exception 'Issued document cannot absorb late records; archive evidence with follow-up reason'; end if;
   correction_id:=gen_random_uuid();
   correction:=original.operation||jsonb_build_object('id',correction_id,'baseRevision',rev);
   correction_result:=private.apply_record(w,original.device_id,correction,original.actor_id);
   if original.operation->>'kind'='receive' and correction_result->>'status'='accepted' then
    insert into private.order_devices(workshop_id,order_id,device_id) values(w,oid,dev),(w,oid,original.device_id) on conflict do nothing;
   end if;
   if correction_result->>'status'<>'accepted' or not private.stock_valid(w) then raise exception 'Correction could not be applied: %',coalesce(correction_result->>'reason','Stock conflict'); end if;
  end if;
  insert into private.resolutions values(w,original.id,auth.uid(),p->>'reason',p->>'outcome',correction_id,now());
  perform private.invalidate_close(w,oid);
  r:=jsonb_build_object('resolved',true,'correctionId',correction_id);
 else raise exception 'Unsupported reliability action';
 end case;
 insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,after_data) values(w,auth.uid(),cid,oid,action,jsonb_build_object('payload',p,'result',r));
 insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,r);
 if m->>'role'='technician' and not (m->>'seePrices')::boolean then return private.redact_prices(r); end if;
 return r;
end $$;

create function public.device_snapshot(workshop_id uuid,device_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.device_snapshot($1,$2) $$;
create function public.reliability_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.reliability_command($1,$2,$3,$4,$5) $$;
revoke all on all functions in schema private from public,anon,authenticated;
grant execute on function private.membership(uuid),private.snapshot(uuid),private.apply(uuid,uuid,jsonb),private.device_snapshot(uuid,uuid),private.reliability_command(uuid,uuid,uuid,text,jsonb) to authenticated;
revoke all on function public.device_snapshot(uuid,uuid),public.reliability_command(uuid,uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.device_snapshot(uuid,uuid),public.reliability_command(uuid,uuid,uuid,text,jsonb) to authenticated;
commit;
