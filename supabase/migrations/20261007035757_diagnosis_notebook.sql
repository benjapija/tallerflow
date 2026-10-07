begin;
create function private.diagnosis_entry(d jsonb,p jsonb,kind text,actor uuid,actor_name text,actor_role text,opid uuid,at_time timestamptz,revision bigint,base_revision bigint) returns jsonb language plpgsql immutable set search_path='' as $$
declare rows jsonb:=coalesce(d->'diagnosisNotebook','[]');entry jsonb;source jsonb;sourceid uuid;stage text;confirmed boolean;key text;begin
 if jsonb_typeof(p) is distinct from 'object' then raise exception 'Diagnosis object required';end if;
 if kind='diagnosis_withdraw' then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['sourceId','reason'])) then raise exception 'Unsupported withdrawal fields';end if;sourceid:=(p->>'sourceId')::uuid;
 else
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['stage','text','context','dtcs','source','confirmed','replacesId','reason'])) then raise exception 'Unsupported diagnosis fields';end if;sourceid:=(p->>'replacesId')::uuid;
 end if;
 if kind='diagnosis_withdraw' or sourceid is not null then
  if base_revision is distinct from revision then raise exception 'Notebook revision conflict';end if;
  select x into source from jsonb_array_elements(rows) x where x->>'id'=sourceid::text and x->>'stage'<>'withdrawal';
  if source is null or exists(select 1 from jsonb_array_elements(rows) x where x->>'replacesId'=sourceid::text or x->>'withdrawsId'=sourceid::text) then raise exception 'Current entry in same notebook required';end if;
  if actor_role='technician' and source->>'actorId'<>actor::text then raise exception 'Office required to review another technician entry';end if;
 end if;
 if kind='diagnosis_withdraw' then entry:=jsonb_build_object('stage','withdrawal','withdrawsId',sourceid,'reason',private.require_text(p->>'reason','Withdrawal reason',2000));
 else
  stage:=p->>'stage';if stage is null or stage not in ('symptom','hypothesis','test','result','conclusion','intervention','verification') then raise exception 'Diagnosis stage required';end if;
  if jsonb_typeof(p->'confirmed') is distinct from 'boolean' then raise exception 'Explicit human confirmation required';end if;confirmed:=(p->>'confirmed')::boolean;
  if stage in ('conclusion','verification') and not confirmed then raise exception 'Personally confirm conclusion or verification';end if;
  foreach key in array array['context','dtcs','source'] loop
   if p ? key and jsonb_typeof(p->key) is distinct from 'string' then raise exception 'Technical text required';end if;
  end loop;
  if length(coalesce(p->>'context',''))>2000 or length(coalesce(p->>'source',''))>2000 or length(coalesce(p->>'dtcs',''))>500 then raise exception 'Technical text too long';end if;
  entry:=jsonb_build_object('stage',stage,'text',private.require_text(p->>'text','Observation',4000),'context',trim(coalesce(p->>'context','')),'dtcs',trim(coalesce(p->>'dtcs','')),'source',trim(coalesce(p->>'source','')),'confirmed',confirmed);
  if sourceid is not null then entry:=entry||jsonb_build_object('replacesId',sourceid,'reason',private.require_text(p->>'reason','Review reason',2000));elsif p ? 'reason' then raise exception 'Review reason requires previous entry';end if;
 end if;
 entry:=entry||jsonb_build_object('id',opid,'actorId',actor,'actorName',actor_name,'actorRole',actor_role,'at',at_time);
 return d||jsonb_build_object('diagnosisNotebook',rows||jsonb_build_array(entry),'quality',null);
end $$;
alter function private.apply_record(uuid,uuid,jsonb,uuid) rename to apply_record_before_notebook;
create function private.apply_record(w uuid,dev uuid,op jsonb,effective_actor uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare kind text:=op->>'kind';m private.members%rowtype;opid uuid;oid uuid;at_time timestamptz;d jsonb;before_doc jsonb;rev bigint;previous private.operations%rowtype;begin
 if kind not in ('diagnosis_add','diagnosis_withdraw') or kind is null then return private.apply_record_before_notebook(w,dev,op,effective_actor);end if;
 perform private.photo_device(w,dev);
 if not private.photo_files_ready(w) then raise exception 'Recover original files before new work';end if;
 select * into m from private.members where workshop_id=w and user_id=effective_actor and active;
 if not found or op->>'actorId' is distinct from effective_actor::text then raise exception 'Active membership required' using errcode='42501';end if;
 opid:=(op->>'id')::uuid;oid:=(op->>'orderId')::uuid;at_time:=(op->>'at')::timestamptz;
 if opid is null or oid is null or at_time is null or at_time>now()+interval '2 minutes' then raise exception 'Valid diagnosis identity and date required';end if;
 perform 1 from private.workshops where id=w for update;
 select * into previous from private.operations where workshop_id=w and id=opid;
 if found then
  if previous.actor_id<>effective_actor or previous.device_id<>dev or previous.operation<>op then raise exception 'Idempotency key reused';end if;return jsonb_build_object('status',previous.status,'reason',previous.reason);
 end if;
 select data,revision into d,rev from private.orders where workshop_id=w and id=oid for update;
 if d is null or (m.role='technician' and not exists(select 1 from jsonb_array_elements(d->'tasks') t where t->'assignees' ? effective_actor::text)) then raise exception 'Assigned order or office permission required' using errcode='42501';end if;
 before_doc:=d;d:=private.diagnosis_entry(d,op->'payload',kind,effective_actor,m.display_name,m.role,opid,at_time,rev,(op->>'baseRevision')::bigint);
 update private.orders set data=d,revision=rev+1 where workshop_id=w and id=oid;
 insert into private.operations values(w,opid,oid,effective_actor,dev,now(),op,'accepted',null);
 insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,before_data,after_data) values(w,effective_actor,opid,oid,kind,before_doc,d);
 return '{"status":"accepted","reason":null}';
end $$;
revoke all on function private.diagnosis_entry(jsonb,jsonb,text,uuid,text,text,uuid,timestamptz,bigint,bigint),private.apply_record_before_notebook(uuid,uuid,jsonb,uuid),private.apply_record(uuid,uuid,jsonb,uuid) from public,anon,authenticated;
commit;
