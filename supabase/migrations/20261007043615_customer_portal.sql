begin;
create table private.portal_grants(
 workshop_id uuid not null references private.workshops(id),id uuid not null unique,
 order_id uuid not null,owner_id uuid not null,quote_id uuid not null,quote_version bigint not null check(quote_version>0),
 token_hash text not null check(token_hash~'^[a-f0-9]{64}$'),code_hash text not null check(code_hash~'^[a-f0-9]{64}$'),
 expires_at timestamptz not null,created_at timestamptz not null default now(),created_by uuid not null references auth.users(id),
 verification_evidence text not null,photo_ids jsonb not null check(jsonb_typeof(photo_ids)='array'),document_ids jsonb not null check(jsonb_typeof(document_ids)='array'),
 failed_attempts int not null default 0 check(failed_attempts between 0 and 5),revoked_at timestamptz,revocation_reason text,
 restored boolean not null default false,
 primary key(workshop_id,id),foreign key(workshop_id,order_id) references private.orders(workshop_id,id)
);
create table private.portal_receipts(
 workshop_id uuid not null,grant_id uuid not null,id uuid not null,action text not null,payload jsonb not null,result jsonb not null,
 primary key(workshop_id,id),foreign key(workshop_id,grant_id) references private.portal_grants(workshop_id,id)
);
alter table private.portal_grants enable row level security;alter table private.portal_receipts enable row level security;
revoke all on private.portal_grants,private.portal_receipts from public,anon,authenticated;
create function private.portal_command(w uuid,dev uuid,cid uuid,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb;d jsonb;rev bigint;g private.portal_grants%rowtype;previous private.command_receipts%rowtype;q jsonb;gid uuid;expires timestamptz;v jsonb;result jsonb;reason text;
begin
 m:=private.photo_device(w,dev);if m->>'role' not in ('admin','office') then raise exception 'Office permission required' using errcode='42501';end if;
 if not private.photo_files_ready(w) then raise exception 'Recover original files before new work';end if;
 perform 1 from private.workshops where id=w for update;
 if cid is null or jsonb_typeof(p) is distinct from 'object' then raise exception 'Command and payload required';end if;
 select * into previous from private.command_receipts where workshop_id=w and id=cid;
 if found then if previous.actor_id<>auth.uid() or previous.device_id<>dev or previous.action<>action or previous.payload<>p then raise exception 'Command ID reused';end if;return previous.result;end if;
 if action='portal_configure' then
  if m->>'role'<>'admin' or exists(select 1 from jsonb_object_keys(p) k where not k=any(array['url','reason'])) then raise exception 'Administrator portal configuration required' using errcode='42501';end if;
  reason:=private.require_text(p->>'reason','Reason',2000);
  if coalesce(p->>'url','')<>'' and (length(p->>'url')>500 or p->>'url' !~ '^https://[a-zA-Z0-9.-]+(:[0-9]+)?(/[a-zA-Z0-9_./-]*)?$') then raise exception 'HTTPS portal address required without credentials, query or fragment';end if;
  update private.workshops set settings=settings||jsonb_build_object('portalBaseUrl',coalesce(p->>'url','')) where id=w;
  result:='{"saved":true}';insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,result);
  insert into private.audit(workshop_id,actor_id,operation_id,kind,after_data) values(w,auth.uid(),cid,action,p);return result;
 end if;
 gid:=(p->>'id')::uuid;reason:=private.require_text(p->>'reason','Reason',2000);
 if gid is null then raise exception 'Grant ID required';end if;
 if action='portal_create' then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','orderId','revision','quoteId','quoteVersion','tokenHash','codeHash','expiresAt','recipientConfirmed','verificationEvidence','photoIds','documentIds','reason'])) then raise exception 'Unsupported portal fields';end if;
  select data,revision into d,rev from private.orders where workshop_id=w and id=(p->>'orderId')::uuid;
  if d is null or private.require_int(p->'revision',0,9007199254740991,'Revision')<>rev then raise exception 'Review current repair order';end if;
  select x into q from jsonb_array_elements(coalesce(d->'quoteLedger'->'versions','[]')) x where x->>'id'=p->>'quoteId' and x->>'version'=p->>'quoteVersion';
  if q is null or q->'ownerId' is distinct from d->'ownerId' or q->'ownerId'='null'::jsonb or not exists(select 1 from private.vehicle_profiles where workshop_id=w and vehicle_id=(d->>'vehicleId')::uuid and owner_id=(d->>'ownerId')::uuid) then raise exception 'Verify original and current recipient';end if;
  if p->'recipientConfirmed' is distinct from 'true'::jsonb then raise exception 'Personally verify recipient and shared evidence';end if;
  expires:=(p->>'expiresAt')::timestamptz;if expires is null or expires<=now() or expires>now()+interval '7 days' then raise exception 'Temporary access of at most seven days required';end if;
  if jsonb_typeof(p->'photoIds') is distinct from 'array' or jsonb_typeof(p->'documentIds') is distinct from 'array' or jsonb_array_length(p->'photoIds')>50 or jsonb_array_length(p->'documentIds')>50 then raise exception 'Select at most fifty photos and documents';end if;
  for v in select value from jsonb_array_elements(p->'photoIds') loop
   if jsonb_typeof(v)<>'string' or not exists(select 1 from private.order_photos where workshop_id=w and id=(v#>>'{}')::uuid and order_id=(p->>'orderId')::uuid and status='attached' and verified_at is not null and not recovery) then raise exception 'Verified evidence from same repair required';end if;
  end loop;
  for v in select value from jsonb_array_elements(p->'documentIds') loop
   if jsonb_typeof(v)<>'string' or not exists(select 1 from private.documents where workshop_id=w and id=(v#>>'{}')::uuid and order_id=(p->>'orderId')::uuid and recipient_id=(d->>'ownerId')::uuid) then raise exception 'Authorized document for same original recipient required';end if;
  end loop;
  insert into private.portal_grants(workshop_id,id,order_id,owner_id,quote_id,quote_version,token_hash,code_hash,expires_at,created_by,verification_evidence,photo_ids,document_ids)
   values(w,gid,(p->>'orderId')::uuid,(d->>'ownerId')::uuid,(q->>'id')::uuid,(q->>'version')::bigint,p->>'tokenHash',p->>'codeHash',expires,auth.uid(),private.require_text(p->>'verificationEvidence','Recipient verification evidence',2000),p->'photoIds',p->'documentIds');
 elsif action='portal_revoke' then
  if exists(select 1 from jsonb_object_keys(p) k where not k=any(array['id','reason'])) then raise exception 'Unsupported revocation fields';end if;
  select * into g from private.portal_grants where workshop_id=w and id=gid for update;if not found then raise exception 'Portal access outside workshop';end if;
  update private.portal_grants set revoked_at=coalesce(revoked_at,now()),revocation_reason=reason where workshop_id=w and id=gid;
 else raise exception 'Unsupported portal action';end if;
 result:=jsonb_build_object('saved',true,'id',gid);
 insert into private.command_receipts values(w,cid,auth.uid(),dev,action,p,result);
 insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,after_data) values(w,auth.uid(),cid,coalesce((p->>'orderId')::uuid,g.order_id),action,jsonb_build_object('grantId',gid,'reason',reason));return result;
end $$;
create function public.portal_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.portal_command($1,$2,$3,$4,$5) $$;
-- A second, independent code is necessary. Only server code can call this API;
-- clients never submit hashes, service credentials, Auth identities or a plate.
create function private.portal_access(gid uuid,token text,code text,action text,cid uuid,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare g private.portal_grants%rowtype;d jsonb;before_value jsonb;rev bigint;q jsonb;current_version bigint;decision jsonb;last_decision jsonb;previous private.portal_receipts%rowtype;result jsonb;photo private.order_photos%rowtype;docs jsonb;photos jsonb;lines jsonb;decisions jsonb;
begin
 select * into g from private.portal_grants where id=gid;
 if not found or token is distinct from g.token_hash then return '{"error":"access"}';end if;
 perform 1 from private.workshops where id=g.workshop_id for update;
 select * into g from private.portal_grants where id=gid for update;
 if code is distinct from g.code_hash then
  update private.portal_grants set failed_attempts=least(failed_attempts+1,5) where id=gid;return '{"error":"access"}';
 end if;
 if g.restored or g.revoked_at is not null or g.failed_attempts>=5 or g.expires_at<=now() or not exists(select 1 from private.members where workshop_id=g.workshop_id and user_id=g.created_by and role in ('admin','office') and active) then return '{"error":"access"}';end if;
 select data,revision into d,rev from private.orders where workshop_id=g.workshop_id and id=g.order_id for update;
 if d is null or d->>'ownerId' is distinct from g.owner_id::text or not exists(select 1 from private.vehicle_profiles where workshop_id=g.workshop_id and vehicle_id=(d->>'vehicleId')::uuid and owner_id=g.owner_id) then return '{"error":"access"}';end if;
 select x into q from jsonb_array_elements(d->'quoteLedger'->'versions') x where x->>'id'=g.quote_id::text and (x->>'version')::bigint=g.quote_version;
 if q is null or q->>'ownerId' is distinct from g.owner_id::text then return '{"error":"access"}';end if;
 select max((x->>'version')::bigint) into current_version from jsonb_array_elements(d->'quoteLedger'->'versions') x where x->>'id'=g.quote_id::text;
 if action='decide' then
  if cid is null or jsonb_typeof(p) is distinct from 'object' or exists(select 1 from jsonb_object_keys(p) k where k<>'decisions') then raise exception 'Decision identity and selected lines required';end if;
  select * into previous from private.portal_receipts where workshop_id=g.workshop_id and id=cid;
  if found then if previous.grant_id<>gid or previous.action<>action or previous.payload<>p then raise exception 'Decision ID reused';end if;return previous.result;end if;
  if current_version<>g.quote_version or (q->>'validUntil')::timestamptz<=now() or (d->'document' is not null and d->'document'<>'null'::jsonb) then raise exception 'Quote version unavailable for decision';end if;
  if not private.photo_files_ready(g.workshop_id) then raise exception 'Recover original files before decisions';end if;
  before_value:=d;
  decision:=jsonb_build_object('quoteId',g.quote_id,'version',g.quote_version,'customer',q->'customer','channel','written','evidence','Destinatario verificado por oficina y código independiente; acceso '||gid::text,'reason','Decisión del destinatario en portal','decisions',p->'decisions');
  d:=private.decide_quote(d,decision,g.owner_id,cid,now());
  last_decision:=(d->'quoteLedger'->'decisions'->-1)||jsonb_build_object('channel','portal','actorType','customer','recipientId',g.owner_id,'portalGrantId',gid,'verification','office_checked_separate_code');
  d:=jsonb_set(d,'{quoteLedger,decisions}',(d->'quoteLedger'->'decisions')- (jsonb_array_length(d->'quoteLedger'->'decisions')-1)||jsonb_build_array(last_decision));
  select jsonb_agg(case when t->'authorization'->>'decisionId'=cid::text then jsonb_set(t,'{authorization}',t->'authorization'||jsonb_build_object('channel','portal','actorType','customer','recipientId',g.owner_id,'portalGrantId',gid)) else t end) into lines from jsonb_array_elements(d->'tasks') t;
  d:=jsonb_set(d,'{tasks}',lines);
  update private.orders set data=d,revision=rev+1 where workshop_id=g.workshop_id and id=g.order_id;
  update private.close_requests set status='invalidated' where workshop_id=g.workshop_id and order_id=g.order_id and status='active';
  result:=jsonb_build_object('accepted',true,'version',g.quote_version,'decisionId',cid);
  insert into private.portal_receipts values(g.workshop_id,gid,cid,action,p,result);
  insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,before_data,after_data) values(g.workshop_id,g.owner_id,cid,g.order_id,'portal_decision',before_value,d);
  return result;
 elsif action='photo' then
  if jsonb_typeof(p) is distinct from 'object' or exists(select 1 from jsonb_object_keys(p) k where k<>'photoId') or not g.photo_ids ? (p->>'photoId') then return '{"error":"access"}';end if;
  select * into photo from private.order_photos where workshop_id=g.workshop_id and id=(p->>'photoId')::uuid and order_id=g.order_id and status='attached' and verified_at is not null and not recovery;
  if not found then return '{"error":"access"}';end if;
  return jsonb_build_object('id',photo.id,'path',photo.path,'sha256',photo.sha256,'size',photo.byte_size);
 elsif action<>'read' or p<>'{}'::jsonb then raise exception 'Unsupported portal action';end if;
 select coalesce(jsonb_agg(l-'taskId'),'[]') into lines from jsonb_array_elements(q->'lines') l;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'type',x.type,'version',x.version,'issuedAt',x.issued_at,'snapshot',private.redact_costs(x.snapshot))),'[]') into docs from private.documents x where x.workshop_id=g.workshop_id and x.order_id=g.order_id and x.recipient_id=g.owner_id and g.document_ids ? x.id::text;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'caption',x.caption,'size',x.byte_size,'sha256',x.sha256)),'[]') into photos from private.order_photos x where x.workshop_id=g.workshop_id and x.order_id=g.order_id and g.photo_ids ? x.id::text and x.status='attached' and x.verified_at is not null and not x.recovery;
 select coalesce(jsonb_agg(jsonb_build_object('id',x->'id','at',x->'at','decisions',x->'decisions')),'[]') into decisions from jsonb_array_elements(coalesce(d->'quoteLedger'->'decisions','[]')) x where x->>'quoteId'=g.quote_id::text and (x->>'version')::bigint=g.quote_version;
 return jsonb_build_object('workshop',(select name from private.workshops where id=g.workshop_id),'orderNumber',d->'number','status',d->'status','expiresAt',g.expires_at,'quote',jsonb_build_object('id',q->'id','version',q->'version','title',q->'title','customer',q->'customer','at',q->'at','validUntil',q->'validUntil','lines',lines,'totalCents',q->'totalCents','type',q->'type'),'canDecide',current_version=g.quote_version and (q->>'validUntil')::timestamptz>now() and (d->'document' is null or d->'document'='null'::jsonb),'decisions',decisions,'photos',photos,'documents',docs);
end $$;
create function public.customer_portal(grant_id uuid,token_hash text,code_hash text,action text,command_id uuid,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.portal_access($1,$2,$3,$4,$5,$6) $$;
alter function private.snapshot(uuid) rename to snapshot_before_portal;
create function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;r jsonb;begin
 m:=private.membership(w);r:=private.snapshot_before_portal(w);
 if m->>'role' in ('admin','office') then r:=r||jsonb_build_object('portalDocuments',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'orderId',x.order_id,'type',x.type,'version',x.version,'issuedAt',x.issued_at)) from private.documents x join private.orders o on o.workshop_id=x.workshop_id and o.id=x.order_id where x.workshop_id=w and x.recipient_id=(o.data->>'ownerId')::uuid),'[]'),'portalGrants',coalesce((select jsonb_agg(jsonb_build_object('id',id,'orderId',order_id,'quoteId',quote_id,'quoteVersion',quote_version,'expiresAt',expires_at,'createdAt',created_at,'revokedAt',revoked_at,'restored',restored,'locked',failed_attempts>=5)) from private.portal_grants where workshop_id=w),'[]'));end if;
 return r;
end $$;
alter function private.backup_tables() rename to backup_tables_before_portal;
create function private.backup_tables() returns text[] language sql immutable set search_path='' as $$ select private.backup_tables_before_portal()||array['portal_grants','portal_receipts']::text[] $$;
alter function private.export_workshop(uuid,uuid) rename to export_workshop_before_portal;
create function private.export_workshop(w uuid,dev uuid) returns jsonb language sql security definer set search_path='' as $$ select private.export_workshop_before_portal(w,dev)||jsonb_build_object('databaseVersion',10) $$;
alter function private.restore_workshop(uuid,uuid,uuid,jsonb) rename to restore_workshop_before_portal;
create function private.restore_workshop(w uuid,dev uuid,rid uuid,a jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare normalized jsonb:=a;rows jsonb;begin
 perform private.backup_admin(w,dev);
 if exists(select 1 from private.portal_grants where workshop_id=w) and not exists(select 1 from private.restores where workshop_id=w and id=rid) then raise exception 'Restore requires an empty isolated workshop with no portal grants';end if;
 if a->>'databaseVersion'='10' then
  if jsonb_typeof(a->'tables'->'portal_grants') is distinct from 'array' or jsonb_typeof(a->'tables'->'portal_receipts') is distinct from 'array' then raise exception 'Portal tables missing';end if;
  normalized:=a||jsonb_build_object('databaseVersion',9);
  select coalesce(jsonb_agg(x||jsonb_build_object('restored',true)),'[]') into rows from jsonb_array_elements(a->'tables'->'portal_grants') x;
  normalized:=jsonb_set(normalized,'{tables,portal_grants}',rows);
 elsif a->>'databaseVersion' in ('2','3','4','5','6','7','8','9') then
  normalized:=jsonb_set(jsonb_set(a,'{tables,portal_grants}','[]'),'{tables,portal_receipts}','[]');
 end if;
 return private.restore_workshop_before_portal(w,dev,rid,normalized);
end $$;
revoke all on function private.portal_command(uuid,uuid,uuid,text,jsonb),public.portal_command(uuid,uuid,uuid,text,jsonb),private.portal_access(uuid,text,text,text,uuid,jsonb),public.customer_portal(uuid,text,text,text,uuid,jsonb),private.snapshot_before_portal(uuid),private.snapshot(uuid),private.backup_tables_before_portal(),private.backup_tables(),private.export_workshop_before_portal(uuid,uuid),private.export_workshop(uuid,uuid),private.restore_workshop_before_portal(uuid,uuid,uuid,jsonb),private.restore_workshop(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.portal_command(uuid,uuid,uuid,text,jsonb),public.portal_command(uuid,uuid,uuid,text,jsonb),private.snapshot(uuid),private.export_workshop(uuid,uuid),private.restore_workshop(uuid,uuid,uuid,jsonb) to authenticated;
grant execute on function private.portal_access(uuid,text,text,text,uuid,jsonb),public.customer_portal(uuid,text,text,text,uuid,jsonb) to service_role;
commit;
