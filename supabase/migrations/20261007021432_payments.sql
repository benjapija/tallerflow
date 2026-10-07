begin;
create function private.payment_balance(d jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare total bigint;received bigint:=0;refunded bigint:=0;row jsonb;amount bigint;paid bigint;begin
 total:=private.require_int(d->'document'->'totalCents',0,1000000000000,'Document total');
 for row in select value from jsonb_array_elements(coalesce(d->'payments','[]')) loop
  amount:=private.require_int(row->'amountCents',1,1000000000000,'Payment amount');
  if row->>'kind'='receipt' then received:=received+amount;
  elsif row->>'kind'='reversal' then refunded:=refunded+amount;
  else raise exception 'Invalid payment record';end if;
 end loop;
 paid:=received-refunded;if paid<0 or paid>total then raise exception 'Review payment balance';end if;
 return jsonb_build_object('totalCents',total,'receivedCents',received,'refundedCents',refunded,'paidCents',paid,'outstandingCents',total-paid,'status',case when total=paid then 'paid' when paid=0 then 'pending' else 'partial' end);
end $$;
create function private.record_payment(d jsonb,p jsonb,kind text,actor uuid,opid uuid,at_time timestamptz) returns jsonb language plpgsql immutable set search_path='' as $$
declare balance jsonb;amount bigint;paid_at timestamptz;reference text;reason text;source jsonb;sourceid uuid;method text;refunded bigint;record jsonb;begin
 if d->'document' is null or d->'document'='null' then raise exception 'Issue work note before recording a payment';end if;
 if jsonb_typeof(p) is distinct from 'object' then raise exception 'Payment object required';end if;
 if kind='payment_record' then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['amountCents','paidAt','reference','reason','method'])) then raise exception 'Unsupported payment fields';end if;
 elsif kind='payment_reverse' then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['amountCents','paidAt','reference','reason','sourceId'])) then raise exception 'Unsupported reversal fields';end if;
 else raise exception 'Unsupported payment operation';end if;
 balance:=private.payment_balance(d);amount:=private.require_int(p->'amountCents',1,1000000000000,'Amount');
 reference:=private.require_text(p->>'reference','Reference',300);reason:=private.require_text(p->>'reason','Reason',2000);paid_at:=(p->>'paidAt')::timestamptz;
 if paid_at is null or paid_at>at_time or (d->'document'->>'issuedAt') is null or paid_at<(d->'document'->>'issuedAt')::timestamptz then raise exception 'Actual payment date must follow document issuance';end if;
 if kind='payment_record' then
  method:=p->>'method';if method is null or method not in ('cash','card','transfer','other') then raise exception 'Payment method required';end if;
  if amount>(balance->>'outstandingCents')::bigint then raise exception 'Payment exceeds outstanding balance';end if;
 else
  sourceid:=(p->>'sourceId')::uuid;
  select r into source from jsonb_array_elements(coalesce(d->'payments','[]')) r where r->>'id'=sourceid::text and r->>'kind'='receipt';
  if source is null then raise exception 'Original receipt required';end if;
  select coalesce(sum((r->>'amountCents')::bigint),0) into refunded from jsonb_array_elements(d->'payments') r where r->>'kind'='reversal' and r->>'sourceId'=sourceid::text;
  if amount>(source->>'amountCents')::bigint-refunded then raise exception 'Reversal exceeds available receipt';end if;
  if paid_at<(source->>'paidAt')::timestamptz then raise exception 'Reversal predates receipt';end if;method:=source->>'method';
 end if;
 record:=jsonb_build_object('id',opid,'kind',case when kind='payment_reverse' then 'reversal' else 'receipt' end,'amountCents',amount,'currency','EUR','paidAt',paid_at,'method',method,'reference',reference,'reason',reason,'actorId',actor,'orderId',d->'id','at',at_time,'documentRevision',d->'document'->'revision','ownerId',d->'ownerId');
 record:=record-'at'||jsonb_build_object('recordedAt',at_time);if sourceid is not null then record:=record||jsonb_build_object('sourceId',sourceid);end if;
 return d||jsonb_build_object('payments',coalesce(d->'payments','[]')||jsonb_build_array(record));
end $$;
alter function private.apply_record(uuid,uuid,jsonb,uuid) rename to apply_record_before_payments;
create function private.apply_record(w uuid,dev uuid,op jsonb,effective_actor uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare kind text:=op->>'kind';opid uuid;oid uuid;at_time timestamptz;d jsonb;before_doc jsonb;rev bigint;role text;previous private.operations%rowtype;balance jsonb;reason text;begin
 if kind not in ('payment_record','payment_reverse','deliver') or kind is null then return private.apply_record_before_payments(w,dev,op,effective_actor);end if;
 select m.role into role from private.members m where m.workshop_id=w and m.user_id=effective_actor and m.active;
 if role is null or role not in ('admin','office') or op->>'actorId' is distinct from effective_actor::text then raise exception 'Office permission required' using errcode='42501';end if;
 opid:=(op->>'id')::uuid;oid:=(op->>'orderId')::uuid;at_time:=(op->>'at')::timestamptz;
 if opid is null or oid is null or at_time is null or at_time>now()+interval '2 minutes' then raise exception 'Invalid payment operation';end if;
 perform pg_advisory_xact_lock(hashtextextended(effective_actor::text,0));perform 1 from private.workshops where id=w for update;
 select * into previous from private.operations where workshop_id=w and id=opid;
 if found then
  if previous.actor_id<>effective_actor or previous.device_id<>dev or previous.operation<>op then raise exception 'Idempotency key reused with different data';end if;
  return jsonb_build_object('status',previous.status,'reason',previous.reason);
 end if;
 if not exists(select 1 from private.devices where workshop_id=w and id=dev and user_id=effective_actor) then raise exception 'Device belongs to another user' using errcode='42501';end if;
 select data,revision into d,rev from private.orders where workshop_id=w and id=oid for update;
 if d is null or d->'document' is null or d->'document'='null' then raise exception 'Issued note required';end if;
 if (op->>'baseRevision')::bigint is distinct from rev then raise exception 'Balance changed; review latest order';end if;before_doc:=d;
 if kind='deliver' then
  if d->>'status'='delivered' then raise exception 'Original delivery is preserved';end if;
  if jsonb_typeof(op->'payload') is distinct from 'object' or exists(select 1 from jsonb_object_keys(op->'payload') k where k<>'reason') then raise exception 'Unsupported delivery fields';end if;
  reason:=private.require_text(op->'payload'->>'reason','Delivery reason and authorization',2000);balance:=private.payment_balance(d);
  d:=d||jsonb_build_object('status','delivered','delivery',jsonb_build_object('reason',reason,'actorId',effective_actor,'at',at_time,'outstandingCents',balance->'outstandingCents','paymentStatus',balance->'status','creditAuthorized',(balance->>'outstandingCents')::bigint>0));
 else d:=private.record_payment(d,op->'payload',kind,effective_actor,opid,at_time);end if;
 update private.orders set data=d,revision=rev+1 where workshop_id=w and id=oid;
 insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,before_data,after_data) values(w,effective_actor,opid,oid,kind,before_doc,d);
 insert into private.operations values(w,opid,oid,effective_actor,dev,now(),op,'accepted',null);
 return '{"status":"accepted","reason":null}';
end $$;
alter function private.snapshot(uuid) rename to snapshot_before_payments;
create function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;r jsonb;rows jsonb;begin
 m:=private.membership(w);r:=private.snapshot_before_payments(w);
 if m->>'role'='technician' then
  select coalesce(jsonb_agg(o-'payments'-'delivery'),'[]') into rows from jsonb_array_elements(r->'orders') o;r:=r||jsonb_build_object('orders',rows);
 end if;return r;
end $$;
revoke all on function private.payment_balance(jsonb),private.record_payment(jsonb,jsonb,text,uuid,uuid,timestamptz),private.apply_record_before_payments(uuid,uuid,jsonb,uuid),private.apply_record(uuid,uuid,jsonb,uuid),private.snapshot_before_payments(uuid),private.snapshot(uuid) from public,anon,authenticated;
grant execute on function private.snapshot(uuid) to authenticated;
commit;
