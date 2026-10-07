-- Synthetic identities only. Every fixture is rolled back; no GoTrue/HTTP login.
begin;
do $$
declare w uuid:=gen_random_uuid();other uuid:=gen_random_uuid();a uuid:=gen_random_uuid();o uuid:=gen_random_uuid();
 sid uuid:=gen_random_uuid();osid uuid:=gen_random_uuid();dev uuid:=gen_random_uuid();od uuid:=gen_random_uuid();cid uuid:=gen_random_uuid();
 p jsonb;r jsonb;nextp jsonb;withdraw jsonb;original jsonb;b jsonb;failed boolean;checks int:=0;
begin
 insert into auth.users(id,email) values(a,'draft-admin-'||a||'@example.invalid'),(o,'draft-office-'||o||'@example.invalid');
 insert into auth.sessions(id,user_id) values(sid,a),(osid,o);
 insert into private.workshops(id,name) values(w,'Fictional rolled-back fiscal drafts'),(other,'Fictional draft isolation');
 insert into private.members values(w,a,'Fictional admin','admin',true,true),(w,o,'Fictional office','office',true,true);
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',sid)::text,true);perform public.device_snapshot(w,dev);
 perform public.management_command(w,dev,gen_random_uuid(),'fiscal_profile_save','{"revision":0,"reason":"Fictional profile","profile":{"country":"ES","legalForm":"company","territory":"common","sii":"no","clients":"mixed","turnover":"under_8m","taxSystem":"iva"}}');
 p:=jsonb_build_object('issuerNif','B12345678','installation','rolled-back-test','prefix','ENSAYO-A','expectedSequence',0,'expectedHash','','reason','Fictional draft',
  'issueDate','2026-10-07','recipient','{"name":"Fictional recipient","nif":"12345678Z"}'::jsonb,'lines',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'description','Fictional part','unitCents',3333,'quantityMilli',1500,'discountBps',1250,'taxBps',2100,'tax','iva','treatment','taxable')));
 r:=public.fiscal_draft_command(w,dev,cid,'fiscal_draft_append',p);
 if r->>'number'<>'1' or r->'emissionEnabled' is distinct from 'false'::jsonb or r->'transmissionEnabled' is distinct from 'false'::jsonb then raise exception 'Sandbox result invalid';end if;checks:=checks+1;
 select body into original from private.fiscal_draft_records where workshop_id=w and id=cid;
 if original->'calculation'->>'totalCents'<>'5294' then raise exception 'Server calculation differs';end if;checks:=checks+1;
 if public.fiscal_draft_command(w,dev,cid,'fiscal_draft_append',p)<>r then raise exception 'Retry changed result';end if;checks:=checks+1;
 failed:=false;begin perform public.fiscal_draft_command(w,dev,cid,'fiscal_draft_append',p||'{"reason":"Changed"}');exception when others then failed:=true;end;if not failed then raise exception 'Changed identity accepted';end if;checks:=checks+1;
 failed:=false;begin perform public.fiscal_draft_command(w,dev,gen_random_uuid(),'fiscal_draft_append',p);exception when others then failed:=true;end;if not failed then raise exception 'Stale head accepted';end if;checks:=checks+1;
 nextp:=p||jsonb_build_object('expectedSequence',1,'expectedHash',r->>'ledgerHash');
 failed:=false;begin perform public.fiscal_draft_command(w,dev,gen_random_uuid(),'fiscal_draft_append',nextp||'{"emissionEnabled":true}');exception when others then failed:=true;end;if not failed then raise exception 'Activation accepted';end if;checks:=checks+1;
 r:=public.fiscal_draft_command(w,dev,gen_random_uuid(),'fiscal_draft_append',nextp);
 if r->>'number'<>'2' or r->>'sequence'<>'2' then raise exception 'Number skipped after rejection';end if;checks:=checks+1;
 withdraw:=jsonb_build_object('issuerNif','B12345678','installation','rolled-back-test','expectedSequence',2,'expectedHash',r->>'ledgerHash','targetId',cid,'reason','Fictional withdrawal');
 r:=public.fiscal_draft_command(w,dev,gen_random_uuid(),'fiscal_draft_withdraw',withdraw);
 if r->>'number'<>'1' or (select body from private.fiscal_draft_records where workshop_id=w and id=cid)<>original then raise exception 'Withdrawal changed original';end if;checks:=checks+1;
 failed:=false;begin perform public.fiscal_draft_command(w,dev,gen_random_uuid(),'fiscal_draft_withdraw',withdraw||jsonb_build_object('expectedSequence',3,'expectedHash',r->>'ledgerHash'));exception when others then failed:=true;end;if not failed then raise exception 'Duplicate withdrawal accepted';end if;checks:=checks+1;
 failed:=false;begin update private.fiscal_draft_records set body='{}' where workshop_id=w and id=cid;exception when others then failed:=true;end;if not failed then raise exception 'Original updated';end if;checks:=checks+1;
 perform private.validate_fiscal_drafts(w);b:=public.export_workshop(w,dev);
 if b->>'databaseVersion'<>'14' or jsonb_array_length(b->'tables'->'fiscal_draft_records')<>3 or jsonb_array_length(b->'tables'->'fiscal_draft_heads')<>1 or jsonb_array_length(b->'tables'->'fiscal_draft_series')<>1 then raise exception 'Backup incomplete';end if;checks:=checks+1;
 perform set_config('request.jwt.claim.sub',o::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',o,'session_id',osid)::text,true);perform public.device_snapshot(w,od);
 failed:=false;begin perform public.fiscal_drafts(w,od);exception when others then failed:=true;end;if not failed then raise exception 'Office read drafts';end if;checks:=checks+1;
 failed:=false;begin perform public.fiscal_draft_command(w,od,gen_random_uuid(),'fiscal_draft_append',nextp);exception when others then failed:=true;end;if not failed then raise exception 'Office wrote drafts';end if;checks:=checks+1;
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',sid)::text,true);
 failed:=false;begin perform public.fiscal_drafts(other,dev);exception when others then failed:=true;end;if not failed then raise exception 'Ledger crossed workshop';end if;checks:=checks+1;
 if has_function_privilege('anon','public.fiscal_drafts(uuid,uuid)','execute') or has_function_privilege('anon','public.fiscal_draft_command(uuid,uuid,uuid,text,jsonb)','execute') or has_function_privilege('authenticated','private.validate_fiscal_drafts(uuid)','execute') or has_table_privilege('authenticated','private.fiscal_draft_records','select') or has_table_privilege('authenticated','private.fiscal_draft_series','update') or has_table_privilege('authenticated','private.fiscal_draft_heads','update') then raise exception 'Private access exposed';end if;checks:=checks+1;
 delete from auth.sessions where id=sid;
 failed:=false;begin perform public.fiscal_draft_command(w,dev,cid,'fiscal_draft_append',p);exception when others then failed:=true;end;if not failed then raise exception 'Revoked retry accepted';end if;checks:=checks+1;
 perform set_config('tallerflow.fiscal_draft_checks',checks::text,true);
end $$;
select current_setting('tallerflow.fiscal_draft_checks')::int as checks_passed,'Hosted SQL; synthetic Auth; rollback; no HTTP, multiconnection race or fiscal service acceptance' as scope;
rollback;
