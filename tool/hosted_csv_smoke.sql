begin;
do $$
declare w uuid:=gen_random_uuid();uid uuid:=gen_random_uuid();sid uuid:=gen_random_uuid();dev uuid:=gen_random_uuid();cid uuid:=gen_random_uuid();rid uuid:=gen_random_uuid();car uuid:=gen_random_uuid();p jsonb;r jsonb;s jsonb;passed int:=0;failed boolean;
begin
 insert into auth.users(id,email) values(uid,'csv-validation-'||uid||'@example.invalid');insert into auth.sessions(id,user_id) values(sid,uid);
 insert into private.workshops(id,name) values(w,'Fictional rolled-back CSV validation');insert into private.members values(w,uid,'Fictional admin','admin',true,true);
 perform set_config('request.jwt.claim.sub',uid::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'session_id',sid)::text,true);perform public.device_snapshot(w,dev);
 p:=jsonb_build_object('kind','clients','reason','Fictional validation','rows',jsonb_build_array(jsonb_build_object('id',rid,'line',2,'data',jsonb_build_object('code','C1','name','Fictional client','phone','','email','','taxId','','address',''))));
 r:=public.import_command(w,dev,cid,'import_preview',p);if r->'rows'->0->>'status'<>'ready' or exists(select 1 from private.clients where workshop_id=w) then raise exception 'Preview wrote data';end if;passed:=passed+1;
 r:=public.import_command(w,dev,cid,'import_commit',p);if r->>'created'<>'1' then raise exception 'Import failed';end if;passed:=passed+1;
 if public.import_command(w,dev,cid,'import_commit',p)<>r then raise exception 'Retry changed';end if;passed:=passed+1;
 failed:=false;begin perform public.import_command(w,dev,cid,'import_commit',p||jsonb_build_object('reason','Changed'));exception when others then failed:=true;end;if not failed then raise exception 'Changed receipt accepted';end if;passed:=passed+1;
 r:=public.import_command(w,dev,gen_random_uuid(),'import_commit',p);if r->>'created'<>'0' or r->'rows'->0->>'status'<>'duplicate' then raise exception 'Duplicate overwrote client';end if;passed:=passed+1;
 p:=jsonb_build_object('kind','vehicles','reason','Fictional validation','rows',jsonb_build_array(jsonb_build_object('id',car,'line',2,'data',jsonb_build_object('plate','9234ABC','country','ES','vin','CSV-FICTIONAL','vehicle','Fictional vehicle','engine','2020','km',120,'clientCode','C1'))));
 r:=public.import_command(w,dev,gen_random_uuid(),'import_commit',p);if r->>'created'<>'1' or not exists(select 1 from private.vehicle_profiles where workshop_id=w and vehicle_id=car and owner_id=rid) or exists(select 1 from private.orders where workshop_id=w) then raise exception 'Vehicle identity not preserved';end if;passed:=passed+1;
 p:=jsonb_build_object('kind','catalog','reason','Fictional validation','rows',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'line',2,'data',jsonb_build_object('reference','CSV-FICT','description','Fictional','unit','L','priceCents',1235,'costCents',0,'costKnown',false,'taxBps',2100,'stockMilli',1125,'minMilli',500,'supplier','Fictional'))));
 r:=public.import_command(w,dev,gen_random_uuid(),'import_commit',p);if r->>'created'<>'1' then raise exception 'Catalog failed';end if;s:=public.device_snapshot(w,dev);if s->'catalog'->0->>'stockMilli'<>'1125' or s->'catalog'->0->>'costKnown'<>'false' then raise exception 'Quantity or cost changed';end if;passed:=passed+1;
 update private.members set role='office' where workshop_id=w and user_id=uid;failed:=false;begin perform public.import_command(w,dev,gen_random_uuid(),'import_commit',p);exception when others then failed:=true;end;if not failed then raise exception 'Office imported catalog';end if;passed:=passed+1;
 update private.members set role='technician' where workshop_id=w and user_id=uid;s:=public.device_snapshot(w,dev);if jsonb_array_length(s->'clients')<>0 then raise exception 'Private contact leak';end if;failed:=false;begin perform public.import_command(w,dev,gen_random_uuid(),'import_preview',p);exception when others then failed:=true;end;if not failed then raise exception 'Technician imported data';end if;passed:=passed+1;
 if has_function_privilege('anon','public.import_command(uuid,uuid,uuid,text,jsonb)','EXECUTE') or has_function_privilege('authenticated','private.import_row(uuid,text,uuid,jsonb,boolean)','EXECUTE') then raise exception 'Import privileges leaked';end if;passed:=passed+1;
 perform set_config('tallerflow.validation',jsonb_build_object('passed',passed,'environment','hosted PostgreSQL','realAuthLogin',false,'csvNativePicker',false,'fixtureRolledBack',true)::text,true);
end $$;
select current_setting('tallerflow.validation')::jsonb as validation;
rollback;
