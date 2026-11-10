-- Dev only; SQL/RLS metadata test, NOT a binary Storage HTTP upload.
-- Real existing non-admin owner; all new identities/projects/objects roll back.
begin;
create temp table avatar_fixture on commit drop as
select p.id owner_id,gen_random_uuid() peer_id,gen_random_uuid() outsider_id,
 (select id from public.profiles where status='ACTIVO' and global_role='ADMINISTRADOR' limit 1) admin_id,
 gen_random_uuid() project_id,gen_random_uuid() object_id,
 p.id::text||'/codex-test-'||gen_random_uuid()::text||'.jpg' path
from public.profiles p where status='ACTIVO' and global_role is null limit 1;
grant select on avatar_fixture to authenticated;
do $$ begin if (select count(*) from avatar_fixture)<>1 then raise exception 'FIXTURE_OWNER_MISSING'; end if; end $$;
insert into auth.users(id,aud,role,email,raw_user_meta_data)
select peer_id,'authenticated','authenticated',peer_id::text||'@avatar-test.invalid',
 '{"full_name":"Avatar OAuth fixture","avatar_url":"https://provider.invalid/photo.jpg"}'::jsonb from avatar_fixture
union all select outsider_id,'authenticated','authenticated',outsider_id::text||'@avatar-test.invalid','{}'::jsonb from avatar_fixture;
do $$ begin
if not exists(select 1 from public.profiles where id=(select peer_id from avatar_fixture)
 and avatar_url is null and full_name='Avatar OAuth fixture') then raise exception 'FAIL_OAUTH_SIGNUP_COMPATIBILITY'; end if;
end $$;
update public.profiles set status='ACTIVO' where id in(select peer_id from avatar_fixture union all select outsider_id from avatar_fixture);
insert into public.projects(id,name,created_by) select project_id,'CODEX avatar rollback fixture',owner_id from avatar_fixture;
insert into public.project_members(project_id,profile_id,assignment_source)
select project_id,owner_id,'FIXTURE_LOCAL'::public.authorization_assignment_source from avatar_fixture
union all select project_id,peer_id,'FIXTURE_LOCAL'::public.authorization_assignment_source from avatar_fixture;
do $$ declare f record; begin select * into strict f from avatar_fixture;
perform set_config('request.jwt.claims',jsonb_build_object('sub',f.owner_id,'role','authenticated')::text,true); end $$;
set local role authenticated;
do $$ declare f record; n integer; begin select * into strict f from avatar_fixture;
insert into storage.objects(id,bucket_id,name,owner_id,metadata)
values(f.object_id,'avatars',f.path,f.owner_id::text,'{"mimetype":"image/jpeg","size":128}');
if not exists(select 1 from storage.objects where id=f.object_id) then raise exception 'FAIL_OWNER_READ'; end if;
-- Storage upsert uses SELECT + INSERT + UPDATE privileges/policies.
update storage.objects set metadata='{"mimetype":"image/jpeg","size":256}' where id=f.object_id;
get diagnostics n=row_count; if n<>1 then raise exception 'FAIL_OWNER_REPLACE'; end if;
begin
 update storage.objects set name=f.peer_id::text||'/intrusion.jpg' where id=f.object_id;
 raise exception 'FAIL_FOREIGN_MOVE'; exception when insufficient_privilege then null; end;
begin
 insert into storage.objects(bucket_id,name) values('avatars',f.peer_id::text||'/intrusion.jpg');
 raise exception 'FAIL_FOREIGN_INSERT'; exception when insufficient_privilege then null; end;
end $$;
reset role;
-- Trigger writes exactly the stable reference; no direct profiles write grant.
update auth.users u set raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||
 jsonb_build_object('avatar_path',f.path,'avatar_url','storage://avatars/'||f.path)
from avatar_fixture f where u.id=f.owner_id;
do $$ declare f record; begin select * into strict f from avatar_fixture;
if not exists(select 1 from public.profiles where id=f.owner_id and avatar_url='storage://avatars/'||f.path) then raise exception 'FAIL_PROFILE_REFERENCE'; end if;
update auth.users set raw_user_meta_data=raw_user_meta_data||'{"avatar_url":"https://provider.invalid/new-photo.jpg"}'::jsonb where id=f.owner_id;
if not exists(select 1 from public.profiles where id=f.owner_id and avatar_url='storage://avatars/'||f.path) then raise exception 'FAIL_PROVIDER_OVERWROTE_MANAGED_AVATAR'; end if;
perform set_config('request.jwt.claims',jsonb_build_object('sub',f.peer_id,'role','authenticated')::text,true); end $$;
set local role authenticated;
do $$ declare f record; n integer; begin select * into strict f from avatar_fixture;
if not exists(select 1 from storage.objects where id=f.object_id) then raise exception 'FAIL_SHARED_PROJECT_READ'; end if;
update storage.objects set metadata='{}' where id=f.object_id;
get diagnostics n=row_count; if n<>0 then raise exception 'FAIL_PEER_WRITE'; end if;
perform set_config('storage.allow_delete_query','true',true);
delete from storage.objects where id=f.object_id;
get diagnostics n=row_count; if n<>0 then raise exception 'FAIL_PEER_DELETE'; end if;
end $$;
reset role;
do $$ declare f record; begin select * into strict f from avatar_fixture;
perform set_config('request.jwt.claims',jsonb_build_object('sub',f.outsider_id,'role','authenticated')::text,true); end $$;
set local role authenticated;
do $$ begin if exists(select 1 from storage.objects where id=(select object_id from avatar_fixture)) then raise exception 'FAIL_OUTSIDER_READ'; end if; end $$;
reset role;
do $$ declare f record; begin select * into strict f from avatar_fixture;
perform set_config('request.jwt.claims',jsonb_build_object('sub',f.admin_id,'role','authenticated')::text,true); end $$;
set local role authenticated;
do $$ begin if not exists(select 1 from storage.objects where id=(select object_id from avatar_fixture)) then raise exception 'FAIL_ADMIN_READ'; end if; end $$;
reset role;
-- Expired membership must immediately lose visibility.
update public.project_members set status='FINALIZADO',starts_at=now()-interval '2 days',ends_at=now()-interval '1 day' where project_id=(select project_id from avatar_fixture) and profile_id=(select peer_id from avatar_fixture);
do $$ declare f record; begin select * into strict f from avatar_fixture;
perform set_config('request.jwt.claims',jsonb_build_object('sub',f.peer_id,'role','authenticated')::text,true); end $$;
set local role authenticated;
do $$ begin if exists(select 1 from storage.objects where id=(select object_id from avatar_fixture)) then raise exception 'FAIL_EXPIRED_MEMBERSHIP_READ'; end if; end $$;
reset role;
-- Mirror Storage service's delete-query context, only for our fixture object.
select set_config('storage.allow_delete_query','true',true);
do $$ declare f record; begin select * into strict f from avatar_fixture;
perform set_config('request.jwt.claims',jsonb_build_object('sub',f.owner_id,'role','authenticated')::text,true); end $$;
set local role authenticated;
do $$ declare n integer; begin
delete from storage.objects where id=(select object_id from avatar_fixture);
get diagnostics n=row_count; if n<>1 then raise exception 'FAIL_OWNER_DELETE'; end if;
end $$;
reset role;
update auth.users u set raw_user_meta_data=raw_user_meta_data||'{"avatar_path":null,"avatar_url":null}'::jsonb from avatar_fixture f where u.id=f.owner_id;
do $$ begin
if exists(select 1 from public.profiles where id=(select owner_id from avatar_fixture) and avatar_url is not null) then raise exception 'FAIL_CLEAR_REFERENCE'; end if;
if not exists(select 1 from storage.buckets where id='avatars' and not public and file_size_limit=5242880 and allowed_mime_types=array['image/png','image/jpeg']) then raise exception 'FAIL_BUCKET_LIMITS'; end if;
end $$;
select 'PASS: owner CRUD, peer/admin SELECT, foreign/expired denial, Auth/profile sync, private bucket limits; ROLLBACK' result;
rollback;
