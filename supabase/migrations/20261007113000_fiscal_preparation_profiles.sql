-- Per-workshop preparation for Spain. This never enables fiscal emission.
begin;
create function private.normalize_fiscal_profile(v jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare choices jsonb:='{
 "legalForm":["unknown","sole_trader","company","attribution","other"],
 "territory":["unknown","common","canary","ceuta","melilla","navarra","alava","bizkaia","gipuzkoa"],
 "sii":["unknown","yes","no"],
 "clients":["unknown","individuals","business","public","mixed"],
 "turnover":["unknown","under_8m","over_8m"],
 "taxSystem":["unknown","iva","igic","ipsi","mixed","other"]
}'::jsonb; entry record; result jsonb;
begin
 if jsonb_typeof(v) is distinct from 'object' or v->>'country' is distinct from 'ES' then
  raise exception 'Invalid fiscal preparation profile';
 end if;
 if exists(select 1 from jsonb_object_keys(v) k where k not in
  ('country','legalForm','territory','sii','clients','turnover','taxSystem','profileVersion','emissionEnabled'))
  or (v ? 'profileVersion' and v->'profileVersion' is distinct from '1'::jsonb)
  or (v ? 'emissionEnabled' and v->'emissionEnabled' is distinct from 'false'::jsonb) then
  raise exception 'Preparation cannot enable emission or contain private credentials';
 end if;
 result:='{"country":"ES","profileVersion":1,"emissionEnabled":false}'::jsonb;
 for entry in select key,value from jsonb_each(choices) loop
  if jsonb_typeof(v->entry.key) is distinct from 'string' or not (entry.value ? (v->>entry.key)) then
   raise exception 'Invalid fiscal option: %',entry.key;
  end if;
  result:=result||jsonb_build_object(entry.key,v->entry.key);
 end loop;
 return result;
end $$;
revoke all on function private.normalize_fiscal_profile(jsonb) from public,anon,authenticated;

-- Delegate every existing action to its unchanged implementation.
alter function private.management_command(uuid,uuid,uuid,text,jsonb) rename to management_command_before_fiscal;
revoke all on function private.management_command_before_fiscal(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
create function private.management_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare member jsonb; prior private.command_receipts%rowtype; rev bigint; original jsonb; profile jsonb; result jsonb;
begin
 if action is distinct from 'fiscal_profile_save' then
  return private.management_command_before_fiscal(w,dev,cid,action,p);
 end if;
 member:=private.membership(w);
 if member->>'role' is distinct from 'admin' then raise exception 'Administrator required' using errcode='42501';end if;
 perform private.backup_admin(w,dev);
 select settings into original from private.workshops where id=w for update;
 if cid is null or jsonb_typeof(p) is distinct from 'object' then raise exception 'Command identity required';end if;
 select * into prior from private.command_receipts where workshop_id=w and id=cid;
 if found then
  if prior.actor_id is distinct from auth.uid() or prior.device_id is distinct from dev
   or prior.action is distinct from action or prior.payload is distinct from p then
   raise exception 'Command ID reused';
  end if;
  return prior.result;
 end if;
 select revision into rev from private.management_state where workshop_id=w;
 rev:=coalesce(rev,0);
 if private.require_int(p->'revision',0,9007199254740991,'Revision')<>rev then
  raise exception 'Configuration revision conflict; refresh and review';
 end if;
 perform private.require_text(p->>'reason','Reason');
 profile:=private.normalize_fiscal_profile(p->'profile');
 update private.workshops set settings=original||jsonb_build_object('fiscalProfile',profile) where id=w;
 insert into private.management_state values(w,rev+1) on conflict(workshop_id) do update set revision=excluded.revision;
 update private.close_requests set status='invalidated' where workshop_id=w and status='active';
 insert into private.audit(workshop_id,actor_id,operation_id,kind,before_data,after_data)
  values(w,auth.uid(),cid,action,original->'fiscalProfile',jsonb_build_object('value',profile,'reason',p->>'reason','revision',rev+1));
 result:=jsonb_build_object('saved',true,'revision',rev+1);
 insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,result);
 return result;
end $$;
create or replace function public.management_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select private.management_command(workshop_id,device_id,command_id,action,payload)
$$;
revoke all on function private.management_command(uuid,uuid,uuid,text,jsonb),public.management_command(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.management_command(uuid,uuid,uuid,text,jsonb),public.management_command(uuid,uuid,uuid,text,jsonb) to authenticated;
commit;
