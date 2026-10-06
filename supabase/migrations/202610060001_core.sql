-- TallerFlow 0.1: private data, authenticated command API, no client table writes.
begin;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table private.workshops (
  id uuid primary key default gen_random_uuid(), name text not null,
  billing_country text not null default 'ES', settings jsonb not null default '{"hourlyRateCents":4800,"taxBps":2100,"internalHourlyCostCents":2200,"aiEnabled":false}'
);
create table private.members (
  workshop_id uuid not null references private.workshops(id), user_id uuid not null references auth.users(id),
  display_name text not null, role text not null check (role in ('technician','office','admin')),
  see_prices boolean not null default false, active boolean not null default true,
  primary key (workshop_id,user_id)
);
create table private.vehicles (
  workshop_id uuid not null references private.workshops(id), id uuid not null default gen_random_uuid(),
  plate text not null, country text not null, vin text, technical jsonb not null default '{}',
  primary key (workshop_id,id), unique (workshop_id,country,plate)
);
create unique index vehicle_vin on private.vehicles(workshop_id,vin) where vin is not null;
create table private.orders (
  workshop_id uuid not null references private.workshops(id), id uuid not null,
  vehicle_id uuid not null, data jsonb not null, revision bigint not null default 0,
  primary key (workshop_id,id), foreign key (workshop_id,vehicle_id) references private.vehicles(workshop_id,id)
);
create table private.catalog (
  workshop_id uuid not null references private.workshops(id), id uuid not null default gen_random_uuid(),
  reference text not null, description text not null, unit text not null,
  price_cents bigint not null check(price_cents >= 0), cost_cents bigint not null check(cost_cents >= 0),
  stock_milli bigint not null check(stock_milli >= 0), min_milli bigint not null default 0 check(min_milli >= 0),
  primary key(workshop_id,id), unique(workshop_id,reference)
);
create table private.devices (
  workshop_id uuid not null references private.workshops(id), id uuid not null,
  user_id uuid not null references auth.users(id), last_seen timestamptz not null default now(),
  primary key(workshop_id,id)
);
create table private.operations (
  workshop_id uuid not null references private.workshops(id), id uuid not null,
  order_id uuid not null, actor_id uuid not null references auth.users(id), device_id uuid not null,
  received_at timestamptz not null default now(), operation jsonb not null,
  status text not null check(status in ('accepted','conflict','late')), reason text,
  primary key(workshop_id,id), foreign key(workshop_id,device_id) references private.devices(workshop_id,id)
);
create table private.time_sessions (
  workshop_id uuid not null, id uuid not null, order_id uuid not null,
  task_id uuid not null, actor_id uuid not null references auth.users(id), device_id uuid not null,
  started_at timestamptz not null, ended_at timestamptz,
  primary key(workshop_id,id), foreign key(workshop_id,order_id) references private.orders(workshop_id,id),
  check(ended_at is null or ended_at >= started_at)
);
create unique index one_active_timer_per_user on private.time_sessions(actor_id) where ended_at is null;
create table private.audit (
  id bigint generated always as identity primary key, workshop_id uuid not null,
  actor_id uuid not null, operation_id uuid, order_id uuid, occurred_at timestamptz not null default now(),
  kind text not null, before_data jsonb, after_data jsonb
);
create table private.documents (
  workshop_id uuid not null, id uuid not null default gen_random_uuid(), order_id uuid not null,
  type text not null check(type in ('work_note','estimate')), version int not null,
  recipient_id uuid not null, snapshot jsonb not null, issued_at timestamptz not null default now(),
  primary key(workshop_id,id), foreign key(workshop_id,order_id) references private.orders(workshop_id,id)
);
-- Immutable issued documents. Corrections must create a linked replacement later.
create function private.immutable_document() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Issued documents are immutable'; end $$;
create trigger documents_immutable before update or delete on private.documents for each row execute function private.immutable_document();
-- Defense in depth: the private schema is not exposed by PostgREST; no table grants.
do $$ declare t text; begin
  foreach t in array array['workshops','members','vehicles','orders','catalog','devices','operations','time_sessions','audit','documents'] loop
    execute format('alter table private.%I enable row level security', t);
    execute format('revoke all on private.%I from public,anon,authenticated', t);
  end loop;
end $$;

create function private.membership(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m private.members%rowtype;
begin
  select * into m from private.members where workshop_id=w and user_id=auth.uid() and active;
  if not found then raise exception 'Membership required' using errcode='42501'; end if;
  return jsonb_build_object('id',m.user_id,'name',m.display_name,'role',m.role,'seePrices',m.see_prices);
end $$;
create function public.my_membership(workshop_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select private.membership($1) $$;

create function private.redact_prices(value jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb; k text; v jsonb;
begin
  if jsonb_typeof(value)='array' then
    select coalesce(jsonb_agg(private.redact_prices(x)),'[]') into result from jsonb_array_elements(value) x;
    return result;
  elsif jsonb_typeof(value)='object' then
    result := '{}';
    for k,v in select * from jsonb_each(value) loop
      if k not in ('priceCents','costCents','rateCents','approvedCents','netCents','taxCents','totalCents','document','authorization') then
        result := result || jsonb_build_object(k,private.redact_prices(v));
      end if;
    end loop;
    return result;
  end if;
  return value;
end $$;

create function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
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
  return jsonb_build_object('workshopId',w,'orders',orders_json,'catalog',catalog_json,'members',(select coalesce(jsonb_agg(jsonb_build_object('id',user_id,'name',display_name,'role',role,'seePrices',false)),'[]') from private.members where workshop_id=w and active),'audit',audit_json,'applied','[]'::jsonb,'incidents',incidents_json);
end $$;
create function public.workshop_snapshot(workshop_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select private.snapshot($1) $$;

create function private.apply(w uuid, dev uuid, op jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  m jsonb; opid uuid; oid uuid; kind text; p jsonb; at_time timestamptz; d jsonb; before_doc jsonb;
  tid uuid; t jsonb; task_index int; entry jsonb; item private.catalog%rowtype;
  q bigint; sid uuid; n bigint; amount bigint; vid uuid; canonical_plate text;
  session private.time_sessions%rowtype; previous private.operations%rowtype;
  reason text; response_status text := 'accepted'; settings jsonb; current_revision bigint;
begin
  m := private.membership(w);
  if (op->>'actorId') is distinct from auth.uid()::text then raise exception 'Actor mismatch' using errcode='42501'; end if;
  opid := (op->>'id')::uuid; oid := (op->>'orderId')::uuid; kind := op->>'kind'; p := op->'payload'; at_time := (op->>'at')::timestamptz;
  if opid is null or oid is null or kind is null or jsonb_typeof(p) <> 'object' then raise exception 'Malformed operation'; end if;
  if at_time is null or at_time > now()+interval '2 minutes' then raise exception 'Invalid device time'; end if;
  -- Serializes mutations inside a workshop and user timers across workshops.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
  select s.settings into settings from private.workshops s where s.id=w for update;
  select * into previous from private.operations where workshop_id=w and id=opid;
  if found then
    if previous.actor_id <> auth.uid() or previous.operation <> op then raise exception 'Idempotency key reused with different data'; end if;
    return jsonb_build_object('status',previous.status,'reason',previous.reason);
  end if;
  insert into private.devices(workshop_id,id,user_id) values(w,dev,auth.uid())
    on conflict(workshop_id,id) do update set last_seen=now() where private.devices.user_id=auth.uid();
  if not exists(select 1 from private.devices where workshop_id=w and id=dev and user_id=auth.uid()) then raise exception 'Device belongs to another user' using errcode='42501'; end if;
  if kind in ('receive','authorize','billable','review_parts','issue','deliver') and m->>'role'='technician' then raise exception 'Office permission required' using errcode='42501'; end if;
  select data,revision into d,current_revision from private.orders where workshop_id=w and id=oid for update;
  before_doc := d;
  if kind <> 'receive' then
    if d is null then raise exception 'Order not found'; end if;
    if m->>'role'='technician' and not exists(select 1 from jsonb_array_elements(d->'tasks') z where z->'assignees' ? auth.uid()::text) then raise exception 'Order not assigned' using errcode='42501'; end if;
    if d->'document' is not null and d->'document' <> 'null'::jsonb and kind <> 'deliver' then
      insert into private.operations values(w,opid,oid,auth.uid(),dev,now(),op,'late','Registro recibido después de emitir la nota');
      return '{"status":"late"}';
    end if;
  end if;
  -- Validation failures roll back only the mutation, retaining the incoming evidence.
  begin
    if kind in ('start','manual_time','part','finish_task','authorize','billable') then
      tid := (p->>'taskId')::uuid;
      select x.value,(x.ordinality-1)::int into t,task_index from jsonb_array_elements(d->'tasks') with ordinality x where x.value->>'id'=tid::text;
      if t is null then raise exception 'Task not found'; end if;
      if m->>'role'='technician' and not(t->'assignees' ? auth.uid()::text) then raise exception 'Task not assigned'; end if;
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
        if exists(select 1 from private.time_sessions where actor_id=auth.uid() and (ended_at is null or ended_at>at_time)) then raise exception 'Incompatible timer session'; end if;
        insert into private.time_sessions values(w,opid,oid,tid,auth.uid(),dev,at_time,null);
        entry := jsonb_build_object('id',opid,'taskId',tid,'actorId',auth.uid(),'start',at_time,'end',null,'source','timer');
        d := jsonb_set(d,'{times}',d->'times'||jsonb_build_array(entry));
        d := d || '{"status":"repair","quality":null}';
      when 'stop' then
        sid := (p->>'sessionId')::uuid;
        select * into session from private.time_sessions where workshop_id=w and id=sid and order_id=oid for update;
        if session.actor_id is distinct from auth.uid() or session.ended_at is not null or session.started_at>at_time then raise exception 'Invalid timer stop'; end if;
        update private.time_sessions set ended_at=at_time where workshop_id=w and id=sid;
        select jsonb_agg(case when z->>'id'=sid::text then z||jsonb_build_object('end',at_time) else z end) into entry from jsonb_array_elements(d->'times') z;
        d := jsonb_set(d,'{times}',entry);
      when 'manual_time' then
        if coalesce(trim(p->>'reason'),'')='' or (p->>'end')::timestamptz>(at_time+interval '2 minutes') or (p->>'end')::timestamptz<=(p->>'start')::timestamptz then raise exception 'Invalid manual time or missing reason'; end if;
        if exists(select 1 from private.time_sessions where actor_id=auth.uid() and started_at<(p->>'end')::timestamptz and coalesce(ended_at,'infinity'::timestamptz)>(p->>'start')::timestamptz) then raise exception 'Time interval overlaps an existing session'; end if;
        insert into private.time_sessions values(w,opid,oid,tid,auth.uid(),dev,(p->>'start')::timestamptz,(p->>'end')::timestamptz);
        entry := jsonb_build_object('id',opid,'taskId',tid,'actorId',auth.uid(),'start',p->>'start','end',p->>'end','reason',p->>'reason','source','manual');
        d := jsonb_set(d,'{times}',d->'times'||jsonb_build_array(entry));
        d := jsonb_set(d,'{quality}','null');
      when 'part' then
        q := (p->>'quantityMilli')::bigint;
        if q is null or q<=0 or p->>'kind' not in ('consume','reserve','customer') then raise exception 'Invalid part movement'; end if;
        select * into item from private.catalog where workshop_id=w and id=(p->>'itemId')::uuid;
        if not found then raise exception 'Catalog reference not found'; end if;
        entry := jsonb_build_object('id',opid,'taskId',tid,'itemId',item.id,'description',item.description,'reference',item.reference,'unit',item.unit,'quantityMilli',q,'priceCents',item.price_cents,'costCents',item.cost_cents,'taxBps',(settings->>'taxBps')::int,'kind',p->>'kind','charge',p->>'kind'='consume','reviewed',false,'actorId',auth.uid());
        d := jsonb_set(d,'{parts}',d->'parts'||jsonb_build_array(entry));
        d := jsonb_set(d,'{quality}','null');
      when 'return' then
        select z into entry from jsonb_array_elements(d->'parts') z where z->>'id'=p->>'sourceId' and z->>'kind'='consume';
        if entry is null then raise exception 'Consumption not found'; end if;
        if m->>'role'='technician' and not exists(select 1 from jsonb_array_elements(d->'tasks') z where z->>'id'=entry->>'taskId' and z->'assignees' ? auth.uid()::text) then raise exception 'Task not assigned'; end if;
        select coalesce(sum((z->>'quantityMilli')::bigint),0) into n from jsonb_array_elements(d->'parts') z where z->>'sourceId'=entry->>'id';
        q := (p->>'quantityMilli')::bigint;
        if q is null or q<=0 or q+n>(entry->>'quantityMilli')::bigint then raise exception 'Return exceeds consumption'; end if;
        entry := entry||jsonb_build_object('id',opid,'kind','return','sourceId',entry->>'id','quantityMilli',q,'charge',false,'reviewed',false,'actorId',auth.uid());
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
        t := t||jsonb_build_object('authorized',true,'approvedCents',amount,'authorization',p||jsonb_build_object('actorId',auth.uid(),'at',at_time));
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
        d := d||jsonb_build_object('status','verified','quality',p||jsonb_build_object('actorId',auth.uid(),'at',at_time));
      when 'block' then
        if coalesce(trim(p->>'reason'),'')='' then raise exception 'Block reason required'; end if;
        d := d||jsonb_build_object('status','parts','block',p->>'reason','nextAction',p->>'nextAction');
      when 'issue' then
        -- Deliberately fail closed until device reconciliation barriers are implemented.
        raise exception 'Cloud document issuing disabled until all-device reconciliation is validated';
      when 'deliver' then
        if d->'document' is null or d->'document'='null'::jsonb or coalesce(trim(p->>'reason'),'')='' then raise exception 'Issued note and delivery reason required'; end if;
        d := d||jsonb_build_object('status','delivered','delivery',p||jsonb_build_object('actorId',auth.uid(),'at',at_time));
      else raise exception 'Unsupported operation';
    end case;
    update private.orders set data=d,revision=current_revision+1 where workshop_id=w and id=oid;
    insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,before_data,after_data) values(w,auth.uid(),opid,oid,kind,before_doc,d);
  exception when others then
    get stacked diagnostics reason = message_text;
    response_status := 'conflict';
  end;
  insert into private.operations values(w,opid,oid,auth.uid(),dev,now(),op,response_status,reason);
  return jsonb_build_object('status',response_status,'reason',reason);
end $$;
create function public.apply_operation(workshop_id uuid, device_id uuid, operation jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.apply($1,$2,$3) $$;

revoke all on all functions in schema private from public,anon,authenticated;
revoke all on function public.my_membership(uuid),public.workshop_snapshot(uuid),public.apply_operation(uuid,uuid,jsonb) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.membership(uuid),private.snapshot(uuid),private.apply(uuid,uuid,jsonb) to authenticated;
grant execute on function public.my_membership(uuid),public.workshop_snapshot(uuid),public.apply_operation(uuid,uuid,jsonb) to authenticated;
-- Future functions must not accidentally become public APIs.
alter default privileges in schema private revoke execute on functions from public;
alter default privileges in schema private revoke all on tables from anon,authenticated;
commit;
