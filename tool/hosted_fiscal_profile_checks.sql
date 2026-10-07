begin;
do $$
declare w uuid:=gen_random_uuid();other uuid:=gen_random_uuid();a uuid:=gen_random_uuid();o uuid:=gen_random_uuid();t uuid:=gen_random_uuid();f uuid:=gen_random_uuid();sid uuid:=gen_random_uuid();osid uuid:=gen_random_uuid();tsid uuid:=gen_random_uuid();fsid uuid:=gen_random_uuid();dev uuid:=gen_random_uuid();od uuid:=gen_random_uuid();td uuid:=gen_random_uuid();fd uuid:=gen_random_uuid();vehicle uuid:=gen_random_uuid();oid uuid:=gen_random_uuid();doc uuid:=gen_random_uuid();cid uuid:=gen_random_uuid();profile jsonb;payload jsonb;s jsonb;r jsonb;original jsonb;before_profile jsonb;value text;rev int:=1;failed boolean;passed int:=0;
begin
 insert into auth.users(id,email) values(a,'fiscal-admin-'||a||'@example.invalid'),(o,'fiscal-office-'||o||'@example.invalid'),(t,'fiscal-tech-'||t||'@example.invalid'),(f,'fiscal-other-'||f||'@example.invalid');
 insert into auth.sessions(id,user_id) values(sid,a),(osid,o),(tsid,t),(fsid,f);
 insert into private.workshops(id,name) values(w,'Fictional rolled-back fiscal preparation'),(other,'Fictional isolated fiscal preparation');
 insert into private.members values(w,a,'Fictional admin','admin',true,true),(w,o,'Fictional office','office',true,true),(w,t,'Fictional tech','technician',false,true),(other,f,'Fictional foreign','admin',true,true);
 insert into private.vehicles(workshop_id,id,plate,country) values(w,vehicle,'1234FIC','ES');
 original:=jsonb_build_object('id',oid,'vehicleId',vehicle,'plate','1234FIC','vehicle','Fictional','status','issued','tasks','[]'::jsonb,'times','[]'::jsonb,'parts','[]'::jsonb,'notes','[]'::jsonb,'diagnosisNotebook','[]'::jsonb,'document',jsonb_build_object('totalCents',3300,'recipient',jsonb_build_object('name','Fictional original')));
 insert into private.orders(workshop_id,id,vehicle_id,data,revision) values(w,oid,vehicle,original,7);
 insert into private.documents(workshop_id,id,order_id,type,version,recipient_id,snapshot) values(w,doc,oid,'work_note',1,a,original->'document');
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',sid)::text,true);s:=public.device_snapshot(w,dev);
 profile:='{"country":"ES","legalForm":"company","territory":"common","sii":"no","clients":"mixed","turnover":"under_8m","taxSystem":"iva"}';payload:=jsonb_build_object('revision',0,'reason','Fictional preparation','profile',profile);
 r:=public.management_command(w,dev,cid,'fiscal_profile_save',payload);s:=public.device_snapshot(w,dev);if r->>'revision'<>'1' or s->'settings'->'fiscalProfile'->'emissionEnabled'<>'false'::jsonb then raise exception 'Preparation did not remain disabled';end if;passed:=passed+1;
 if public.management_command(w,dev,cid,'fiscal_profile_save',payload)<>r then raise exception 'Lost reply changed result';end if;passed:=passed+1;
 failed:=false;begin perform public.management_command(w,dev,cid,'fiscal_profile_save',payload||'{"reason":"Changed"}');exception when others then failed:=true;end;if not failed then raise exception 'Reused identity changed content';end if;passed:=passed+1;
 failed:=false;begin perform public.management_command(w,dev,gen_random_uuid(),'fiscal_profile_save',payload);exception when others then failed:=true;end;if not failed then raise exception 'Stale profile replaced original';end if;passed:=passed+1;
 for value in select unnest(array['{"emissionEnabled":true}','{"emissionEnabled":"false"}','{"profileVersion":2}','{"apiKey":"fictional"}','{"territory":"invalid"}','{"country":"FR"}','{"sii":null}']) loop
  failed:=false;begin perform public.management_command(w,dev,gen_random_uuid(),'fiscal_profile_save',jsonb_build_object('revision',1,'reason','Fictional invalid option','profile',profile||value::jsonb));exception when others then failed:=true;end;if not failed then raise exception 'Invalid preparation accepted';end if;
 end loop;passed:=passed+1;
 foreach value in array array['common','canary','ceuta','melilla','navarra','alava','bizkaia','gipuzkoa','unknown'] loop
  perform public.management_command(w,dev,gen_random_uuid(),'fiscal_profile_save',jsonb_build_object('revision',rev,'reason','Fictional preparation','profile',profile||jsonb_build_object('territory',value)));rev:=rev+1;
 end loop;
 foreach value in array array['sole_trader','company','attribution','other','unknown'] loop
  perform public.management_command(w,dev,gen_random_uuid(),'fiscal_profile_save',jsonb_build_object('revision',rev,'reason','Fictional preparation','profile',profile||jsonb_build_object('legalForm',value)));rev:=rev+1;
 end loop;passed:=passed+1;
 s:=public.device_snapshot(w,dev);before_profile:=s->'settings'->'fiscalProfile';perform public.management_command(w,dev,gen_random_uuid(),'settings_save',jsonb_build_object('revision',rev,'reason','Fictional tariff change','settings','{"hourlyRateCents":6000,"taxBps":2100,"internalHourlyCostCents":2500,"internalCostKnown":true}'::jsonb));
 s:=public.device_snapshot(w,dev);if s->'settings'->'fiscalProfile'<>before_profile or s->'orders'->0->'document'<>original->'document' or s->'orders'->0->>'revision'<>'7' then raise exception 'Profile or tariff altered previous document';end if;passed:=passed+1;
 r:=public.export_workshop(w,dev);if r->>'databaseVersion'<>'13' or r->'workshop'->'settings'->'fiscalProfile'<>before_profile or r->'tables'->'documents'->0->'snapshot'<>original->'document' or (select count(*) from jsonb_array_elements(r->'tables'->'audit') x where x->>'kind'='fiscal_profile_save')<>15 then raise exception 'Backup omitted originals or profile audit';end if;passed:=passed+1;
 perform set_config('request.jwt.claim.sub',o::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'session_id',osid)::text,true);perform public.device_snapshot(w,od);
 failed:=false;begin perform public.management_command(w,od,gen_random_uuid(),'fiscal_profile_save',payload);exception when others then failed:=true;end;if not failed then raise exception 'Office wrote preparation';end if;
 perform set_config('request.jwt.claim.sub',t::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',t,'session_id',tsid)::text,true);perform public.device_snapshot(w,td);
 failed:=false;begin perform public.management_command(w,td,gen_random_uuid(),'fiscal_profile_save',payload);exception when others then failed:=true;end;if not failed then raise exception 'Technician wrote preparation';end if;passed:=passed+1;
 perform set_config('request.jwt.claim.sub',f::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',f,'session_id',fsid)::text,true);s:=public.device_snapshot(other,fd);if s->'settings' ? 'fiscalProfile' then raise exception 'Profile crossed workshop';end if;
 failed:=false;begin perform public.management_command(w,fd,gen_random_uuid(),'fiscal_profile_save',payload);exception when others then failed:=true;end;if not failed then raise exception 'Foreign account wrote preparation';end if;passed:=passed+1;
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',sid)::text,true);delete from auth.sessions where id=sid;
 failed:=false;begin perform public.management_command(w,dev,gen_random_uuid(),'fiscal_profile_save',payload);exception when others then failed:=true;end;if not failed then raise exception 'Revoked session wrote preparation';end if;passed:=passed+1;
 if has_function_privilege('anon','public.management_command(uuid,uuid,uuid,text,jsonb)','execute') or has_function_privilege('authenticated','private.normalize_fiscal_profile(jsonb)','execute') or has_function_privilege('authenticated','private.management_command_before_fiscal(uuid,uuid,uuid,text,jsonb)','execute') then raise exception 'Preparation bypass available';end if;passed:=passed+1;
 perform set_config('tallerflow.fiscal_profile_checks',passed::text,true);
end $$;
select current_setting('tallerflow.fiscal_profile_checks')::int as checks_passed,'Hosted PostgreSQL; synthetic Auth; full rollback; fiscal emission disabled' as scope;
rollback;
