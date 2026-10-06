-- Pricing review retains source movements, costs, work and original documents.
create function private.review_pricing(d jsonb,p jsonb,actor uuid,opid uuid,at_time timestamptz) returns jsonb language plpgsql immutable set search_path='' as $$
declare labor boolean; e jsonb; t jsonb; idx int; task_idx int; before_value jsonb; after_value jsonb;
 price bigint; tax bigint; discount bigint; reason text; requires_auth boolean; price_key text;
begin
 if jsonb_typeof(p)<>'object' or exists(select 1 from jsonb_object_keys(p) k where k<>all(array['target','targetId','unitPriceCents','taxBps','discountBps','charge','reason'])) then raise exception 'Unsupported pricing field';end if;
 reason:=private.require_text(p->>'reason','Reason');price:=private.require_int(p->'unitPriceCents',0,10000000,'Price');
 tax:=private.require_int(p->'taxBps',0,10000,'Tax');discount:=private.require_int(p->'discountBps',0,10000,'Discount');
 if jsonb_typeof(p->'charge') is distinct from 'boolean' then raise exception 'Charge choice required';end if;
 labor:=p->>'target'='labor';
 if p->>'target' is null or p->>'target' not in ('labor','part') then raise exception 'Invalid pricing target';end if;
 select x.value,(x.ordinality-1)::int into e,idx from jsonb_array_elements(case when labor then d->'tasks' else d->'parts' end) with ordinality x where x.value->>'id'=p->>'targetId';
 if e is null or (labor and coalesce((e->>'cancelled')::boolean,false)) or (not labor and e->>'kind'<>'consume') then raise exception 'Active task or consumption required';end if;
 if labor and not(p->>'charge')::boolean then raise exception 'Use billable minutes or discount for labor';end if;
 if labor and exists(select 1 from jsonb_array_elements(d->'times') x where x->>'taskId'=e->>'id' and (x->'end' is null or x->'end'='null')) then raise exception 'Pause task timers before review';end if;
 price_key:=case when labor then 'rateCents' else 'priceCents' end;
 before_value:=jsonb_build_object('unitPriceCents',coalesce((e->>price_key)::bigint,0),'taxBps',coalesce((e->>'taxBps')::bigint,2100),'discountBps',coalesce((e->>'discountBps')::bigint,0),'charge',labor or coalesce((e->>'charge')::boolean,false));
 after_value:=jsonb_build_object('unitPriceCents',price,'taxBps',tax,'discountBps',discount,'charge',p->'charge');
 requires_auth:=(p->>'charge')::boolean and (not(before_value->>'charge')::boolean or price>(before_value->>'unitPriceCents')::bigint or tax>(before_value->>'taxBps')::bigint or discount<(before_value->>'discountBps')::bigint);
 select x.value,(x.ordinality-1)::int into t,task_idx from jsonb_array_elements(d->'tasks') with ordinality x where x.value->>'id'=case when labor then e->>'id' else e->>'taskId' end;
 if t is null then raise exception 'Task not found';end if;
 e:=e||jsonb_build_object(price_key,price,'taxBps',tax,'discountBps',discount);
 if labor then t:=e;else
  e:=e||jsonb_build_object('charge',p->'charge','reviewed',true,'noChargeReason',case when not(p->>'charge')::boolean then reason end);
  d:=jsonb_set(d,array['parts',idx::text],e);
 end if;
 if requires_auth then
  t:=t||jsonb_build_object('previousAuthorizations',coalesce(t->'previousAuthorizations','[]')||case when t->'authorization' is null or t->'authorization'='null' then '[]'::jsonb else jsonb_build_array(t->'authorization') end,'authorized',false,'authorization',null,'approvedCents',0);
 end if;
 t:=t||jsonb_build_object('priceVersion',coalesce((t->>'priceVersion')::int,1)+1);
 d:=jsonb_set(d,array['tasks',task_idx::text],t);
 return d||jsonb_build_object('pricingReviews',coalesce(d->'pricingReviews','[]')||jsonb_build_array(jsonb_build_object('id',opid,'target',p->>'target','targetId',p->>'targetId','actorId',actor,'at',at_time,'reason',reason,'before',before_value,'after',after_value,'requiresAuthorization',requires_auth)));
end $$;
revoke all on function private.review_pricing(jsonb,jsonb,uuid,uuid,timestamptz) from public,anon,authenticated;

create or replace function private.redact_prices(value jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb; k text; v jsonb;
begin
 if jsonb_typeof(value)='array' then select coalesce(jsonb_agg(private.redact_prices(x)),'[]') into result from jsonb_array_elements(value) x;return result;
 elsif jsonb_typeof(value)='object' then
  result:='{}';for k,v in select * from jsonb_each(value) loop
   if k not in ('priceCents','rateCents','unitPriceCents','approvedCents','netCents','taxCents','totalCents','grossCents','discountCents','discountBps','taxBps','hourlyRateCents','document','authorization','pricingReviews') then result:=result||jsonb_build_object(k,private.redact_prices(v));end if;
  end loop;return result;
 end if;return value;
end $$;
create or replace function private.redact_costs(value jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb; k text; v jsonb;
begin
 if jsonb_typeof(value)='array' then select coalesce(jsonb_agg(private.redact_costs(x)),'[]') into result from jsonb_array_elements(value) x;return result;
 elsif jsonb_typeof(value)='object' then
  result:='{}';for k,v in select * from jsonb_each(value) loop
   if k not in ('costCents','costKnown','internalHourlyCostCents','internalCostKnown','internalCostCents','marginCents','registeredCostCents') then result:=result||jsonb_build_object(k,private.redact_costs(v));end if;
  end loop;return result;
 end if;return value;
end $$;


create or replace function private.new_task(w uuid,v jsonb,s jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if v->>'id' is null or (v->>'id')::uuid is null then raise exception 'Task ID required';end if;
 return jsonb_build_object('id',(v->>'id')::uuid::text,'title',private.require_text(v->>'title','Task title',300),
  'estimateMinutes',private.require_int(v->'estimateMinutes',1,14400,'Estimate'),'assignees',private.validate_assignees(w,v->'assignees'),
  'authorized',false,'authorization',null,'approvedCents',0,'done',false,'billableMinutes',0,
  'rateCents',(s->>'hourlyRateCents')::bigint,'taxBps',(s->>'taxBps')::int,'discountBps',0,'priceVersion',1,'internalCostCents',coalesce((s->>'internalHourlyCostCents')::bigint,0),'internalCostKnown',coalesce((s->>'internalCostKnown')::boolean,false),'scopeVersion',1,'block',null);
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
  if kind in ('receive','authorize','billable','pricing_review','review_parts','issue','deliver') and m->>'role'='technician' then raise exception 'Office permission required' using errcode='42501'; end if;
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
    if kind in ('authorize','billable','quality','pricing_review','review_parts','deliver','task_add','task_edit','task_cancel','task_reopen','task_block','task_unblock','order_plan','unblock','template_apply') and (op->>'baseRevision')::bigint is distinct from current_revision then raise exception 'Revision conflict; review latest order'; end if;
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
        if q is null or q<=0 or q>100000000 or p->>'kind' not in ('consume','reserve','customer') then raise exception 'Invalid part movement'; end if;
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
        t := t||jsonb_build_object('previousAuthorizations',coalesce(t->'previousAuthorizations','[]')||case when t->'authorization' is null or t->'authorization'='null' then '[]'::jsonb else jsonb_build_array(t->'authorization') end,'authorized',true,'approvedCents',amount,'authorization',p||jsonb_build_object('actorId',effective_actor,'at',at_time,'scopeVersion',coalesce((t->>'scopeVersion')::int,1),'priceVersion',coalesce((t->>'priceVersion')::int,1)));
        d := jsonb_set(d,array['tasks',task_index::text],t);
      when 'billable' then
        n := (p->>'minutes')::bigint;
        if n is null or n<0 or n>14400 or coalesce(trim(p->>'reason'),'')='' then raise exception 'Invalid billable minutes or missing reason'; end if;
        if n>0 and not(t->>'authorized')::boolean then raise exception 'Task authorization required'; end if;
        d := jsonb_set(d,array['tasks',task_index::text,'billableMinutes'],to_jsonb(n));
      when 'pricing_review' then
        d:=private.review_pricing(d,p,effective_actor,opid,at_time);
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
 if op->>'kind' in ('receive','authorize','billable','pricing_review','review_parts','issue','deliver') and m->>'role'='technician' then raise exception 'Office permission required' using errcode='42501'; end if;
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

create or replace function private.note_snapshot(d jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare t jsonb; p jsonb; l jsonb; lines jsonb:='[]'; gross bigint; discount bigint; discount_bps bigint; net bigint; tax bigint; q bigint; returned bigint; total_net bigint:=0; total_tax bigint:=0;
begin
 for t in select value from jsonb_array_elements(d->'tasks') loop
  if (t->>'billableMinutes')::bigint>0 then
   if not coalesce((t->>'authorized')::boolean,false) or coalesce((t->>'rateCents')::bigint,0)<=0 then raise exception 'Unauthorized or unpriced labor'; end if;
   gross:=((t->>'billableMinutes')::bigint*(t->>'rateCents')::bigint+30)/60;
   discount_bps:=coalesce((t->>'discountBps')::bigint,0);if discount_bps not between 0 and 10000 then raise exception 'Invalid labor discount';end if;
   discount:=(gross*discount_bps+5000)/10000;net:=gross-discount;
   tax:=(net*(t->>'taxBps')::bigint+5000)/10000;
   lines:=lines||jsonb_build_array(jsonb_build_object('taskId',t->>'id','description',t->>'title','quantity',(t->>'billableMinutes')||' min','unitPriceCents',t->'rateCents','taxBps',t->'taxBps','grossCents',gross,'discountBps',discount_bps,'discountCents',discount,'netCents',net,'taxCents',tax));
  end if;
 end loop;
 for p in select value from jsonb_array_elements(d->'parts') loop
  if p->>'kind'='consume' then
   if (p->>'priceCents')::bigint<0 then raise exception 'Missing price'; end if;
   if not coalesce((p->>'charge')::boolean,false) and coalesce(trim(p->>'noChargeReason'),'')='' then raise exception 'No-charge consumption requires reason';end if;
   if (p->>'charge')::boolean and not exists(select 1 from jsonb_array_elements(d->'tasks') x where x->>'id'=p->>'taskId' and (x->>'authorized')::boolean) then raise exception 'Unauthorized consumption'; end if;
   select coalesce(sum((x->>'quantityMilli')::bigint),0) into returned from jsonb_array_elements(d->'parts') x where x->>'kind'='return' and x->>'sourceId'=p->>'id';
   q:=(p->>'quantityMilli')::bigint-returned;
   if q<0 then raise exception 'Invalid return'; end if;
   if q>0 then
    gross:=(q*(p->>'priceCents')::bigint+500)/1000;
    discount_bps:=case when (p->>'charge')::boolean then coalesce((p->>'discountBps')::bigint,0) else 10000 end;
    if discount_bps not between 0 and 10000 then raise exception 'Invalid consumption discount';end if;
    discount:=(gross*discount_bps+5000)/10000;net:=gross-discount;tax:=(net*(p->>'taxBps')::bigint+5000)/10000;
    lines:=lines||jsonb_build_array(jsonb_build_object('taskId',p->>'taskId','description',p->>'description','quantity',replace(trim(trailing '.' from trim(trailing '0' from to_char(q::numeric/1000,'FM999999999990.000'))),'.',',')||' '||(p->>'unit'),'partId',p->>'id','unitPriceCents',p->'priceCents','taxBps',p->'taxBps','grossCents',gross,'discountBps',discount_bps,'discountCents',discount,'charge',p->'charge','noChargeReason',p->'noChargeReason','netCents',net,'taxCents',tax));
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
