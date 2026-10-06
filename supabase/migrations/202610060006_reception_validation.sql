-- Reception uses the same validated task defaults as later task creation.
begin;
create or replace function private.new_task(w uuid,v jsonb,s jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if v->>'id' is null or (v->>'id')::uuid is null then raise exception 'Task ID required';end if;
 return jsonb_build_object('id',(v->>'id')::uuid::text,'title',private.require_text(v->>'title','Task title',300),
  'estimateMinutes',private.require_int(v->'estimateMinutes',1,14400,'Estimate'),'assignees',private.validate_assignees(w,v->'assignees'),
  'authorized',false,'authorization',null,'approvedCents',0,'done',false,'billableMinutes',0,
  'rateCents',(s->>'hourlyRateCents')::bigint,'taxBps',(s->>'taxBps')::int,'scopeVersion',1,'block',null);
end $$;
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
        if coalesce(canonical_plate,'')='' or coalesce(trim(p->>'symptom'),'')='' or coalesce(trim(p->>'client'),'')='' then raise exception 'Reception fields required'; end if;
        select id into vid from private.vehicles where workshop_id=w and ((coalesce(p->>'vin','')<>'' and vin=upper(p->>'vin')) or (country=p->>'country' and plate=canonical_plate));
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
        insert into private.orders(workshop_id,id,vehicle_id,data) values(w,oid,vid,d);
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


commit;
