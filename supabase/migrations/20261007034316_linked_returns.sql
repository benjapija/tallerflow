begin;
create function private.return_classification(p jsonb,actor uuid,at_time timestamptz) returns jsonb language plpgsql immutable set search_path='' as $$
begin
 if jsonb_typeof(p) is distinct from 'object' or exists(select 1 from jsonb_object_keys(p) k where not k=any(array['sourceOrderId','classification','reason'])) then raise exception 'Unsupported return classification';end if;
 if (p->>'sourceOrderId')::uuid is null or coalesce(p->>'classification','') not in ('warranty','recurrence','different') then raise exception 'Source order and classification required';end if;
 return jsonb_build_object('sourceOrderId',(p->>'sourceOrderId')::uuid,'classification',p->>'classification','reason',private.require_text(p->>'reason','Classification reason',2000),'actorId',actor,'at',at_time);
end $$;
alter function private.apply_record(uuid,uuid,jsonb,uuid) rename to apply_record_before_returns;
create function private.apply_record(w uuid,dev uuid,op jsonb,effective_actor uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare kind text:=op->>'kind';p jsonb:=op->'payload';oid uuid:=(op->>'orderId')::uuid;opid uuid:=(op->>'id')::uuid;at_time timestamptz:=(op->>'at')::timestamptz;r jsonb;d jsonb;original jsonb;link jsonb;before_doc jsonb;rev bigint;previous private.operations%rowtype;begin
 if kind='receive' and p ? 'returnLink' then
  r:=private.apply_record_before_returns(w,dev,op,effective_actor);
  if r->>'status'<>'accepted' then return r;end if;
  select data into d from private.orders where workshop_id=w and id=oid;
  if d ? 'returnHistory' then return r;end if;
  link:=private.return_classification(p->'returnLink',effective_actor,at_time);
  select data into original from private.orders where workshop_id=w and id=(link->>'sourceOrderId')::uuid;
  if original is null or original->>'id'=oid::text or original->>'vehicleId' is distinct from d->>'vehicleId' then raise exception 'Previous order for same vehicle required';end if;
  if (original->'document' is null or original->'document'='null') and coalesce(original->>'status','') not in ('finished','verified','delivered') then raise exception 'Original repair remains active';end if;
  update private.orders set data=d||jsonb_build_object('returnHistory',jsonb_build_array(link)) where workshop_id=w and id=oid;
  insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,after_data) values(w,effective_actor,opid,oid,'return_link',link);
  return r;
 elsif kind='return_classify' then
  if not exists(select 1 from private.members where workshop_id=w and user_id=effective_actor and active and role in ('office','admin')) or op->>'actorId' is distinct from effective_actor::text then raise exception 'Office permission required' using errcode='42501';end if;
  if opid is null or oid is null or at_time is null or at_time>now()+interval '2 minutes' then raise exception 'Invalid return operation';end if;
  perform 1 from private.workshops where id=w for update;
  select * into previous from private.operations where workshop_id=w and id=opid;
  if found then
   if previous.actor_id<>effective_actor or previous.device_id<>dev or previous.operation<>op then raise exception 'Idempotency key reused';end if;return jsonb_build_object('status',previous.status,'reason',previous.reason);
  end if;
  select data,revision into d,rev from private.orders where workshop_id=w and id=oid for update;
  if d is null or jsonb_array_length(coalesce(d->'returnHistory','[]'))=0 then raise exception 'Linked return required';end if;
  if d->'document' is not null and d->'document'<>'null' then raise exception 'Issued note remains immutable';end if;
  if (op->>'baseRevision')::bigint is distinct from rev then raise exception 'Revision conflict';end if;
  link:=private.return_classification(p,effective_actor,at_time);
  if link->>'sourceOrderId' is distinct from d->'returnHistory'->0->>'sourceOrderId' then raise exception 'Original link remains immutable';end if;
  before_doc:=d;d:=d||jsonb_build_object('returnHistory',d->'returnHistory'||jsonb_build_array(link));
  update private.orders set data=d,revision=rev+1 where workshop_id=w and id=oid;
  insert into private.operations values(w,opid,oid,effective_actor,dev,now(),op,'accepted',null);
  insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,before_data,after_data) values(w,effective_actor,opid,oid,kind,before_doc,d);
  return '{"status":"accepted","reason":null}';
 end if;
 return private.apply_record_before_returns(w,dev,op,effective_actor);
end $$;
alter function private.snapshot(uuid) rename to snapshot_before_returns;
create function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;r jsonb;rows jsonb;begin
 m:=private.membership(w);r:=private.snapshot_before_returns(w);
 if m->>'role'='technician' then
  select coalesce(jsonb_agg(o-'returnHistory'),'[]') into rows from jsonb_array_elements(r->'orders') o;r:=r||jsonb_build_object('orders',rows);
 end if;return r;
end $$;
revoke all on function private.return_classification(jsonb,uuid,timestamptz),private.apply_record_before_returns(uuid,uuid,jsonb,uuid),private.apply_record(uuid,uuid,jsonb,uuid),private.snapshot_before_returns(uuid),private.snapshot(uuid) from public,anon,authenticated;
grant execute on function private.snapshot(uuid) to authenticated;
commit;
