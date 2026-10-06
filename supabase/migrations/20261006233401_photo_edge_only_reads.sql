-- Storage authenticates GET using the get_authenticated_info operation too.
-- Permitting that operation would therefore still permit cached object GET.
-- Only the server reads Storage bytes; clients use the authenticated POST.
begin;
drop policy tallerflow_photo_read on storage.objects;
commit;
