-- Hosted PostgreSQL regression with synthetic identities, rolled back completely.
-- This exercises real hosted SQL and roles, not GoTrue sign-in or native storage.
do $$
declare w uuid:=gen_random_uuid(); admin_id uuid:=gen_random_uuid();tech_id uuid:=gen_random_uuid();
 desk uuid:=gen_random_uuid();phone uuid:=gen_random_uuid();oid uuid:=gen_random_uuid();tid uuid:=gen_random_uuid();
 cid uuid:=gen_random_uuid();opid uuid;timer uuid;d jsonb;r jsonb;req jsonb;payload jsonb;revision bigint;passed int:=0;completed boolean:=false;
begin
 begin
  insert into auth.users(id) values(admin_id),(tech_id);
  insert into auth.sessions(id,user_id) values(desk,admin_id),(phone,tech_id);
  insert into private.workshops(id,name) values(w,'TallerFlow · prueba transaccional ficticia');
  insert into private.members values(w,admin_id,'Administración ficticia','admin',true,true),(w,tech_id,'Operario ficticio','technician',false,true);
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'session_id',desk)::text,true);
  execute 'set local role authenticated';
  d:=public.device_snapshot(w,desk);
  if d->'actor'->>'role'<>'admin' then raise exception 'FAIL admin snapshot';end if;passed:=passed+1;
  payload:=jsonb_build_object('revision',0,'reason','Fictional rates','settings',jsonb_build_object('hourlyRateCents',6000,'taxBps',1000,'internalHourlyCostCents',2500,'internalCostKnown',true));
  r:=public.management_command(w,desk,cid,'settings_save',payload);
  if public.management_command(w,desk,cid,'settings_save',payload)<>r then raise exception 'FAIL command idempotency';end if;passed:=passed+1;
  r:=public.apply_operation(w,desk,jsonb_build_object('id',gen_random_uuid(),'orderId',oid,'actorId',admin_id,'kind','receive','at',now(),'baseRevision',0,'payload',jsonb_build_object(
   'plate','FICT 0001','country','ES','vin','','client','Cliente ficticio','phone','','vehicle','Vehículo ficticio','engine','Prueba','km',0,'symptom','Comprobación ficticia','due','Prueba','priority','Normal','location','Prueba','keys','Prueba',
   'tasks',jsonb_build_array(jsonb_build_object('id',tid,'title','Tarea ficticia','estimateMinutes',30,'assignees',jsonb_build_array(tech_id))))));
  if r->>'status'<>'accepted' then raise exception 'FAIL reception: %',r;end if;passed:=passed+1;
  d:=public.device_snapshot(w,desk);revision:=(d->'orders'->0->>'revision')::bigint;
  r:=public.apply_operation(w,desk,jsonb_build_object('id',gen_random_uuid(),'orderId',oid,'actorId',admin_id,'kind','authorize','at',now(),'baseRevision',revision,
   'payload',jsonb_build_object('taskId',tid,'approvedCents',50000,'version',1,'customer','Ficticio','evidence','Autorización ficticia')));
  if r->>'status'<>'accepted' then raise exception 'FAIL authorization';end if;
  perform set_config('request.jwt.claim.sub',tech_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',tech_id,'session_id',phone)::text,true);
  d:=public.device_snapshot(w,phone);
  if d->'settings' ? 'hourlyRateCents' or d->'settings' ? 'internalHourlyCostCents' or d->'orders'->0->'tasks'->0 ? 'rateCents' then raise exception 'FAIL technician money redaction';end if;passed:=passed+1;
  begin
   perform public.management_command(w,phone,gen_random_uuid(),'settings_save',payload);
   raise exception 'FAIL technician admin permission';
  exception when insufficient_privilege then passed:=passed+1;end;
  revision:=(d->'orders'->0->>'revision')::bigint;timer:=gen_random_uuid();
  payload:=jsonb_build_object('id',timer,'orderId',oid,'actorId',tech_id,'kind','start','at',now(),'baseRevision',revision,'payload',jsonb_build_object('taskId',tid));
  r:=public.apply_operation(w,phone,payload);
  if r->>'status'<>'accepted' or public.apply_operation(w,phone,payload)<>r then raise exception 'FAIL timer idempotency';end if;passed:=passed+1;
  r:=public.apply_operation(w,phone,jsonb_build_object('id',gen_random_uuid(),'orderId',oid,'actorId',tech_id,'kind','stop','at',now(),'baseRevision',revision,'payload',jsonb_build_object('sessionId',timer)));
  if r->>'status'<>'accepted' then raise exception 'FAIL stop';end if;
  d:=public.device_snapshot(w,phone);revision:=(d->'orders'->0->>'revision')::bigint;
  r:=public.apply_operation(w,phone,jsonb_build_object('id',gen_random_uuid(),'orderId',oid,'actorId',tech_id,'kind','finish_task','at',now(),'baseRevision',revision,'payload',jsonb_build_object('taskId',tid)));
  if r->>'status'<>'accepted' then raise exception 'FAIL task completion';end if;passed:=passed+1;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'session_id',desk)::text,true);
  d:=public.device_snapshot(w,desk);revision:=(d->'orders'->0->>'revision')::bigint;
  r:=public.apply_operation(w,desk,jsonb_build_object('id',gen_random_uuid(),'orderId',oid,'actorId',admin_id,'kind','billable','at',now(),'baseRevision',revision,'payload',jsonb_build_object('taskId',tid,'minutes',30,'reason','Fictional review')));
  if r->>'status'<>'accepted' then raise exception 'FAIL billing';end if;
  d:=public.device_snapshot(w,desk);revision:=(d->'orders'->0->>'revision')::bigint;
  r:=public.apply_operation(w,desk,jsonb_build_object('id',gen_random_uuid(),'orderId',oid,'actorId',admin_id,'kind','quality','at',now(),'baseRevision',revision,'payload',jsonb_build_object('result','Fictional quality','pendingSymptoms','')));
  if r->>'status'<>'accepted' then raise exception 'FAIL quality';end if;
  d:=public.device_snapshot(w,desk);revision:=(d->'orders'->0->>'revision')::bigint;
  req:=public.reliability_command(w,desk,gen_random_uuid(),'request_close',jsonb_build_object('orderId',oid,'revision',revision));
  perform public.reliability_command(w,desk,gen_random_uuid(),'ack_close',jsonb_build_object('orderId',oid,'revision',revision,'requestId',req->>'requestId','locallyFrozen',true));
  begin
   perform public.reliability_command(w,desk,gen_random_uuid(),'issue',jsonb_build_object('orderId',oid,'requestId',req->>'requestId'));
   raise exception 'FAIL missing technician closure';
  exception when raise_exception then if sqlerrm not like '%Unreconciled%' then raise;end if;passed:=passed+1;end;
  perform set_config('request.jwt.claim.sub',tech_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',tech_id,'session_id',phone)::text,true);
  perform public.reliability_command(w,phone,gen_random_uuid(),'ack_close',jsonb_build_object('orderId',oid,'revision',revision,'requestId',req->>'requestId','locallyFrozen',true));
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'session_id',desk)::text,true);
  r:=public.reliability_command(w,desk,gen_random_uuid(),'issue',jsonb_build_object('orderId',oid,'requestId',req->>'requestId'));
  if (r->'document'->>'totalCents')::bigint<>3300 then raise exception 'FAIL deterministic issued amount: %',r;end if;passed:=passed+1;
  r:=public.export_workshop(w,desk);
  if jsonb_array_length(r->'tables'->'documents')<>1 or r->>'authExcluded'<>'true' then raise exception 'FAIL hosted archive';end if;passed:=passed+1;
  execute 'reset role';
  completed:=true;raise exception 'ROLLBACK_SYNTHETIC_SUCCESS' using errcode='P0002';
 exception when no_data_found then if not completed then raise;end if;end;
 if exists(select 1 from private.workshops where id=w) or exists(select 1 from auth.users where id=admin_id) then raise exception 'FAIL fixture rollback';end if;
 perform set_config('tallerflow.smoke_result',jsonb_build_object('checks',passed,'environment','Hosted PostgreSQL 17; synthetic identities; transaction rolled back','authApiValidated',false,'nativeValidated',false)::text,false);
end $$;
select current_setting('tallerflow.smoke_result')::jsonb as validation;
