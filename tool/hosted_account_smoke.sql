-- Hosted SQL only: identities are synthetic and every fixture is rolled back.
do $$
declare w uuid:=gen_random_uuid();a uuid:=gen_random_uuid();dev uuid:=gen_random_uuid();rid uuid:=gen_random_uuid();u uuid:=gen_random_uuid();
 p jsonb;r jsonb;state jsonb;passed int:=0;completed boolean:=false;
begin
 begin
  insert into auth.users(id,email) values(a,a::text||'@example.invalid');
  insert into auth.sessions(id,user_id) values(dev,a);
  insert into private.workshops(id,name) values(w,'TallerFlow · altas ficticias transaccionales');
  insert into private.members values(w,a,'Administrador ficticio','admin',true,true);
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',dev)::text,true);
  execute 'set local role authenticated';perform public.device_snapshot(w,dev);
  p:=jsonb_build_object('name','Operario ficticio','email',u::text||'@example.invalid','role','technician','seePrices',false,'seeCosts',false,'reason','Prueba ficticia','password','MUST_NOT_BE_STORED');
  r:=public.prepare_account(w,dev,rid,p);
  if public.prepare_account(w,dev,rid,p)<>r then raise exception 'FAIL stable account preparation';end if;passed:=passed+1;
  begin
   perform public.account_provision_state(w,rid);raise exception 'FAIL client provision privilege';
  exception when insufficient_privilege then passed:=passed+1;end;
  execute 'reset role';
  if exists(select 1 from private.account_requests where workshop_id=w and payload ? 'password') then raise exception 'FAIL stored credential';end if;passed:=passed+1;
  insert into auth.users(id,email,raw_app_meta_data) values(u,u::text||'@example.invalid',jsonb_build_object('tallerflow_request',rid,'tallerflow_workshop',w));
  execute 'set local role service_role';state:=public.account_provision_state(w,rid);
  if state->>'userId'<>u::text then raise exception 'FAIL Auth identity lookup';end if;passed:=passed+1;
  r:=public.finish_account_provision(w,rid,u);
  if public.finish_account_provision(w,rid,u)<>r then raise exception 'FAIL finalization retry';end if;passed:=passed+1;
  execute 'reset role';
  if (select count(*) from private.audit where workshop_id=w and kind='account_created')<>1 or
   not exists(select 1 from private.members where workshop_id=w and user_id=u and role='technician' and active) then raise exception 'FAIL duplicate membership or audit';end if;passed:=passed+1;
  update private.devices set retired_at=now() where workshop_id=w and id=dev;
  execute 'set local role service_role';
  begin
   perform public.account_provision_state(w,rid);raise exception 'FAIL retirement access';
  exception when raise_exception then if sqlerrm='FAIL retirement access' then raise;end if;passed:=passed+1;end;
  execute 'reset role';completed:=true;raise exception 'ROLLBACK_SYNTHETIC_SUCCESS' using errcode='P0002';
 exception when no_data_found then if not completed then raise;end if;end;
 if exists(select 1 from private.workshops where id=w) or exists(select 1 from auth.users where id in(a,u)) then raise exception 'FAIL fixture rollback';end if;
 perform set_config('tallerflow.account_smoke',jsonb_build_object('checks',passed,'fixtureRolledBack',true,'environment','Hosted PostgreSQL; synthetic identities','authApiValidated',false)::text,false);
end $$;
select current_setting('tallerflow.account_smoke')::jsonb as validation;
