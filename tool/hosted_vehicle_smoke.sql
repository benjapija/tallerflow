-- Hosted SQL with fictional identities; all fixtures are rolled back.
-- This does not validate Auth HTTP, portal permissions or native plugins.
do $$
declare w uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); t uuid:=gen_random_uuid();
 desk uuid:=gen_random_uuid(); phone uuid:=gen_random_uuid(); oid uuid:=gen_random_uuid();
 tid uuid:=gen_random_uuid(); vid uuid; owner uuid; new_owner uuid:=gen_random_uuid();
 cid uuid:=gen_random_uuid(); p jsonb; op jsonb; s jsonb; v jsonb; r jsonb;
 doc jsonb:=jsonb_build_object('type','work_note','clientSnapshot','Destinatario ficticio original','plateSnapshot','1234ABC','totalCents',1234);
 passed int:=0; completed boolean:=false;
begin
 begin
  insert into auth.users(id) values(a),(t);
  insert into auth.sessions(id,user_id) values(desk,a),(phone,t);
  insert into private.workshops(id,name) values(w,'TallerFlow · historial ficticio transaccional');
  insert into private.members values(w,a,'Oficina ficticia','admin',true,true),(w,t,'Operario ficticio','technician',false,true);
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',desk)::text,true);
  execute 'set local role authenticated'; perform public.device_snapshot(w,desk);
  p:=jsonb_build_object('plate','12-34 ABC','country','es','vin','FICTIONALVIN001','vehicle','Vehículo ficticio','engine','Motor ficticio','client','Destinatario ficticio original','phone','600000001','km',100,'symptom','Síntoma ficticio','location','Box','keys','Panel','due','Hoy','priority','Normal','tasks',jsonb_build_array(jsonb_build_object('id',tid,'title','Tarea ficticia','assignees',jsonb_build_array(t),'estimateMinutes',30)));
  op:=jsonb_build_object('id',gen_random_uuid(),'orderId',oid,'actorId',a,'kind','receive','at',now(),'baseRevision',0,'payload',p);
  r:=public.apply_operation(w,desk,op);
  if r->>'status'<>'accepted' then raise exception 'FAIL reception: %',r;end if;
  s:=public.device_snapshot(w,desk);v:=s->'vehicleProfiles'->0;vid:=(v->>'id')::uuid;owner:=(s->'orders'->0->>'ownerId')::uuid;
  execute 'reset role';
  insert into private.documents(workshop_id,id,order_id,type,version,recipient_id,snapshot) values(w,gen_random_uuid(),oid,'work_note',1,a,doc);
  update private.orders set data=data||jsonb_build_object('document',doc) where workshop_id=w and id=oid;
  execute 'set local role authenticated';
  r:=public.vehicle_command(w,desk,cid,'vehicle_change',jsonb_build_object('vehicleId',vid,'revision',v->'revision','change','registration','plate','98-76 xyz','country','ES','vin','FICTIONALVIN001','reason','Cambio ficticio verificado'));
  if public.vehicle_command(w,desk,cid,'vehicle_change',jsonb_build_object('vehicleId',vid,'revision',v->'revision','change','registration','plate','98-76 xyz','country','ES','vin','FICTIONALVIN001','reason','Cambio ficticio verificado'))<>r then raise exception 'FAIL stable command receipt';end if;passed:=passed+1;
  s:=public.device_snapshot(w,desk);v:=s->'vehicleProfiles'->0;
  if v->>'id'<>vid::text or v->>'plate'<>'9876XYZ' or v->>'engine'<>'Motor ficticio' or jsonb_array_length(v->'identifiers')<>3 or s->'orders'->0->'document'<>doc or s->'orders'->0->>'plate'<>'1234ABC' then raise exception 'FAIL original identity/document/technical data';end if;passed:=passed+1;
  op:=jsonb_set(jsonb_set(op,'{id}',to_jsonb(gen_random_uuid())), '{orderId}',to_jsonb(gen_random_uuid()));
  r:=public.apply_operation(w,desk,op);s:=public.device_snapshot(w,desk);
  if r->>'status'<>'accepted' or jsonb_array_length(s->'orders')<>2 or exists(select 1 from jsonb_array_elements(s->'orders') q where q->>'vehicleId'<>vid::text or q->>'ownerId'<>owner::text) then raise exception 'FAIL old registration linkage';end if;passed:=passed+1;
  v:=s->'vehicleProfiles'->0;
  perform public.vehicle_command(w,desk,gen_random_uuid(),'vehicle_change',jsonb_build_object('vehicleId',vid,'revision',v->'revision','change','owner','ownerId',new_owner,'name','Destinatario ficticio nuevo','phone','600000002','reason','Transmisión ficticia verificada'));
  s:=public.device_snapshot(w,desk);
  if s->'vehicleProfiles'->0->>'ownerId'<>new_owner::text or exists(select 1 from jsonb_array_elements(s->'orders') q where q->>'ownerId'<>owner::text) then raise exception 'FAIL original recipient changed';end if;passed:=passed+1;
  op:=jsonb_set(jsonb_set(op,'{id}',to_jsonb(gen_random_uuid())), '{orderId}',to_jsonb(gen_random_uuid()));
  r:=public.apply_operation(w,desk,op);
  if r->>'status'<>'conflict' or r->>'reason' not like '%Confirm owner%' then raise exception 'FAIL stale owner conflict';end if;passed:=passed+1;
  op:=jsonb_set(jsonb_set(op,'{id}',to_jsonb(gen_random_uuid())),'{payload}',p||jsonb_build_object('client','Destinatario ficticio nuevo','phone','600000002'));
  r:=public.apply_operation(w,desk,op);s:=public.device_snapshot(w,desk);
  if r->>'status'<>'accepted' or jsonb_array_length(s->'orders')<>3 or not exists(select 1 from jsonb_array_elements(s->'orders') q where q->>'ownerId'=new_owner::text and q->>'vehicleId'=vid::text) then raise exception 'FAIL new recipient reception';end if;passed:=passed+1;
  v:=s->'vehicleProfiles'->0;
  begin
   perform public.vehicle_command(w,desk,gen_random_uuid(),'vehicle_change',jsonb_build_object('vehicleId',vid,'revision',v->'revision','change','owner','ownerId',owner,'name','Identidad falsa','phone','','reason','No válido'));
   raise exception 'FAIL earlier recipient identity reused';
  exception when raise_exception then if sqlerrm not like '%New recipient%' then raise;end if;passed:=passed+1;end;
  perform set_config('request.jwt.claim.sub',t::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',t,'session_id',phone)::text,true);
  s:=public.device_snapshot(w,phone);
  if jsonb_array_length(s->'vehicleHistory')<>3 or s->'vehicleProfiles'->0->'owner'<>'null'::jsonb or exists(select 1 from jsonb_array_elements(s->'vehicleHistory') q where q ? 'recipient' or q ? 'ownerId' or q ? 'document') then raise exception 'FAIL technician personal data redaction';end if;passed:=passed+1;
  begin
   perform public.vehicle_command(w,phone,gen_random_uuid(),'vehicle_change',jsonb_build_object('vehicleId',vid,'revision',v->'revision','change','owner'));
   raise exception 'FAIL technician changes recipient';
  exception when insufficient_privilege then passed:=passed+1;end;
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',desk)::text,true);
  r:=public.export_workshop(w,desk);
  if r->>'databaseVersion'<>'5' or jsonb_array_length(r->'tables'->'vehicle_changes')<>2 or jsonb_array_length(r->'tables'->'order_recipient_refs')<>3 or r->'tables'->'documents'->0->'snapshot'<>doc then raise exception 'FAIL complete vehicle archive';end if;passed:=passed+1;
  execute 'reset role';
  if exists(select 1 from private.order_recipient_refs where workshop_id=w and order_id=oid and owner_id<>owner) then raise exception 'FAIL original immutable reference';end if;passed:=passed+1;
  completed:=true;raise exception 'ROLLBACK_SYNTHETIC_SUCCESS' using errcode='P0002';
 exception when no_data_found then if not completed then raise;end if;end;
 if exists(select 1 from private.workshops where id=w) or exists(select 1 from auth.users where id in(a,t)) then raise exception 'FAIL fixture rollback';end if;
 perform set_config('tallerflow.vehicle_smoke',jsonb_build_object('checks',passed,'fixtureRolledBack',true,'environment','Hosted PostgreSQL; synthetic identities','authApiValidated',false,'nativeValidated',false)::text,false);
end $$;
select current_setting('tallerflow.vehicle_smoke')::jsonb as validation;
