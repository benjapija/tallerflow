-- Local Storage metadata fixture. Object bytes and HTTP API are not simulated here.
create schema storage;
create function storage.allow_any_operation(operations text[]) returns boolean language sql stable as $$
 select coalesce(nullif(current_setting('storage.operation',true),''),'object.get_authenticated')=any(operations)
$$;
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text not null,name text not null,owner_id text,metadata jsonb,unique(bucket_id,name));
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated,anon;
grant select,insert,update,delete on storage.objects to authenticated;
