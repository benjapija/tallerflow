-- Private object GET may be served by a CDN without a new RLS check.
-- Application downloads therefore go through a non-cacheable authenticated
-- POST, which checks the current session and device before and after reading.
begin;
drop policy tallerflow_photo_read on storage.objects;
create policy tallerflow_photo_read on storage.objects for select to authenticated
 using(storage.allow_any_operation(array['object.get_authenticated_info','object.head_authenticated_info'])
  and private.photo_storage_access(bucket_id,name,false));

create function private.photo_download_info(w uuid,dev uuid,pid uuid) returns jsonb
 language plpgsql stable security definer set search_path='' as $$
declare p private.order_photos%rowtype;
begin
 perform private.photo_device(w,dev);
 select * into p from private.order_photos where workshop_id=w and id=pid;
 if not found or not private.photo_storage_access('tallerflow-photos',p.path,false) then
  raise exception 'Photo not available for this account' using errcode='42501';
 end if;
 return private.photo_json(p)||jsonb_build_object('sessionId',private.auth_session(),'userId',auth.uid());
end $$;
create function public.photo_download_info(workshop_id uuid,device_id uuid,photo_id uuid) returns jsonb
 language sql security invoker set search_path='' as $$ select private.photo_download_info($1,$2,$3) $$;
revoke all on function private.photo_download_info(uuid,uuid,uuid),public.photo_download_info(uuid,uuid,uuid) from public,anon;
grant execute on function private.photo_download_info(uuid,uuid,uuid),public.photo_download_info(uuid,uuid,uuid) to authenticated;
commit;
