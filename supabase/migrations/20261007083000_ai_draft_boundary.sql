begin;
-- AI can read a minimal technical projection and reserve bounded consumption.
-- It has no operation that changes a repair, authorization or issued document.
create function private.ai_context(w uuid,dev uuid,oid uuid,mode text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare m jsonb;d jsonb;rev bigint;facts jsonb:='[]';cases jsonb:='[]';x jsonb;t jsonb;c jsonb;v jsonb;source jsonb;
begin
 m:=private.photo_device(w,dev);
 if mode is null or mode not in ('technical','office') or (mode='office' and m->>'role'='technician') then raise exception 'AI role required' using errcode='42501';end if;
 select data,revision into d,rev from private.orders where workshop_id=w and id=oid;
 if d is null or not private.photo_order_access(w,oid,auth.uid(),m->>'role' in ('office','admin')) then raise exception 'Assigned repair required' using errcode='42501';end if;
 if not private.photo_files_ready(w) then raise exception 'Recover original evidence first';end if;
 for x in select value from jsonb_array_elements(coalesce(d->'diagnosisNotebook','[]')) loop
  if x->>'stage'<>'withdrawal' and not exists(select 1 from jsonb_array_elements(coalesce(d->'diagnosisNotebook','[]')) y where y->>'replacesId'=x->>'id' or y->>'withdrawsId'=x->>'id') then
   facts:=facts||jsonb_build_array(jsonb_build_object('id','notebook:'|| (x->>'id'),'kind',x->'stage','text',x->'text','context',x->'context','dtcs',x->'dtcs','confirmed',x->'confirmed'));
  end if;
 end loop;
 if mode='office' then
  for x in select value from jsonb_array_elements(d->'notes') loop
   facts:=facts||jsonb_build_array(jsonb_build_object('id','note:'||(x->>'id'),'kind','recorded_note','text',x->'text'));
  end loop;
  for x in select value from jsonb_array_elements(d->'times') where value->>'end' is not null loop
   select value into t from jsonb_array_elements(d->'tasks') where value->>'id'=x->>'taskId';
   facts:=facts||jsonb_build_array(jsonb_build_object('id','time:'||(x->>'id'),'kind','recorded_time','text','Tiempo registrado en tarea: '||(t->>'title')));
  end loop;
  for x in select value from jsonb_array_elements(d->'parts') where value->>'kind' in ('consume','return') loop
   facts:=facts||jsonb_build_array(jsonb_build_object('id','part:'||(x->>'id'),'kind',case when x->>'kind'='return' then 'recorded_return' else 'recorded_consumption' end,'text',x->'description','quantityMilli',x->'quantityMilli','unit',x->'unit'));
  end loop;
 end if;
 if mode='technical' then
  for c in select data from private.case_library where workshop_id=w order by id loop
   select value into v from jsonb_array_elements(c->'versions') where value->>'version'=c->>'activeVersion';
   select data into source from private.orders where workshop_id=w and id=(c->>'sourceOrderId')::uuid;
   if v is not null and c->'withdrawn'='false'::jsonb and private.case_evidence(source,v) then
    cases:=cases||jsonb_build_array(jsonb_build_object('id','case:'||(c->>'id')||':'||(v->>'version'),'kind','validated_antecedent','content',v->'content'));
   end if;
  end loop;
 end if;
 return jsonb_build_object('userId',auth.uid(),'sessionId',private.auth_session(),'role',m->'role','revision',rev,'facts',facts,'cases',cases);
end $$;
create function public.ai_context(workshop_id uuid,device_id uuid,order_id uuid,mode text) returns jsonb
language sql stable security invoker set search_path='' as $$ select private.ai_context($1,$2,$3,$4) $$;


create function private.ai_receipt(w uuid,dev uuid,oid uuid,cid uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare m jsonb;r private.command_receipts%rowtype;
begin
 m:=private.photo_device(w,dev);
 if not private.photo_order_access(w,oid,auth.uid(),m->>'role' in ('office','admin')) then raise exception 'Assigned repair required' using errcode='42501';end if;
 select * into r from private.command_receipts where workshop_id=w and id=cid and action='ai_request' and actor_id=auth.uid() and device_id=dev and payload->>'orderId'=oid::text;
 if not found then return '{"state":"not_found"}';end if;
 if r.payload->>'mode'='office' and m->>'role'='technician' then raise exception 'AI role required' using errcode='42501';end if;
 return r.result;
end $$;
create function public.ai_receipt(workshop_id uuid,device_id uuid,order_id uuid,request_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$ select private.ai_receipt($1,$2,$3,$4) $$;

create function private.ai_reserve(w uuid,dev uuid,uid uuid,sid uuid,cid uuid,oid uuid,revision bigint,mode text,request_hash text,model text,reserve_micro bigint,limit_micro bigint,request_limit int) returns jsonb
language plpgsql security definer set search_path='' as $$
declare old private.command_receipts%rowtype;day text:=to_char(now() at time zone 'UTC','YYYY-MM-DD');p jsonb;spent bigint;n bigint;current_rev bigint;role text;
begin
 if cid is null or oid is null or request_hash is null or request_hash !~ '^[a-f0-9]{64}$' or model is null or length(model) not between 1 and 100 or mode is null or mode not in ('technical','office') or reserve_micro is null or reserve_micro<=0 or limit_micro is null or limit_micro not between 1 and 1000000 or reserve_micro>limit_micro or request_limit is null or request_limit not between 1 and 100 then raise exception 'Bounded server AI configuration required';end if;
 select m.role into role from private.members m join private.devices dv on dv.workshop_id=m.workshop_id and dv.user_id=m.user_id where m.workshop_id=w and m.user_id=uid and m.active and dv.id=dev and dv.retired_at is null and dv.auth_session_id=sid;
 if role is null or not exists(select 1 from auth.sessions where id=sid and user_id=uid) or (mode='office' and role='technician') then raise exception 'Active AI account and device required' using errcode='42501';end if;
 perform 1 from private.workshops where id=w for update;
 select o.revision into current_rev from private.orders o where o.workshop_id=w and o.id=oid and private.photo_order_access(w,oid,uid,role in ('office','admin'));
 if current_rev is null or current_rev<>revision then raise exception 'Review current repair context';end if;
 select * into old from private.command_receipts where workshop_id=w and id=cid;
 if found then
  if old.action is distinct from 'ai_request' or old.actor_id is distinct from uid or old.device_id is distinct from dev or old.payload->>'requestHash' is distinct from request_hash or old.payload->>'model' is distinct from model or old.payload->>'mode' is distinct from mode or old.payload->>'orderId' is distinct from oid::text or (old.payload->>'revision')::bigint is distinct from revision then raise exception 'AI request identity reused';end if;
  return jsonb_build_object('start',false,'receipt',old.result);
 end if;
 if exists(select 1 from private.command_receipts where workshop_id=w and action='ai_request' and result->'budgetOverrun'='true'::jsonb) then raise exception 'AI consumption requires administrator review';end if;
 select count(*),coalesce(sum(case when result->>'state'='completed' then (result->>'actualMicroUsd')::bigint else (payload->>'reservedMicroUsd')::bigint end),0) into n,spent from private.command_receipts where workshop_id=w and action='ai_request' and payload->>'day'=day;
 if n>=request_limit or spent+reserve_micro>limit_micro then raise exception 'AI daily limit reached';end if;
 p:=jsonb_build_object('requestHash',request_hash,'orderId',oid,'revision',revision,'mode',mode,'model',model,'reservedMicroUsd',reserve_micro,'day',day);
 insert into private.command_receipts values(w,cid,uid,dev,'ai_request',p,'{"state":"reserved"}');
 insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,after_data) values(w,uid,cid,oid,'ai_reserved',p);
 return '{"start":true}';
end $$;
create function public.ai_reserve(workshop_id uuid,device_id uuid,user_id uuid,session_id uuid,request_id uuid,order_id uuid,revision bigint,mode text,request_hash text,model text,reserve_micro bigint,limit_micro bigint,request_limit int) returns jsonb
language sql security invoker set search_path='' as $$ select private.ai_reserve($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) $$;

create function private.ai_finish(w uuid,cid uuid,request_hash text,result jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare old private.command_receipts%rowtype;charge bigint;begin
 perform 1 from private.workshops where id=w for update;
 select * into old from private.command_receipts where workshop_id=w and id=cid for update;
 if not found or old.action<>'ai_request' or old.payload->>'requestHash' is distinct from request_hash then raise exception 'Original AI reservation required';end if;
 if old.result->>'state'<>'reserved' then if old.result<>result then raise exception 'AI result already preserved';end if;return old.result;end if;
 if jsonb_typeof(result) is distinct from 'object' or length(result::text)>32000 or result->>'state' is null or result->>'state' not in ('completed','uncertain') then raise exception 'AI result must remain a draft';end if;
 if result->>'state'='completed' then
  charge:=private.require_int(result->'actualMicroUsd',0,1000000,'AI usage');
  if charge>(old.payload->>'reservedMicroUsd')::bigint or result->'reviewRequired' is distinct from 'true'::jsonb or jsonb_typeof(result->'draft') is distinct from 'object' then raise exception 'AI usage or human review invalid';end if;
 elsif result ? 'draft' then raise exception 'Uncertain response cannot become a draft';end if;
 update private.command_receipts set result=ai_finish.result where workshop_id=w and id=cid;
 insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,after_data) values(w,old.actor_id,cid,(old.payload->>'orderId')::uuid,'ai_'||(result->>'state'),result);
 return result;
end $$;
create function public.ai_finish(workshop_id uuid,request_id uuid,request_hash text,result jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select private.ai_finish($1,$2,$3,$4) $$;

revoke all on function private.ai_context(uuid,uuid,uuid,text),public.ai_context(uuid,uuid,uuid,text),private.ai_reserve(uuid,uuid,uuid,uuid,uuid,uuid,bigint,text,text,text,bigint,bigint,int),public.ai_reserve(uuid,uuid,uuid,uuid,uuid,uuid,bigint,text,text,text,bigint,bigint,int),private.ai_finish(uuid,uuid,text,jsonb),public.ai_finish(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.ai_context(uuid,uuid,uuid,text),public.ai_context(uuid,uuid,uuid,text) to authenticated;
grant execute on function private.ai_reserve(uuid,uuid,uuid,uuid,uuid,uuid,bigint,text,text,text,bigint,bigint,int),public.ai_reserve(uuid,uuid,uuid,uuid,uuid,uuid,bigint,text,text,text,bigint,bigint,int),private.ai_finish(uuid,uuid,text,jsonb),public.ai_finish(uuid,uuid,text,jsonb) to service_role;
revoke all on function private.ai_receipt(uuid,uuid,uuid,uuid),public.ai_receipt(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function private.ai_receipt(uuid,uuid,uuid,uuid),public.ai_receipt(uuid,uuid,uuid,uuid) to authenticated;
commit;
