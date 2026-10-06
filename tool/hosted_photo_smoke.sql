begin;
do $$
declare w uuid:=gen_random_uuid();a uuid:=gen_random_uuid();t uuid:=gen_random_uuid();sid uuid:=gen_random_uuid();dev uuid:=gen_random_uuid();oid uuid:=gen_random_uuid();tid uuid:=gen_random_uuid();pid uuid:=gen_random_uuid();cid uuid:=gen_random_uuid();p jsonb;r jsonb;s jsonb;passed int:=0;failed boolean;
begin
 insert into auth.users(id,email) values(a,'photo-admin-'||a||'@example.invalid'),(t,'photo-tech-'||t||'@example.invalid');
 insert into auth.sessions(id,user_id) values(sid,a);
 insert into private.workshops(id,name) values(w,'Fictional rolled-back photo validation');
 insert into private.members values(w,a,'Fictional admin','admin',true,true),(w,t,'Fictional technician','technician',false,true);
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',sid)::text,true);
 perform public.device_snapshot(w,dev);
 r:=public.apply_operation(w,dev,jsonb_build_object('id',gen_random_uuid(),'orderId',oid,'actorId',a,'kind','receive','baseRevision',0,'at',now(),'payload',jsonb_build_object('plate','1298ABC','country','ES','vin','FICTIONAL-PHOTO-VALIDATION','vehicle','Fictional','engine','2020','client','Fictional owner','phone','','km',10,'symptom','Fictional','tasks',jsonb_build_array(jsonb_build_object('id',tid,'title','Fictional task','assignees',jsonb_build_array(t),'estimateMinutes',30)))));
 if r->>'status'<>'accepted' then raise exception 'Reception fixture failed';end if;
 p:=jsonb_build_object('id',pid,'orderId',oid,'originalDeviceId',dev,'sha256',repeat('ab',32),'size',100,'mime','image/jpeg','caption','Fictional damaged part','capturedAt',now());
 r:=public.photo_command(w,dev,cid,'photo_prepare',p);if r->>'status'<>'pending' then raise exception 'Prepare failed';end if;passed:=passed+1;
 if public.photo_command(w,dev,cid,'photo_prepare',p)<>r then raise exception 'Retry changed';end if;passed:=passed+1;
 failed:=false;begin perform public.photo_command(w,dev,cid,'photo_prepare',p||jsonb_build_object('caption','Changed'));exception when others then failed:=true;end;if not failed then raise exception 'ID reuse accepted';end if;passed:=passed+1;
 failed:=false;begin perform public.photo_command(w,dev,gen_random_uuid(),'photo_prepare',p||jsonb_build_object('unexpected','value'));exception when others then failed:=true;end;if not failed then raise exception 'Unexpected field accepted';end if;passed:=passed+1;
 s:=public.device_snapshot(w,dev);if jsonb_array_length(s->'photoManifest')<>1 or s->'photoManifest'->0->>'filePresent'<>'false' then raise exception 'Manifest failed';end if;passed:=passed+1;
 failed:=false;begin insert into private.close_requests(workshop_id,id,order_id,revision,status,requested_by) values(w,gen_random_uuid(),oid,1,'active',a);exception when others then failed:=true;end;if not failed then raise exception 'Pending photo closed';end if;passed:=passed+1;
 if has_function_privilege('authenticated','public.photo_finalize(uuid,uuid,uuid,uuid,uuid,text,integer)','EXECUTE') or has_function_privilege('anon','public.photo_command(uuid,uuid,uuid,text,jsonb)','EXECUTE') then raise exception 'Photo privileges leaked';end if;passed:=passed+1;
 if private.photo_storage_access('another-bucket',r->>'path',true) or private.photo_storage_access('tallerflow-photos',w::text||'/'||oid||'/'||gen_random_uuid()||'.jpg',true) then raise exception 'Unreserved path allowed';end if;passed:=passed+1;
 update private.devices set retired_at=now(),retirement_reason='Fictional validation' where workshop_id=w and id=dev;
 failed:=false;begin perform public.photo_upload_info(w,dev,pid);exception when others then failed:=true;end;if not failed then raise exception 'Retired uploader allowed';end if;passed:=passed+1;
 if exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'tallerflow_photo%' and cmd in ('ALL','UPDATE','DELETE')) then raise exception 'Mutable evidence policy';end if;passed:=passed+1;
 perform set_config('tallerflow.validation',jsonb_build_object('passed',passed,'environment','hosted PostgreSQL','realAuthLogin',false,'storageHttp',false,'fixtureRolledBack',true)::text,true);
end $$;
select current_setting('tallerflow.validation')::jsonb as validation;
rollback;
