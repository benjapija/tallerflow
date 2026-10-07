begin;
create table private.case_library(
 workshop_id uuid not null references private.workshops(id), id uuid not null,
 data jsonb not null,
 source_order_id uuid generated always as ((data->>'sourceOrderId')::uuid) stored not null,
 primary key(workshop_id,id),
 foreign key(workshop_id,source_order_id) references private.orders(workshop_id,id),
 check(jsonb_typeof(data)='object' and data->>'id'=id::text and (data->>'revision')::bigint>=1 and jsonb_typeof(data->'versions')='array' and jsonb_array_length(data->'versions')>=1 and jsonb_typeof(data->'events')='array' and data ?& array['id','revision','authorId','sourceOrderId','versions','events','activeVersion','withdrawn'])
);
alter table private.case_library enable row level security;
revoke all on private.case_library from public,anon,authenticated;
create function private.case_evidence(d jsonb,v jsonb) returns boolean language sql immutable set search_path='' as $$
 select d is not null and not exists(
  select 1 from (values ('conclusionId','conclusion'),('verificationId','verification')) links(key,stage)
  where not exists(select 1 from jsonb_array_elements(coalesce(d->'diagnosisNotebook','[]')) e
   where e->>'id'=v->>links.key and e->>'stage'=links.stage and e->'confirmed'='true'::jsonb
    and not exists(select 1 from jsonb_array_elements(coalesce(d->'diagnosisNotebook','[]')) r where r->>'replacesId'=e->>'id' or r->>'withdrawsId'=e->>'id'))
 )
$$;
create function private.case_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb;c jsonb;before_value jsonb;previous private.command_receipts%rowtype;caseid uuid;sourceid uuid;d jsonb;v jsonb;content jsonb:='{}';key text;value_text text;version bigint;rev bigint;reason text;result jsonb;allowed text[];
begin
 m:=private.photo_device(w,dev);
 if not private.photo_files_ready(w) then raise exception 'Recover original files before new work';end if;
 perform 1 from private.workshops where id=w for update;
 if cid is null or jsonb_typeof(p) is distinct from 'object' then raise exception 'Command and payload required';end if;
 select * into previous from private.command_receipts where workshop_id=w and id=cid;
 if found then
  if previous.actor_id<>auth.uid() or previous.device_id<>dev or previous.action<>action or previous.payload<>p then raise exception 'Command ID reused';end if;return previous.result;
 end if;
 caseid:=(p->>'id')::uuid;
 if caseid is null then raise exception 'Case ID required';end if;
 select data into c from private.case_library where workshop_id=w and id=caseid for update;before_value:=c;
 if c is not null and m->>'role'='technician' and c->>'authorId'<>auth.uid()::text then raise exception 'Author or office required' using errcode='42501';end if;
 rev:=coalesce((c->>'revision')::bigint,0);
 if private.require_int(p->'revision',0,9007199254740991,'Revision')<>rev then raise exception 'Case revision conflict';end if;
 reason:=private.require_text(p->>'reason','Review reason',2000);
 if action='case_draft' then allowed:=array['id','revision','sourceOrderId','conclusionId','verificationId','content','reason'];
 elsif action='case_validate' then allowed:=array['id','revision','version','technicalConfirmed','privacyConfirmed','reason'];
 elsif action='case_withdraw' then allowed:=array['id','revision','reason'];
 else raise exception 'Unsupported case action';end if;
 if exists(select 1 from jsonb_object_keys(p) k where not k=any(allowed)) then raise exception 'Unsupported case fields';end if;
 sourceid:=coalesce((c->>'sourceOrderId')::uuid,(p->>'sourceOrderId')::uuid);
 select data into d from private.orders where workshop_id=w and id=sourceid;
 if d is null or (m->>'role'='technician' and not exists(select 1 from jsonb_array_elements(d->'tasks') t where t->'assignees' ? auth.uid()::text)) then raise exception 'Assigned source order or office required' using errcode='42501';end if;
 if c is null then c:=jsonb_build_object('id',caseid,'revision',0,'authorId',auth.uid(),'sourceOrderId',sourceid,'versions','[]'::jsonb,'events','[]'::jsonb,'activeVersion',null,'withdrawn',false);end if;
 if action='case_draft' then
  if (p->>'sourceOrderId')::uuid is distinct from sourceid then raise exception 'Original source order must remain';end if;
  if jsonb_typeof(p->'content') is distinct from 'object' or (select count(*) from jsonb_object_keys(p->'content'))<>11 or exists(select 1 from jsonb_object_keys(p->'content') k where not k=any(array['title','vehicle','engine','symptom','dtcs','checks','result','conclusion','intervention','verification','sources'])) then raise exception 'Technical content fields required';end if;
  foreach key in array array['title','vehicle','engine','symptom','dtcs','checks','result','conclusion','intervention','verification','sources'] loop
   if jsonb_typeof(p->'content'->key) is distinct from 'string' then raise exception 'Technical text required';end if;
   value_text:=btrim(p->'content'->>key);
   if length(value_text)>(case when key in ('title','vehicle','engine','dtcs') then 500 else 4000 end) or (key not in ('dtcs','sources') and length(value_text)=0) then raise exception 'Complete technical content';end if;
   content:=content||jsonb_build_object(key,value_text);
  end loop;
  version:=jsonb_array_length(c->'versions')+1;
  v:=jsonb_build_object('version',version,'content',content,'conclusionId',(p->>'conclusionId')::uuid,'verificationId',(p->>'verificationId')::uuid,'actorId',auth.uid(),'at',now());
  if not private.case_evidence(d,v) then raise exception 'Current confirmed conclusion and verification required';end if;
  c:=jsonb_set(c,'{versions}',c->'versions'||jsonb_build_array(v));
 elsif action='case_validate' then
  v:=c->'versions'->-1;version:=private.require_int(p->'version',1,9007199254740991,'Version');
  if v is null or version<>(v->>'version')::bigint then raise exception 'Validate latest draft';end if;
  if p->'technicalConfirmed' is distinct from 'true'::jsonb or p->'privacyConfirmed' is distinct from 'true'::jsonb then raise exception 'Human technical and privacy review required';end if;
  if not private.case_evidence(d,v) then raise exception 'Source evidence needs review';end if;
  c:=c||jsonb_build_object('activeVersion',version,'withdrawn',false);
 else
  version:=(c->>'activeVersion')::bigint;
  if version is null or c->'withdrawn'='true'::jsonb then raise exception 'Current published case required';end if;
  c:=c||jsonb_build_object('withdrawn',true);
 end if;
 c:=c||jsonb_build_object('revision',rev+1,'events',c->'events'||jsonb_build_array(jsonb_build_object('id',cid,'kind',action,'version',version,'reason',reason,'actorId',auth.uid(),'actorName',m->>'name','at',now())));
 insert into private.case_library(workshop_id,id,data) values(w,caseid,c) on conflict(workshop_id,id) do update set data=excluded.data;
 result:=jsonb_build_object('saved',true,'revision',rev+1);
 insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,result);
 insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,before_data,after_data) values(w,auth.uid(),cid,sourceid,action,before_value,c);
 return result;
end $$;
create function public.case_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.case_command($1,$2,$3,$4,$5) $$;
alter function private.snapshot(uuid) rename to snapshot_before_cases;
create function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;r jsonb;c jsonb;published jsonb;source jsonb;rows jsonb:='[]';needs_review boolean;
begin
 m:=private.membership(w);r:=private.snapshot_before_cases(w);
 for c in select data from private.case_library where workshop_id=w order by id loop
  select x into published from jsonb_array_elements(c->'versions') x where x->>'version'=c->>'activeVersion';
  select data into source from private.orders where workshop_id=w and id=(c->>'sourceOrderId')::uuid;
  needs_review:=published is not null and not private.case_evidence(source,published);
  if m->>'role' in ('admin','office') or c->>'authorId'=auth.uid()::text then rows:=rows||jsonb_build_array(c||jsonb_build_object('editable',true,'needsReview',needs_review));
  elsif published is not null and c->'withdrawn'='false'::jsonb then
   rows:=rows||jsonb_build_array(jsonb_build_object('id',c->'id','revision',c->'revision','activeVersion',c->'activeVersion','withdrawn',false,'editable',false,'needsReview',needs_review,'versions',jsonb_build_array(jsonb_build_object('version',published->'version','content',published->'content')),'events','[]'::jsonb));
  end if;
 end loop;
 return r||jsonb_build_object('caseLibrary',rows);
end $$;
alter function private.backup_tables() rename to backup_tables_before_cases;
create function private.backup_tables() returns text[] language sql immutable set search_path='' as $$ select private.backup_tables_before_cases()||array['case_library']::text[] $$;
alter function private.export_workshop(uuid,uuid) rename to export_workshop_before_cases;
create function private.export_workshop(w uuid,dev uuid) returns jsonb language sql security definer set search_path='' as $$ select private.export_workshop_before_cases(w,dev)||jsonb_build_object('databaseVersion',9) $$;
alter function private.restore_workshop(uuid,uuid,uuid,jsonb) rename to restore_workshop_before_cases;
create function private.restore_workshop(w uuid,dev uuid,rid uuid,a jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare normalized jsonb:=a;
begin
 perform private.backup_admin(w,dev);
 if exists(select 1 from private.case_library where workshop_id=w) and not exists(select 1 from private.restores where workshop_id=w and id=rid) then raise exception 'Restore requires an empty isolated workshop with no case records';end if;
 if a->>'databaseVersion'='9' then
  if jsonb_typeof(a->'tables'->'case_library') is distinct from 'array' then raise exception 'Case library table missing';end if;
  normalized:=a||jsonb_build_object('databaseVersion',8);
 elsif a->>'databaseVersion' in ('2','3','4','5','6','7','8') then
  normalized:=jsonb_set(a,'{tables,case_library}',coalesce(a->'tables'->'case_library','[]'));
 end if;
 return private.restore_workshop_before_cases(w,dev,rid,normalized);
end $$;
revoke all on function private.case_evidence(jsonb,jsonb),private.case_command(uuid,uuid,uuid,text,jsonb),public.case_command(uuid,uuid,uuid,text,jsonb),private.snapshot_before_cases(uuid),private.snapshot(uuid),private.backup_tables_before_cases(),private.backup_tables(),private.export_workshop_before_cases(uuid,uuid),private.export_workshop(uuid,uuid),private.restore_workshop_before_cases(uuid,uuid,uuid,jsonb),private.restore_workshop(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.case_command(uuid,uuid,uuid,text,jsonb),public.case_command(uuid,uuid,uuid,text,jsonb),private.snapshot(uuid),private.export_workshop(uuid,uuid),private.restore_workshop(uuid,uuid,uuid,jsonb) to authenticated;
commit;
