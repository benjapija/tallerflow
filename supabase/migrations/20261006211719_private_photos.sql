-- Private, immutable photo files. Bytes are changed only through Storage API.
begin;
create table private.order_photos (
 workshop_id uuid not null, id uuid not null, order_id uuid not null,
 actor_id uuid not null, device_id uuid not null, original_device_id uuid not null,
 sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
 byte_size int not null check(byte_size between 1 and 4194304),
 mime text not null check(mime='image/jpeg'), caption text not null check(length(caption)<=2000),
 captured_at timestamptz not null, created_at timestamptz not null default now(),
 status text not null check(status in ('pending','attached','review','late','archived')),
 verified_at timestamptz, recovery boolean not null default false,
 restored boolean not null default false, restore_file_expected boolean not null default false,
 restore_upload_device_id uuid, restore_verified_at timestamptz,
 path text generated always as (workshop_id::text||'/'||order_id::text||'/'||id::text||'.jpg') stored,
 primary key(workshop_id,id), unique(path),
 foreign key(workshop_id,order_id) references private.orders(workshop_id,id),
 foreign key(workshop_id,device_id) references private.devices(workshop_id,id),
 foreign key(workshop_id,original_device_id) references private.devices(workshop_id,id),
 foreign key(actor_id) references auth.users(id)
);
create index order_photos_order on private.order_photos(workshop_id,order_id,status);
alter table private.order_photos enable row level security;
revoke all on private.order_photos from public,anon,authenticated;

create function private.photo_json(p private.order_photos) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('id',p.id,'orderId',p.order_id,'actorId',p.actor_id,'deviceId',p.device_id,
  'originalDeviceId',p.original_device_id,'sha256',p.sha256,'size',p.byte_size,'mime',p.mime,
  'caption',p.caption,'capturedAt',p.captured_at,'status',p.status,'path',p.path,
  'recovery',p.recovery,'restored',p.restored)
$$;

create function private.photo_device(w uuid,dev uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb; d private.devices%rowtype;
begin
 m:=private.membership(w);
 select * into d from private.devices where workshop_id=w and id=dev and user_id=auth.uid();
 if not found or d.retired_at is not null or d.auth_session_id is distinct from private.auth_session() then
  raise exception 'Active authenticated device required' using errcode='42501';
 end if;
 return m;
end $$;

create function private.photo_order_access(w uuid,oid uuid,uid uuid,office boolean) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from private.orders o where o.workshop_id=w and o.id=oid and
  (office or exists(select 1 from jsonb_array_elements(o.data->'tasks') t where t->'assignees' ? uid::text)))
$$;

create function private.photo_storage_access(bucket text,object_path text,writing boolean) returns boolean language plpgsql stable security definer set search_path='' as $$
declare p private.order_photos%rowtype; m jsonb; sid uuid; active_device uuid; office boolean;
begin
 if bucket<>'tallerflow-photos' or auth.uid() is null then return false;end if;
 select * into p from private.order_photos where path=object_path;
 if not found then return false;end if;
 m:=private.membership(p.workshop_id);sid:=private.auth_session();office:=m->>'role' in ('office','admin');
 select id into active_device from private.devices where workshop_id=p.workshop_id and user_id=auth.uid() and auth_session_id=sid and retired_at is null;
 if active_device is null then return false;end if;
 if writing then
  return (p.status='pending' and p.actor_id=auth.uid() and p.device_id=active_device and not p.restored
   and private.photo_order_access(p.workshop_id,p.order_id,auth.uid(),office))
   or (p.restored and m->>'role'='admin' and p.restore_upload_device_id=active_device and p.restore_verified_at is null);
 end if;
 return office or private.photo_order_access(p.workshop_id,p.order_id,auth.uid(),false)
  or (p.status='attached' and exists(select 1 from private.orders historical join private.orders current_order
    on current_order.workshop_id=historical.workshop_id and current_order.vehicle_id=historical.vehicle_id
    where historical.workshop_id=p.workshop_id and historical.id=p.order_id
    and exists(select 1 from jsonb_array_elements(current_order.data->'tasks') t where t->'assignees' ? auth.uid()::text)));
end $$;
create policy tallerflow_photo_read on storage.objects for select to authenticated
 using(storage.allow_any_operation(array['object.get_authenticated','object.get_authenticated_info','object.head_authenticated_info'])
  and private.photo_storage_access(bucket_id,name,false));
create policy tallerflow_photo_upload on storage.objects for insert to authenticated
 with check(private.photo_storage_access(bucket_id,name,true));
-- No UPDATE or DELETE: upsert and replacement of evidence remain denied.
revoke all on function private.photo_storage_access(text,text,boolean) from public,anon;
grant execute on function private.photo_storage_access(text,text,boolean) to authenticated;

create function private.photo_info(w uuid,dev uuid,pid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb;p private.order_photos%rowtype;
begin
 m:=private.photo_device(w,dev);
 select * into p from private.order_photos where workshop_id=w and id=pid;
 if not found or not private.photo_storage_access('tallerflow-photos',p.path,false) then
  raise exception 'Photo not available for this account' using errcode='42501';end if;
 if not (p.actor_id=auth.uid() and p.device_id=dev) and not (p.restored and m->>'role'='admin' and p.restore_upload_device_id=dev) then
  raise exception 'Photo upload belongs to another device' using errcode='42501';end if;
 return private.photo_json(p)||jsonb_build_object('sessionId',private.auth_session(),'userId',auth.uid(),
  'filePresent',exists(select 1 from storage.objects where bucket_id='tallerflow-photos' and name=p.path));
end $$;

create function private.photo_command(w uuid,dev uuid,cid uuid,action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m jsonb; p private.order_photos%rowtype; previous private.command_receipts%rowtype;
 oid uuid;pid uuid;orig uuid;captured timestamptz;r jsonb;d jsonb;office boolean;rev bigint;
begin
 m:=private.photo_device(w,dev);office:=m->>'role' in ('office','admin');
 perform 1 from private.workshops where id=w for update;
 select * into previous from private.command_receipts where workshop_id=w and id=cid;
 if found then
  if previous.actor_id<>auth.uid() or previous.device_id<>dev or previous.action<>action or previous.payload<>payload then raise exception 'Command ID reused';end if;
  return previous.result;
 end if;
 if jsonb_typeof(payload) is distinct from 'object' or cid is null then raise exception 'Invalid photo request';end if;
 pid:=(payload->>'id')::uuid;
 if action='photo_prepare' then
  if exists(select 1 from jsonb_object_keys(payload) k where k not in ('id','orderId','sha256','size','mime','caption','capturedAt','originalDeviceId')) then raise exception 'Unexpected photo field';end if;
  oid:=(payload->>'orderId')::uuid;orig:=(payload->>'originalDeviceId')::uuid;captured:=(payload->>'capturedAt')::timestamptz;
  if pid is null or oid is null or orig is null or payload->>'sha256' is null or payload->>'mime' is null or length(trim(coalesce(payload->>'caption','')))=0 or captured is null
   or captured>now()+interval '2 minutes' or captured<'2000-01-01' then raise exception 'Invalid photo metadata';end if;
  if jsonb_typeof(payload->'size') is distinct from 'number' or payload->>'size' !~ '^[0-9]+$' then raise exception 'Invalid photo size';end if;
  if not private.photo_order_access(w,oid,auth.uid(),office) then raise exception 'Order permission required' using errcode='42501';end if;
  select data into d from private.orders where workshop_id=w and id=oid;
  if d->'document' is not null and d->'document'<>'null'::jsonb and orig=dev then raise exception 'Issued order cannot receive photos';end if;
  if orig<>dev and not exists(select 1 from private.devices where workshop_id=w and id=orig and user_id=auth.uid() and retired_at is not null) then
   raise exception 'Recovery requires an original retired device of this account' using errcode='42501';end if;
  select * into p from private.order_photos where workshop_id=w and id=pid for update;
  if found then
   if p.actor_id<>auth.uid() or p.order_id<>oid or p.original_device_id<>orig or p.sha256<>payload->>'sha256' or p.byte_size<>(payload->>'size')::int or p.mime<>payload->>'mime' or p.caption<>payload->>'caption' or p.captured_at<>captured or p.restored then raise exception 'Photo ID reused';end if;
   if p.device_id<>dev then
    if not exists(select 1 from private.devices where workshop_id=w and id=p.device_id and user_id=auth.uid() and retired_at is not null) then raise exception 'Original device must be retired' using errcode='42501';end if;
    update private.order_photos set device_id=dev,recovery=true,status=case when status='pending' and verified_at is not null then 'review' else status end where workshop_id=w and id=pid returning * into p;
   end if;
  else
   if (select count(*) from private.order_photos where workshop_id=w and order_id=oid)>=500 then raise exception 'Review the number of photos in this order';end if;
   insert into private.order_photos(workshop_id,id,order_id,actor_id,device_id,original_device_id,sha256,byte_size,mime,caption,captured_at,status,recovery)
    values(w,pid,oid,auth.uid(),dev,orig,payload->>'sha256',(payload->>'size')::int,payload->>'mime',payload->>'caption',captured,'pending',orig<>dev) returning * into p;
  end if;
  insert into private.order_devices(workshop_id,order_id,device_id) values(w,oid,dev) on conflict do nothing;
  perform private.invalidate_close(w,oid);
  r:=private.photo_json(p);
 elsif action in ('photo_archive','photo_approve') then
  if exists(select 1 from jsonb_object_keys(payload) k where k not in ('id','reason','revision')) or length(trim(coalesce(payload->>'reason','')))=0 or length(payload->>'reason')>2000 then raise exception 'Photo review reason required';end if;
  select * into p from private.order_photos where workshop_id=w and id=pid for update;
  if not found or not private.photo_order_access(w,p.order_id,auth.uid(),office) then raise exception 'Photo permission required' using errcode='42501';end if;
  if action='photo_archive' then
   if p.status not in ('pending','review','late') or not (office or p.actor_id=auth.uid()) then raise exception 'Only pending photos can be archived';end if;
   update private.order_photos set status='archived' where workshop_id=w and id=pid returning * into p;
  else
   if not office then raise exception 'Office review required' using errcode='42501';end if;
   if p.status not in ('review','late') or (p.restored and p.restore_verified_at is null) or (not p.restored and p.verified_at is null) then raise exception 'Verified recovered photo required';end if;
   select data,revision into d,rev from private.orders where workshop_id=w and id=p.order_id for update;
   if (d->'document' is not null and d->'document'<>'null'::jsonb) or (payload->>'revision')::bigint is distinct from rev then raise exception 'Issued order or revision conflict';end if;
   update private.order_photos set status='attached' where workshop_id=w and id=pid returning * into p;
   d:=d||jsonb_build_object('photos',coalesce(d->'photos','[]'::jsonb)||jsonb_build_array(private.photo_json(p)), 'revision',rev+1);
   update private.orders set data=d,revision=revision+1 where workshop_id=w and id=p.order_id;
  end if;
  perform private.invalidate_close(w,p.order_id);r:=private.photo_json(p);
 else raise exception 'Unknown photo action';end if;
 insert into private.command_receipts values(w,cid,auth.uid(),dev,action,payload,r);
 insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,after_data) values(w,auth.uid(),cid,p.order_id,action,jsonb_build_object('photo',r,'reason',payload->>'reason'));
 return r;
end $$;

-- Only the trusted verifier may call this after downloading and hashing bytes.
create function private.photo_finalize(w uuid,dev uuid,pid uuid,uid uuid,sid uuid,hash text,size int) returns jsonb language plpgsql security definer set search_path='' as $$
declare p private.order_photos%rowtype; m private.members%rowtype; d jsonb;office boolean;rev bigint;
begin
 perform 1 from private.workshops where id=w for update;
 if not exists(select 1 from auth.sessions where id=sid and user_id=uid) or not exists(select 1 from private.devices where workshop_id=w and id=dev and user_id=uid and auth_session_id=sid and retired_at is null) then raise exception 'Session or device revoked' using errcode='42501';end if;
 select * into m from private.members where workshop_id=w and user_id=uid and active;
 if not found then raise exception 'Membership revoked' using errcode='42501';end if;office:=m.role in ('office','admin');
 select * into p from private.order_photos where workshop_id=w and id=pid for update;
 if not found or p.sha256<>hash or p.byte_size<>size then raise exception 'Photo hash or size mismatch';end if;
 if not exists(select 1 from storage.objects where bucket_id='tallerflow-photos' and name=p.path) then raise exception 'Storage object missing';end if;
 if p.restored then
  if m.role<>'admin' or p.restore_upload_device_id<>dev then raise exception 'Restore administrator required' using errcode='42501';end if;
  if p.restore_verified_at is not null then return private.photo_json(p);end if;
  update private.order_photos set restore_verified_at=now(),restore_file_expected=true where workshop_id=w and id=pid returning * into p;
  insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,after_data) values(w,uid,pid,p.order_id,'photo_file_restored',private.photo_json(p));
  return private.photo_json(p);
 end if;
 if p.actor_id<>uid or p.device_id<>dev or not private.photo_order_access(w,p.order_id,uid,office) then raise exception 'Photo permission revoked' using errcode='42501';end if;
 if p.status<>'pending' then return private.photo_json(p);end if;
 select data,revision into d,rev from private.orders where workshop_id=w and id=p.order_id for update;
 update private.order_photos set verified_at=now(),status=case
  when d->'document' is not null and d->'document'<>'null'::jsonb then 'late'
  when p.recovery then 'review' else 'attached' end where workshop_id=w and id=pid returning * into p;
 if p.status='attached' then
  d:=d||jsonb_build_object('photos',coalesce(d->'photos','[]'::jsonb)||jsonb_build_array(private.photo_json(p)), 'revision',rev+1);
  update private.orders set data=d,revision=revision+1 where workshop_id=w and id=p.order_id;
 end if;
 perform private.invalidate_close(w,p.order_id);
 insert into private.audit(workshop_id,actor_id,operation_id,order_id,kind,after_data) values(w,uid,pid,p.order_id,'photo_verified',private.photo_json(p));
 return private.photo_json(p);
end $$;

create function private.photo_files_ready(w uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from private.order_photos p where workshop_id=w and p.restored and p.restore_file_expected and p.restore_verified_at is null)
$$;
create function private.photo_close_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if new.status='active' and (not private.photo_files_ready(new.workshop_id) or exists(select 1 from private.order_photos where workshop_id=new.workshop_id and order_id=new.order_id and status in ('pending','review'))) then
  raise exception 'Photos pending upload or office review';end if;
 return new;
end $$;
create trigger photos_before_closure before insert on private.close_requests for each row execute function private.photo_close_guard();
create function private.photo_document_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if new.type='work_note' and (not private.photo_files_ready(new.workshop_id) or exists(select 1 from private.order_photos where workshop_id=new.workshop_id and order_id=new.order_id and status in ('pending','review'))) then raise exception 'Photos pending upload or review';end if;
 return new;
end $$;
create trigger photos_before_document before insert on private.documents for each row execute function private.photo_document_guard();

alter function private.snapshot(uuid) rename to snapshot_before_photos;
create function private.snapshot(w uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r jsonb;files jsonb;
begin
 r:=private.snapshot_before_photos(w);
 select coalesce(jsonb_agg(private.photo_json(p)||jsonb_build_object('filePresent',exists(select 1 from storage.objects where bucket_id='tallerflow-photos' and name=p.path))), '[]'::jsonb)
 into files from private.order_photos p where p.workshop_id=w and private.photo_storage_access('tallerflow-photos',p.path,false);
 return r||jsonb_build_object('photoManifest',files,'restoreFilesPending',not private.photo_files_ready(w));
end $$;
alter function private.note_snapshot(jsonb) rename to note_snapshot_before_photos;
create function private.note_snapshot(d jsonb) returns jsonb language sql immutable set search_path='' as $$
 select private.note_snapshot_before_photos(d)||jsonb_build_object('photos',coalesce(d->'photos','[]'::jsonb))
$$;
alter function private.apply(uuid,uuid,jsonb) rename to apply_before_photos;
create function private.apply(w uuid,dev uuid,op jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform private.membership(w);
 if not private.photo_files_ready(w) and exists(select 1 from private.devices where workshop_id=w and id=dev and retired_at is null) then raise exception 'Restore original photo files before recording new work';end if;
 return private.apply_before_photos(w,dev,op);
end $$;

create function public.photo_command(workshop_id uuid,device_id uuid,command_id uuid,action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.photo_command($1,$2,$3,$4,$5) $$;
create function public.photo_upload_info(workshop_id uuid,device_id uuid,photo_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.photo_info($1,$2,$3) $$;
create function public.photo_finalize(workshop_id uuid,device_id uuid,photo_id uuid,user_id uuid,session_id uuid,sha256 text,byte_size int) returns jsonb language sql security invoker set search_path='' as $$ select private.photo_finalize($1,$2,$3,$4,$5,$6,$7) $$;

revoke all on function private.photo_json(private.order_photos),private.photo_device(uuid,uuid),private.photo_order_access(uuid,uuid,uuid,boolean),private.photo_info(uuid,uuid,uuid),private.photo_command(uuid,uuid,uuid,text,jsonb),private.photo_finalize(uuid,uuid,uuid,uuid,uuid,text,int),private.photo_files_ready(uuid),private.photo_close_guard(),private.photo_document_guard(),private.snapshot_before_photos(uuid),private.note_snapshot_before_photos(jsonb),private.apply_before_photos(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.photo_command(uuid,uuid,uuid,text,jsonb),public.photo_upload_info(uuid,uuid,uuid),public.photo_finalize(uuid,uuid,uuid,uuid,uuid,text,int) from public,anon,authenticated;
grant execute on function private.photo_command(uuid,uuid,uuid,text,jsonb),private.photo_info(uuid,uuid,uuid),public.photo_command(uuid,uuid,uuid,text,jsonb),public.photo_upload_info(uuid,uuid,uuid) to authenticated;
grant execute on function private.photo_finalize(uuid,uuid,uuid,uuid,uuid,text,int),public.photo_finalize(uuid,uuid,uuid,uuid,uuid,text,int) to service_role;
revoke all on function private.snapshot(uuid),private.note_snapshot(jsonb),private.apply(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.snapshot(uuid),private.apply(uuid,uuid,jsonb) to authenticated;
create or replace function private.backup_tables() returns text[] language sql immutable set search_path='' as $$
 select array['members','member_permissions','vehicles','vehicle_profiles','vehicle_identifiers','vehicle_changes','catalog','catalog_details','templates','management_state','devices','device_sessions','orders','order_recipient_refs','operations','time_sessions',
 'close_requests','order_devices','close_acknowledgements','resolutions','command_receipts','documents','account_requests','audit','order_photos']::text[]
$$;
create or replace function private.export_workshop(w uuid,dev uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare t text; rows jsonb; tables jsonb:='{}'; workshop jsonb;
begin
 perform private.backup_admin(w,dev);
 select to_jsonb(x) into workshop from private.workshops x where id=w for update;
 foreach t in array private.backup_tables() loop
  execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from private.%I x where workshop_id=$1',t)
   into rows using w;
  tables:=tables||jsonb_build_object(t,rows);
 end loop;
 return jsonb_build_object('serverFormat',1,'databaseVersion',6,'workshopId',w,
  'exportedAt',now(),'workshop',workshop,'tables',tables,
  'restorationHistory',coalesce((select jsonb_agg(to_jsonb(x)) from private.restores x where workshop_id=w),'[]'),
  'externalFiles','[]'::jsonb,'authExcluded',true,'photoFiles',(select coalesce(jsonb_agg(private.photo_json(p)||jsonb_build_object('filePresent',exists(select 1 from storage.objects where bucket_id='tallerflow-photos' and name=p.path))), '[]'::jsonb) from private.order_photos p where p.workshop_id=w));
end $$;
create or replace function private.restore_workshop(w uuid,dev uuid,rid uuid,a jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare previous private.restores%rowtype; t text; r jsonb; tables jsonb; cols text; result jsonb:='{}'; n bigint;
begin
 perform private.backup_admin(w,dev);
 perform 1 from private.workshops where id=w for update;
 if rid is null then raise exception 'Stable restore ID required'; end if;
 select * into previous from private.restores where workshop_id=w and id=rid;
 if found then
  if previous.archive<>a or previous.actor_id<>auth.uid() then raise exception 'Restore ID reused'; end if;
  return previous.result;
 end if;
 if a->>'serverFormat' is distinct from '1' or coalesce(a->>'databaseVersion','') not in ('2','3','4','5','6') or a->>'workshopId' is distinct from w::text
  or a->'workshop'->>'id' is distinct from w::text or a->>'authExcluded' is distinct from 'true' then raise exception 'Incompatible workshop archive'; end if;
 tables:=a->'tables';
 if a->>'databaseVersion'<>'6' then tables:=tables||jsonb_build_object('order_photos','[]'::jsonb);end if;
 if a->>'databaseVersion' in ('2','3','4') then tables:=jsonb_build_object('vehicle_profiles','[]'::jsonb,'vehicle_identifiers','[]'::jsonb,'vehicle_changes','[]'::jsonb,'order_recipient_refs','[]'::jsonb)||tables;end if;
 if a->>'databaseVersion' in ('2','3') then tables:=jsonb_build_object('account_requests','[]'::jsonb)||tables;end if;
 if a->>'databaseVersion'='2' then tables:=jsonb_build_object('member_permissions','[]'::jsonb,'catalog_details','[]'::jsonb,'templates','[]'::jsonb,'management_state','[]'::jsonb)||tables;end if;
 if jsonb_typeof(tables) is distinct from 'object' then raise exception 'Missing archive tables'; end if;
 if exists(select 1 from jsonb_object_keys(tables) k where not k=any(private.backup_tables())) then raise exception 'Unknown archive table'; end if;
 if exists(select 1 from private.order_photos where workshop_id=w) or exists(select 1 from private.orders where workshop_id=w) or exists(select 1 from private.operations where workshop_id=w)
  or exists(select 1 from private.documents where workshop_id=w) or exists(select 1 from private.catalog where workshop_id=w)
  or exists(select 1 from private.templates where workshop_id=w) or exists(select 1 from private.management_state where workshop_id=w)
  or exists(select 1 from private.vehicle_profiles where workshop_id=w) or exists(select 1 from private.vehicle_changes where workshop_id=w) or exists(select 1 from private.vehicles where workshop_id=w) or exists(select 1 from private.restores where workshop_id=w)
  or exists(select 1 from private.devices where workshop_id=w and id<>dev)
  or exists(select 1 from private.members where workshop_id=w and user_id<>auth.uid()) then
  raise exception 'Restore requires an empty isolated workshop with only its bootstrap administrator and current device';
 end if;
 foreach t in array private.backup_tables() loop
  if jsonb_typeof(tables->t) is distinct from 'array' then raise exception 'Missing or invalid archive table: %',t; end if;
  for r in select value from jsonb_array_elements(tables->t) loop
   if r->>'workshop_id'<>w::text or r->>'workshop_id' is null then raise exception 'Cross-workshop archive row'; end if;
  end loop;
 end loop;
 if not exists(select 1 from jsonb_array_elements(tables->'members') m where m->>'user_id'=auth.uid()::text
  and m->>'role'='admin' and (m->>'active')::boolean) then raise exception 'Bootstrap administrator must remain active'; end if;
 if exists(select 1 from jsonb_array_elements(tables->'members') m where not exists(select 1 from auth.users u where u.id=(m->>'user_id')::uuid)) then
  raise exception 'Auth identities must exist with their original IDs before restoring application data';
 end if;
 if exists(select 1 from jsonb_array_elements(tables->'devices') d where d->>'id'=dev::text) then
  raise exception 'Use a new authenticated device identity in the recovery environment';
 end if;
 update private.workshops set name=a->'workshop'->>'name',billing_country=a->'workshop'->>'billing_country',
  settings=a->'workshop'->'settings' where id=w;
 insert into private.members select * from jsonb_populate_recordset(null::private.members,tables->'members')
  on conflict(workshop_id,user_id) do update set display_name=excluded.display_name,role=excluded.role,
   see_prices=excluded.see_prices,active=excluded.active;
 foreach t in array private.backup_tables() loop
  if t='members' then continue; end if;
  if t='devices' then
   insert into private.devices(workshop_id,id,user_id,last_seen,auth_session_id,retired_at,retirement_reason)
    select workshop_id,id,user_id,last_seen,null,coalesce(retired_at,now()),
     coalesce(retirement_reason,'Identidad histórica restaurada; requiere recuperación y revisión, no acredita sincronización')
    from jsonb_populate_recordset(null::private.devices,tables->t);
  elsif t='close_requests' then
   insert into private.close_requests select workshop_id,id,order_id,revision,
    case when status='active' then 'invalidated' else status end,requested_by,requested_at,exception_reason,retired_devices
    from jsonb_populate_recordset(null::private.close_requests,tables->t);
  elsif t='order_photos' then
   if exists(select 1 from jsonb_array_elements(tables->t) x where x->>'status'='attached' and not exists(select 1 from jsonb_array_elements(coalesce(a->'photoFiles','[]'::jsonb)) f where f->>'id'=x->>'id' and f->>'sha256'=x->>'sha256' and f->>'filePresent'='true')) then raise exception 'Attached photo file manifest missing';end if;
   insert into private.order_photos(workshop_id,id,order_id,actor_id,device_id,original_device_id,sha256,byte_size,mime,caption,captured_at,created_at,status,verified_at,recovery,restored,restore_file_expected,restore_upload_device_id)
    select workshop_id,id,order_id,actor_id,device_id,original_device_id,sha256,byte_size,mime,caption,captured_at,created_at,
     case when status='pending' then 'review' else status end,verified_at,true,true,
     exists(select 1 from jsonb_array_elements(coalesce(a->'photoFiles','[]'::jsonb)) f where f->>'id'=p.id::text and f->>'filePresent'='true'),dev
    from jsonb_populate_recordset(null::private.order_photos,tables->t) p;
  elsif t='audit' then
   insert into private.audit(workshop_id,actor_id,operation_id,order_id,occurred_at,kind,before_data,after_data,source_id)
    select workshop_id,actor_id,operation_id,order_id,occurred_at,kind,before_data,after_data,coalesce(source_id,id)
    from jsonb_populate_recordset(null::private.audit,tables->t);
  else
   select string_agg(quote_ident(column_name),',' order by ordinal_position) into cols from information_schema.columns
    where table_schema='private' and table_name=t and is_generated='NEVER';
   execute format('insert into private.%I (%s) select %s from jsonb_populate_recordset(null::private.%I,$1)',t,cols,cols,t)
    using tables->t;
  end if;
  get diagnostics n=row_count;
  result:=result||jsonb_build_object(t,n);
 end loop;
 perform private.seed_vehicle_history(w);
 -- No Auth session or successful closure confirmation is restored as active authority.
 result:=jsonb_build_object('restored',true,'counts',result,'requiresDeviceReview',true,'restoreId',rid);
 insert into private.restores(workshop_id,id,actor_id,device_id,archive,result) values(w,rid,auth.uid(),dev,a,result);
 insert into private.audit(workshop_id,actor_id,kind,after_data) values(w,auth.uid(),'restore_workshop',
  jsonb_build_object('restoreId',rid,'counts',result->'counts','deviceId',dev,'originalClosureConfirmationsInvalidated',true));
 return result;
end $$;




commit;
