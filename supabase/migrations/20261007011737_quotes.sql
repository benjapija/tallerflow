begin;
create function private.quote_amount(row_data jsonb,quantity bigint,divisor bigint) returns jsonb language plpgsql immutable set search_path='' as $$
declare gross bigint;discount bigint;net bigint;tax bigint;begin
 gross:=(quantity*(row_data->>'unitPriceCents')::bigint+divisor/2)/divisor;
 discount:=(gross*(row_data->>'discountBps')::bigint+5000)/10000;net:=gross-discount;
 tax:=(net*(row_data->>'taxBps')::bigint+5000)/10000;
 return row_data||jsonb_build_object('grossCents',gross,'discountCents',discount,'netCents',net,'taxCents',tax,'totalCents',net+tax);
end $$;
create function private.prepare_quote(d jsonb,p jsonb,actor uuid,opid uuid,at_time timestamptz,rev bigint) returns jsonb language plpgsql immutable set search_path='' as $$
declare qid uuid;old jsonb;ledger jsonb;line jsonb;part jsonb;task jsonb;parts jsonb;components jsonb;lines jsonb:='[]';lineid uuid;tid uuid;seen text[]:='{}';tasks text[]:='{}';refs text[];minutes bigint;q bigint;net bigint;tax bigint;total bigint:=0;expiry timestamptz;next jsonb;
begin
 if jsonb_typeof(p) is distinct from 'object' or exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','expectedVersion','title','reason','validUntil','lines'])) then raise exception 'Unsupported quote fields';end if;
 qid:=(p->>'id')::uuid;if qid is null then raise exception 'Quote identity required';end if;
 ledger:=coalesce(d->'quoteLedger','{"versions":[],"decisions":[]}'::jsonb);
 select v into old from jsonb_array_elements(ledger->'versions') v where v->>'id'=qid::text order by (v->>'version')::bigint desc limit 1;
 if private.require_int(p->'expectedVersion',0,100000,'Quote version')<>coalesce((old->>'version')::bigint,0) then raise exception 'Review current quote version';end if;
 expiry:=(p->>'validUntil')::timestamptz;if expiry is null or expiry<=at_time then raise exception 'Quote expiry must be later';end if;
 if jsonb_typeof(p->'lines') is distinct from 'array' or jsonb_array_length(p->'lines') not between 1 and 50 then raise exception 'Quote requires 1 to 50 lines';end if;
 for line in select value from jsonb_array_elements(p->'lines') loop
  if jsonb_typeof(line) is distinct from 'object' or exists(select 1 from jsonb_object_keys(line) k where not k=any(array['id','taskId','description','laborMinutes','parts'])) then raise exception 'Unsupported quote line';end if;
  lineid:=(line->>'id')::uuid;tid:=(line->>'taskId')::uuid;
  if lineid is null or tid is null or lineid::text=any(seen) or tid::text=any(tasks) then raise exception 'Each line requires a distinct task and identity';end if;seen:=array_append(seen,lineid::text);tasks:=array_append(tasks,tid::text);
  select t into task from jsonb_array_elements(d->'tasks') t where t->>'id'=tid::text;
  if task is null or coalesce((task->>'cancelled')::boolean,false) then raise exception 'Current task required';end if;
  components:='[]';minutes:=private.require_int(line->'laborMinutes',0,14400,'Labor minutes');
  if minutes>0 then components:=components||jsonb_build_array(private.quote_amount(jsonb_build_object('kind','labor','description',task->'title','minutes',minutes,'unitPriceCents',private.require_int(task->'rateCents',0,10000000,'Rate'),'taxBps',private.require_int(task->'taxBps',0,10000,'Tax'),'discountBps',private.require_int(coalesce(task->'discountBps','0'),0,10000,'Discount')),minutes,60));end if;
  parts:=line->'parts';if jsonb_typeof(parts) is distinct from 'array' or jsonb_array_length(parts)>40 then raise exception 'Review quote parts';end if;refs:='{}';
  for part in select value from jsonb_array_elements(parts) loop
   if jsonb_typeof(part) is distinct from 'object' or exists(select 1 from jsonb_object_keys(part) k where not k=any(array['reference','description','unit','quantityMilli','unitPriceCents','taxBps','discountBps'])) then raise exception 'Unsupported quote part';end if;
   if private.require_text(part->>'reference','Reference',100)=any(refs) then raise exception 'Duplicate quote reference';end if;refs:=array_append(refs,trim(part->>'reference'));
   q:=private.require_int(part->'quantityMilli',1,100000000,'Quantity');
   components:=components||jsonb_build_array(private.quote_amount(jsonb_build_object('kind','part','reference',trim(part->>'reference'),'description',private.require_text(part->>'description','Description',300),'unit',private.require_text(part->>'unit','Unit',30),'quantityMilli',q,'unitPriceCents',private.require_int(part->'unitPriceCents',0,10000000,'Price'),'taxBps',private.require_int(part->'taxBps',0,10000,'Tax'),'discountBps',private.require_int(part->'discountBps',0,10000,'Discount')),q,1000));
  end loop;
  if jsonb_array_length(components)=0 then raise exception 'Labor or parts required';end if;
  select sum((c->>'netCents')::bigint),sum((c->>'taxCents')::bigint) into net,tax from jsonb_array_elements(components) c;total:=total+net+tax;
  lines:=lines||jsonb_build_array(jsonb_build_object('id',lineid,'taskId',tid,'description',private.require_text(line->>'description','Scope',1000),'scopeVersion',coalesce(task->'scopeVersion','1'),'priceVersion',coalesce(task->'priceVersion','1'),'components',components,'netCents',net,'taxCents',tax,'totalCents',net+tax));
 end loop;
 next:=jsonb_build_object('id',qid,'version',coalesce((old->>'version')::bigint,0)+1,'orderId',d->'id','orderRevision',rev,'title',private.require_text(p->>'title','Title',200),'reason',private.require_text(p->>'reason','Reason',2000),'validUntil',expiry,'at',at_time,'actorId',actor,'operationId',opid,'customer',d->'client','ownerId',d->'ownerId','lines',lines,'totalCents',total,'type','Presupuesto · no es una factura');
 return d||jsonb_build_object('quoteLedger',ledger||jsonb_build_object('versions',(ledger->'versions')||jsonb_build_array(next)));
end $$;
create function private.decide_quote(d jsonb,p jsonb,actor uuid,opid uuid,at_time timestamptz) returns jsonb language plpgsql immutable set search_path='' as $$
declare qid uuid;ledger jsonb;quote jsonb;decision jsonb;line jsonb;task jsonb;seen text[]:='{}';lineid uuid;tid uuid;idx int;amount bigint;performed bigint;results jsonb:='[]';record jsonb;customer text;evidence text;reason text;accepted boolean;
begin
 if jsonb_typeof(p) is distinct from 'object' or exists(select 1 from jsonb_object_keys(p) k where not k=any(array['quoteId','version','customer','channel','evidence','reason','decisions'])) then raise exception 'Unsupported decision fields';end if;
 qid:=(p->>'quoteId')::uuid;ledger:=coalesce(d->'quoteLedger','{"versions":[],"decisions":[]}'::jsonb);
 select v into quote from jsonb_array_elements(ledger->'versions') v where v->>'id'=qid::text order by (v->>'version')::bigint desc limit 1;
 if quote is null or private.require_int(p->'version',1,100000,'Version')<>(quote->>'version')::bigint then raise exception 'Decision refers to an older quote version';end if;
 if (quote->>'validUntil')::timestamptz<=at_time then raise exception 'Quote expired';end if;
 customer:=private.require_text(p->>'customer','Recipient',300);
 if customer is distinct from quote->>'customer' or customer is distinct from d->>'client' or quote->'ownerId' is distinct from d->'ownerId' then raise exception 'Review quote recipient';end if;
 if p->>'channel' is null or p->>'channel' not in ('telephone','in_person','email','written') then raise exception 'Decision channel required';end if;
 evidence:=private.require_text(p->>'evidence','Decision evidence',2000);reason:=private.require_text(p->>'reason','Decision reason',2000);
 if jsonb_typeof(p->'decisions') is distinct from 'array' or jsonb_array_length(p->'decisions') not between 1 and 50 then raise exception 'Decided lines required';end if;
 for decision in select value from jsonb_array_elements(p->'decisions') loop
  if jsonb_typeof(decision) is distinct from 'object' or exists(select 1 from jsonb_object_keys(decision) k where not k=any(array['lineId','accepted'])) or jsonb_typeof(decision->'accepted') is distinct from 'boolean' then raise exception 'Review line decision';end if;
  lineid:=(decision->>'lineId')::uuid;if lineid is null or lineid::text=any(seen) then raise exception 'Duplicate decision';end if;seen:=array_append(seen,lineid::text);
  select l into line from jsonb_array_elements(quote->'lines') l where l->>'id'=lineid::text;if line is null then raise exception 'Line not found';end if;
  tid:=(line->>'taskId')::uuid;
  select x.value,(x.ordinality-1)::int into task,idx from jsonb_array_elements(d->'tasks') with ordinality x where x.value->>'id'=tid::text;
  if task is null or coalesce((task->>'cancelled')::boolean,false) or coalesce(task->'scopeVersion','1')<>line->'scopeVersion' or coalesce(task->'priceVersion','1')<>line->'priceVersion' then raise exception 'Scope or price changed; prepare another version';end if;
  if exists(select 1 from jsonb_array_elements(ledger->'decisions') old cross join lateral jsonb_array_elements(old->'decisions') l where old->>'quoteId'=qid::text and old->'version'=quote->'version' and l->>'lineId'=lineid::text) then raise exception 'A line decision is immutable; prepare another version';end if;
  accepted:=(decision->>'accepted')::boolean;amount:=case when accepted then (line->>'totalCents')::bigint else 0 end;
  if accepted then
   -- note_snapshot validates current consumption and the previous authorization.
   -- Temporarily raise this task's cap to compare only actual performed amount.
   select coalesce(sum((l->>'netCents')::bigint+(l->>'taxCents')::bigint),0) into performed from jsonb_array_elements(private.note_snapshot(d||jsonb_build_object('tasks',jsonb_build_array(task||jsonb_build_object('authorized',true,'approvedCents',9223372036854775807)),'parts',(select coalesce(jsonb_agg(part),'[]') from jsonb_array_elements(d->'parts') part where part->>'taskId'=tid::text)))->'lines') l where l->>'taskId'=tid::text;
   if performed>amount then raise exception 'Authorization does not cover recorded work';end if;
   task:=task||jsonb_build_object('authorized',true,'approvedCents',amount,'previousAuthorizations',coalesce(task->'previousAuthorizations','[]')||case when task->'authorization' is null or task->'authorization'='null' then '[]'::jsonb else jsonb_build_array(task->'authorization') end,
    'authorization',jsonb_build_object('version',quote->'version','quoteId',qid,'lineId',lineid,'decisionId',opid,'customer',customer,'channel',p->'channel','evidence',evidence,'reason',reason,'actorId',actor,'at',at_time,'approvedCents',amount,'scopeVersion',coalesce(task->'scopeVersion','1'),'priceVersion',coalesce(task->'priceVersion','1')));
   d:=jsonb_set(d,array['tasks',idx::text],task)||jsonb_build_object('quality',null);
  end if;
  results:=results||jsonb_build_array(jsonb_build_object('lineId',lineid,'taskId',tid,'accepted',accepted,'approvedCents',amount));
 end loop;
 record:=jsonb_build_object('quoteId',qid,'version',quote->'version','id',opid,'customer',customer,'channel',p->'channel','evidence',evidence,'reason',reason,'actorId',actor,'at',at_time,'decisions',results);
 return d||jsonb_build_object('quoteLedger',ledger||jsonb_build_object('decisions',(ledger->'decisions')||jsonb_build_array(record)));
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
  if kind in ('receive','quote_draft','quote_decision','authorize','billable','pricing_review','review_parts','issue','deliver') and m->>'role'='technician' then raise exception 'Office permission required' using errcode='42501'; end if;
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
    if kind in ('quote_draft','quote_decision','authorize','billable','quality','inspection_save','pricing_review','review_parts','deliver','task_add','task_edit','task_cancel','task_reopen','task_block','task_unblock','order_plan','unblock','template_apply') and (op->>'baseRevision')::bigint is distinct from current_revision then raise exception 'Revision conflict; review latest order'; end if;
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
      when 'quote_draft' then
        d:=private.prepare_quote(d,p,effective_actor,opid,at_time,current_revision);
      when 'quote_decision' then
        d:=private.decide_quote(d,p,effective_actor,opid,at_time);
      when 'inspection_save' then
        d:=private.save_inspection(d,p,effective_actor,opid,at_time);
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


-- Customer decisions and personal quote documents are for office/admin only.
alter function private.snapshot(uuid) rename to snapshot_before_quotes;
create function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;r jsonb;rows jsonb;begin
 m:=private.membership(w);r:=private.snapshot_before_quotes(w);
 if m->>'role'='technician' then
  select coalesce(jsonb_agg(o-'quoteLedger'),'[]') into rows from jsonb_array_elements(r->'orders') o;
  r:=r||jsonb_build_object('orders',rows);
 end if;
 return r;
end $$;
revoke all on function private.snapshot_before_quotes(uuid),private.snapshot(uuid) from public,anon,authenticated;
grant execute on function private.snapshot(uuid) to authenticated;
revoke all on function private.quote_amount(jsonb,bigint,bigint),private.prepare_quote(jsonb,jsonb,uuid,uuid,timestamptz,bigint),private.decide_quote(jsonb,jsonb,uuid,uuid,timestamptz) from public,anon,authenticated;
commit;
