-- Administration stays behind authenticated, audited, idempotent commands.
begin;
create table private.member_permissions (
 workshop_id uuid not null, user_id uuid not null, see_costs boolean not null default false,
 primary key(workshop_id,user_id),foreign key(workshop_id,user_id) references private.members(workshop_id,user_id)
);
create table private.catalog_details (
 workshop_id uuid not null, item_id uuid not null, tax_bps int check(tax_bps between 0 and 10000),
 active boolean not null default true, cost_known boolean not null default false, supplier text not null default '',
 primary key(workshop_id,item_id),foreign key(workshop_id,item_id) references private.catalog(workshop_id,id)
);
create table private.templates (
 workshop_id uuid not null references private.workshops(id),id uuid not null,version int not null,data jsonb not null,
 primary key(workshop_id,id)
);
create table private.management_state (
 workshop_id uuid primary key references private.workshops(id),revision bigint not null default 0
);
do $$ declare t text;begin
 foreach t in array array['member_permissions','catalog_details','templates','management_state'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;
end $$;
create function private.require_int(v jsonb,lo bigint,hi bigint,label text) returns bigint language plpgsql immutable set search_path='' as $$
declare n bigint;begin
 if jsonb_typeof(v) is distinct from 'number' or v::text !~ '^-?[0-9]+$' then raise exception '% must be an integer',label;end if;
 n:=v::text::bigint;if n<lo or n>hi then raise exception '% out of range',label;end if;return n;
end $$;
create function private.require_text(v text,label text,maximum int default 2000) returns text language plpgsql immutable set search_path='' as $$
begin if v is null or length(trim(v))=0 or length(v)>maximum then raise exception '% required',label;end if;return trim(v);end $$;
create or replace function private.membership(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m private.members%rowtype;begin
 perform private.auth_session();select * into m from private.members where workshop_id=w and user_id=auth.uid() and active;
 if not found then raise exception 'Membership required' using errcode='42501';end if;
 return jsonb_build_object('id',m.user_id,'name',m.display_name,'role',m.role,'seePrices',m.see_prices,'active',m.active,
 'seeCosts',m.role='admin' or coalesce((select see_costs from private.member_permissions where workshop_id=w and user_id=m.user_id),false));
end $$;
create function private.management_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb;previous private.command_receipts%rowtype;rev bigint;v jsonb;t jsonb;r jsonb;result jsonb;before_value jsonb;selected_item uuid;uid uuid;available bigint;used bigint;newversion int;
begin
 m:=private.membership(w);
 if m->>'role'<>'admin' then raise exception 'Administrator required' using errcode='42501';end if;
 perform private.backup_admin(w,dev);perform 1 from private.workshops where id=w for update;
 if cid is null or jsonb_typeof(p) is distinct from 'object' then raise exception 'Command ID and payload required';end if;
 select * into previous from private.command_receipts where workshop_id=w and id=cid;
 if found then
  if previous.actor_id<>auth.uid() or previous.device_id<>dev or previous.action<>action or previous.payload<>p then raise exception 'Command ID reused';end if;
  return previous.result;
 end if;
 select revision into rev from private.management_state where workshop_id=w;
 rev:=coalesce(rev,0);
 if private.require_int(p->'revision',0,9007199254740991,'Revision')<>rev then raise exception 'Configuration revision conflict; refresh and review';end if;
 perform private.require_text(p->>'reason','Reason');
 case action
 when 'settings_save' then
  select settings into before_value from private.workshops where id=w;
  v:=jsonb_build_object('hourlyRateCents',private.require_int(p->'settings'->'hourlyRateCents',0,10000000,'Hourly rate'),
   'taxBps',private.require_int(p->'settings'->'taxBps',0,10000,'Tax'),
   'internalHourlyCostCents',private.require_int(p->'settings'->'internalHourlyCostCents',0,10000000,'Internal hourly cost'));
  if jsonb_typeof(p->'settings'->'internalCostKnown') is distinct from 'boolean' then raise exception 'Cost known flag required';end if;
  v:=before_value||v||jsonb_build_object('internalCostKnown',p->'settings'->'internalCostKnown');
  update private.workshops set settings=v where id=w;
 when 'member_save' then
  uid:=(p->>'userId')::uuid;
  select to_jsonb(x) into before_value from private.members x where workshop_id=w and user_id=uid;
  if before_value is null then raise exception 'Account must already belong to workshop';end if;
  if p->>'role' is null or p->>'role' not in ('technician','office','admin') or
   jsonb_typeof(p->'active') is distinct from 'boolean' or jsonb_typeof(p->'seePrices') is distinct from 'boolean' or jsonb_typeof(p->'seeCosts') is distinct from 'boolean' then raise exception 'Invalid permissions';end if;
  if before_value->>'role'='admin' and (p->>'role'<>'admin' or not(p->>'active')::boolean) and
   (select count(*) from private.members where workshop_id=w and active and role='admin')<=1 then raise exception 'Keep an active administrator';end if;
  if not(p->>'active')::boolean and exists(select 1 from private.time_sessions where workshop_id=w and actor_id=uid and ended_at is null) then raise exception 'Stop or recover account timers first';end if;
  if (p->>'seeCosts')::boolean and p->>'role'='technician' and not(p->>'seePrices')::boolean then raise exception 'Cost access requires price access';end if;
  update private.members set display_name=private.require_text(p->>'name','Name',120),role=p->>'role',see_prices=(p->>'seePrices')::boolean,active=(p->>'active')::boolean where workshop_id=w and user_id=uid;
  insert into private.member_permissions values(w,uid,(p->>'seeCosts')::boolean) on conflict(workshop_id,user_id) do update set see_costs=excluded.see_costs;
  v:=p;
 when 'catalog_save' then
  v:=p->'item';selected_item:=(v->>'id')::uuid;if selected_item is null then raise exception 'Item ID required';end if;
  select to_jsonb(x) into before_value from private.catalog x where workshop_id=w and id=selected_item;
  if exists(select 1 from private.catalog where workshop_id=w and id<>selected_item and upper(reference)=upper(private.require_text(v->>'reference','Reference',120))) then raise exception 'Duplicate reference';end if;
  available:=private.require_int(v->'stockMilli',0,100000000,'Stock');
  select coalesce(sum(case when z->>'kind'='consume' then (z->>'quantityMilli')::bigint when z->>'kind'='return' then -(z->>'quantityMilli')::bigint else 0 end),0) into used
   from private.orders o cross join lateral jsonb_array_elements(o.data->'parts') z where o.workshop_id=w and z->>'itemId'=selected_item::text;
  if jsonb_typeof(v->'active') is distinct from 'boolean' or jsonb_typeof(v->'costKnown') is distinct from 'boolean' then raise exception 'Item flags required';end if;
  insert into private.catalog(workshop_id,id,reference,description,unit,price_cents,cost_cents,stock_milli,min_milli)
  values(w,selected_item,private.require_text(v->>'reference','Reference',120),private.require_text(v->>'description','Description',300),private.require_text(v->>'unit','Unit',20),
   private.require_int(v->'priceCents',0,10000000,'Price'),private.require_int(v->'costCents',0,10000000,'Cost'),available+used,private.require_int(v->'minMilli',0,100000000,'Minimum'))
  on conflict(workshop_id,id) do update set reference=excluded.reference,description=excluded.description,unit=excluded.unit,price_cents=excluded.price_cents,cost_cents=excluded.cost_cents,stock_milli=excluded.stock_milli,min_milli=excluded.min_milli;
  insert into private.catalog_details values(w,selected_item,private.require_int(v->'taxBps',0,10000,'Tax')::int,(v->>'active')::boolean,(v->>'costKnown')::boolean,coalesce(v->>'supplier',''))
  on conflict(workshop_id,item_id) do update set tax_bps=excluded.tax_bps,active=excluded.active,cost_known=excluded.cost_known,supplier=excluded.supplier;
 when 'template_save' then
  v:=p->'template';selected_item:=(v->>'id')::uuid;
  if selected_item is null or jsonb_typeof(v->'tasks') is distinct from 'array' or jsonb_array_length(v->'tasks') not between 1 and 40 then raise exception 'Template needs 1 to 40 tasks';end if;
  perform private.require_text(v->>'name','Template name',120);
  if jsonb_typeof(v->'active') is distinct from 'boolean' then raise exception 'Template active flag required';end if;
  for t in select value from jsonb_array_elements(v->'tasks') loop
   perform private.require_text(t->>'title','Task title',300);perform private.require_int(t->'estimateMinutes',1,14400,'Estimate');
   if jsonb_typeof(t->'references') is distinct from 'array' then raise exception 'References array required';end if;
   for r in select value from jsonb_array_elements(t->'references') loop
    if not exists(select 1 from private.catalog c left join private.catalog_details cd on cd.workshop_id=c.workshop_id and cd.item_id=c.id where c.workshop_id=w and c.id=(r->>'itemId')::uuid and coalesce(cd.active,true)) then raise exception 'Template reference unavailable';end if;
    perform private.require_int(r->'quantityMilli',1,10000000,'Reference quantity');
   end loop;
  end loop;
  select data,version+1 into before_value,newversion from private.templates where workshop_id=w and id=selected_item;
  newversion:=coalesce(newversion,1);v:=v||jsonb_build_object('version',newversion);
  insert into private.templates values(w,selected_item,newversion,v) on conflict(workshop_id,id) do update set version=excluded.version,data=excluded.data;
 else raise exception 'Unknown management action';
 end case;
 insert into private.management_state values(w,rev+1) on conflict(workshop_id) do update set revision=excluded.revision;
 -- Membership changes can alter the set of participants required at closure.
 update private.close_requests set status='invalidated' where workshop_id=w and status='active';
 insert into private.audit(workshop_id,actor_id,operation_id,kind,before_data,after_data) values(w,auth.uid(),cid,action,before_value,jsonb_build_object('value',v,'reason',p->>'reason','revision',rev+1));
 result:=jsonb_build_object('saved',true,'revision',rev+1);
 insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,result);
 return result;
end $$;
create function public.management_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.management_command($1,$2,$3,$4,$5) $$;
revoke all on function private.require_int(jsonb,bigint,bigint,text),private.require_text(text,text,int),private.management_command(uuid,uuid,uuid,text,jsonb),public.management_command(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.management_command(uuid,uuid,uuid,text,jsonb),public.management_command(uuid,uuid,uuid,text,jsonb) to authenticated;
create function private.validate_assignees(w uuid,v jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if jsonb_typeof(v) is distinct from 'array' or jsonb_array_length(v) not between 1 and 20 then raise exception 'Select active workshop assignees';end if;
 if (select count(distinct x) from jsonb_array_elements_text(v) x)<>jsonb_array_length(v) or
 exists(select 1 from jsonb_array_elements_text(v) x where not exists(select 1 from private.members where workshop_id=w and user_id::text=x and active)) then raise exception 'Assignee outside active workshop';end if;
 return v;
end $$;
create function private.new_task(w uuid,v jsonb,s jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if v->>'id' is null or (v->>'id')::uuid is null then raise exception 'Task ID required';end if;
 return jsonb_build_object('id',v->>'id','title',private.require_text(v->>'title','Task title',300),
  'estimateMinutes',private.require_int(v->'estimateMinutes',1,14400,'Estimate'),'assignees',private.validate_assignees(w,v->'assignees'),
  'authorized',false,'authorization',null,'approvedCents',0,'done',false,'billableMinutes',0,
  'rateCents',(s->>'hourlyRateCents')::bigint,'taxBps',(s->>'taxBps')::int,'scopeVersion',1,'block',null);
end $$;
create function private.task_change(w uuid,d jsonb,kind text,p jsonb,actor uuid,at_time timestamptz,s jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare t jsonb;idx int;newtitle text;newtask jsonb;template private.templates%rowtype;source jsonb;taskid text;pos int:=0;role_name text;
begin
 select role into role_name from private.members where workshop_id=w and user_id=actor and active;
 if role_name is null or (role_name='technician' and kind not in ('task_block','task_unblock')) then raise exception 'Office permission required';end if;
 perform private.require_text(p->>'reason','Reason');
 if kind in ('task_edit','task_cancel','task_reopen','task_block','task_unblock') then
  select x.value,(x.ordinality-1)::int into t,idx from jsonb_array_elements(d->'tasks') with ordinality x where x.value->>'id'=p->>'taskId';
  if t is null then raise exception 'Task not found';end if;
  if role_name='technician' and not(t->'assignees' ? actor::text) then raise exception 'Task not assigned';end if;
  if kind<>'task_unblock' and exists(select 1 from private.time_sessions where workshop_id=w and order_id=(d->>'id')::uuid and task_id=(t->>'id')::uuid and ended_at is null) then raise exception 'Stop all task timers first';end if;
 end if;
 case kind
 when 'task_add' then
  newtask:=private.new_task(w,p->'task',s);
  if exists(select 1 from jsonb_array_elements(d->'tasks') x where x->>'id'=newtask->>'id') then raise exception 'Duplicate task';end if;
  d:=jsonb_set(d,'{tasks}',d->'tasks'||jsonb_build_array(newtask));
 when 'task_edit' then
  if coalesce((t->>'cancelled')::boolean,false) then raise exception 'Task cancelled';end if;
  newtitle:=private.require_text(p->>'title','Task title',300);
  if newtitle<>t->>'title' then
   t:=t||jsonb_build_object('previousAuthorizations',coalesce(t->'previousAuthorizations','[]')||case when t->'authorization' is null or t->'authorization'='null' then '[]'::jsonb else jsonb_build_array(t->'authorization') end,
    'authorized',false,'approvedCents',0,'authorization',null,'scopeVersion',coalesce((t->>'scopeVersion')::int,1)+1);
  end if;
  t:=t||jsonb_build_object('title',newtitle,'assignees',private.validate_assignees(w,p->'assignees'),'estimateMinutes',private.require_int(p->'estimateMinutes',1,14400,'Estimate'));
 when 'task_cancel' then
  if exists(select 1 from jsonb_array_elements(d->'times') x where x->>'taskId'=t->>'id') or
   exists(select 1 from jsonb_array_elements(d->'parts') x where x->>'taskId'=t->>'id') or coalesce((t->>'billableMinutes')::bigint,0)<>0 then raise exception 'Keep tasks with recorded work; review charges';end if;
  t:=t||jsonb_build_object('previousAuthorizations',coalesce(t->'previousAuthorizations','[]')||case when t->'authorization' is null or t->'authorization'='null' then '[]'::jsonb else jsonb_build_array(t->'authorization') end,
   'cancelled',true,'authorized',false,'authorization',null,'approvedCents',0,'block',null,'cancellationReason',p->>'reason');
 when 'task_reopen' then
  if coalesce((t->>'cancelled')::boolean,false) or coalesce((t->>'done')::boolean,false)=false then raise exception 'Completed task required';end if;
  t:=t||'{"done":false}';d:=d||'{"status":"repair"}';
 when 'task_block' then
  if coalesce((t->>'done')::boolean,false) or coalesce((t->>'cancelled')::boolean,false) then raise exception 'Task does not allow a block';end if;
  perform private.require_text(p->>'nextAction','Next action');
  if not exists(select 1 from private.members where workshop_id=w and user_id::text=p->>'ownerId' and active) then raise exception 'Active responsible member required';end if;
  t:=t||jsonb_build_object('block',jsonb_build_object('reason',p->>'reason','nextAction',p->>'nextAction','ownerId',p->>'ownerId','actorId',actor,'at',at_time));
 when 'task_unblock' then
  if t->'block' is null or t->'block'='null' then raise exception 'Task is not blocked';end if;t:=t||'{"block":null}';
 when 'unblock' then
  if d->'block' is null or d->'block'='null' then raise exception 'Order is not blocked';end if;
  d:=d||'{"block":null,"nextAction":null,"status":"pending"}';
 when 'order_plan' then
  if p->>'priority' is null or p->>'priority' not in ('Normal','Alta','Urgente') then raise exception 'Invalid priority';end if;
  d:=d||jsonb_build_object('priority',p->>'priority','due',private.require_text(p->>'due','Due',300),
   'location',private.require_text(p->>'location','Location',300),'keys',private.require_text(p->>'keys','Keys',300));
 when 'template_apply' then
  if p->>'compatibilityChecked' is distinct from 'true' then raise exception 'Confirm compatibility for this vehicle';end if;
  select * into template from private.templates where workshop_id=w and id=(p->>'templateId')::uuid;
  if not found or template.data->>'active'='false' or template.version is distinct from (p->>'templateVersion')::int then raise exception 'Template unavailable or changed';end if;
  if jsonb_typeof(p->'taskIds') is distinct from 'array' or jsonb_array_length(p->'taskIds')<>jsonb_array_length(template.data->'tasks') then raise exception 'Template task IDs required';end if;
  for source in select value from jsonb_array_elements(template.data->'tasks') loop
   taskid:=p->'taskIds'->>pos;pos:=pos+1;
   newtask:=private.new_task(w,source||jsonb_build_object('id',taskid,'assignees',p->'assignees'),s)||
    jsonb_build_object('templateId',template.id,'templateVersion',template.version,'compatibilityChecked',true,'suggestedReferences',coalesce(source->'references','[]'));
   if exists(select 1 from jsonb_array_elements(d->'tasks') x where x->>'id'=taskid) then raise exception 'Duplicate template task';end if;
   d:=jsonb_set(d,'{tasks}',d->'tasks'||jsonb_build_array(newtask));
  end loop;
 else raise exception 'Unknown task action';
 end case;
 if idx is not null then d:=jsonb_set(d,array['tasks',idx::text],t);end if;
 if kind in ('task_add','task_edit','task_cancel','task_reopen','template_apply') then d:=jsonb_set(d,'{quality}','null');end if;
 return d;
end $$;
revoke all on function private.validate_assignees(uuid,jsonb),private.new_task(uuid,jsonb,jsonb),private.task_change(uuid,jsonb,text,jsonb,uuid,timestamptz,jsonb) from public,anon,authenticated;

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
        select jsonb_agg(private.new_task(w,z,settings)) into entry from jsonb_array_elements(p->'tasks') z;
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


create or replace function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb; orders_json jsonb; catalog_json jsonb; audit_json jsonb; incidents_json jsonb; show_prices boolean; show_costs boolean; settings_json jsonb;
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
  return jsonb_build_object('workshopId',w,'orders',orders_json,'catalog',catalog_json,'members',(select coalesce(jsonb_agg(jsonb_build_object('id',user_id,'name',display_name,'role',role,'seePrices',see_prices,'seeCosts',coalesce((select see_costs from private.member_permissions mp where mp.workshop_id=w and mp.user_id=private.members.user_id),false),'active',active)),'[]') from private.members where workshop_id=w and (active or m->>'role'='admin')),'audit',audit_json,'applied','[]'::jsonb,'incidents',incidents_json,'settings',settings_json,'managementRevision',coalesce((select revision from private.management_state where workshop_id=w),0),
 'templates',case when m->>'role'='technician' then '[]'::jsonb else (select coalesce(jsonb_agg(data),'[]') from private.templates where workshop_id=w) end);
end $$;


create or replace function private.backup_tables() returns text[] language sql immutable set search_path='' as $$
 select array['members','member_permissions','vehicles','catalog','catalog_details','templates','management_state','devices','device_sessions','orders','operations','time_sessions',
 'close_requests','order_devices','close_acknowledgements','resolutions','command_receipts','documents','audit']::text[]
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
 return jsonb_build_object('serverFormat',1,'databaseVersion',3,'workshopId',w,
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
 if a->>'serverFormat' is distinct from '1' or coalesce(a->>'databaseVersion','') not in ('2','3') or a->>'workshopId' is distinct from w::text
  or a->'workshop'->>'id' is distinct from w::text or a->>'authExcluded' is distinct from 'true' then raise exception 'Incompatible workshop archive'; end if;
 tables:=a->'tables';
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

create or replace function private.redact_prices(value jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb; k text; v jsonb;
begin
  if jsonb_typeof(value)='array' then
    select coalesce(jsonb_agg(private.redact_prices(x)),'[]') into result from jsonb_array_elements(value) x;
    return result;
  elsif jsonb_typeof(value)='object' then
    result := '{}';
    for k,v in select * from jsonb_each(value) loop
      if k not in ('priceCents','costCents','rateCents','approvedCents','netCents','taxCents','totalCents','document','authorization','hourlyRateCents','internalHourlyCostCents') then
        result := result || jsonb_build_object(k,private.redact_prices(v));
      end if;
    end loop;
    return result;
  end if;
  return value;
end $$;


create or replace function private.reliability_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
  if (d->'block' is not null and d->'block'<>'null') or exists(select 1 from jsonb_array_elements(d->'tasks') x where x->'block' is not null and x->'block'<>'null' and coalesce((x->>'cancelled')::boolean,false)=false) then raise exception 'Resolve work blocks before issuing';end if;
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


commit;
