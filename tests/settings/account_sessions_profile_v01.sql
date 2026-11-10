-- Dev only. Uses a real non-admin user and session, never reads JWTs/IP/tokens.
-- All fixtures, revocations and profile updates are rolled back.
begin;
create temp table account_fixture on commit drop as
select p.id as user_id,s.id as current_id,
       (select id from public.profiles where id<>p.id order by id limit 1) as other_user,
       gen_random_uuid() as revoke_id,gen_random_uuid() as foreign_id,
       gen_random_uuid() as expired_id,gen_random_uuid() as newer_id
from public.profiles p join auth.sessions s on s.user_id=p.id
where p.role::text='LECTOR' and p.global_role is null and p.status::text='ACTIVO'
  and (s.not_after is null or s.not_after>=now())
order by s.created_at desc limit 1;
grant select on account_fixture to authenticated;
do $$
declare f record;
begin
  select * into strict f from account_fixture;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',f.user_id,'role','authenticated','session_id',f.current_id)::text,true);
end $$;
set local role authenticated;
-- RED before migration: undefined_function (not a fixture/schema failure).
select jsonb_typeof(public.list_my_auth_sessions_v01()) as rpc_response_type;
reset role;
insert into auth.sessions(id,user_id,created_at,updated_at,refreshed_at,user_agent,not_after)
select revoke_id,user_id,now()-interval '3 days',now()-interval '2 days',
       (now()-interval '2 days') at time zone 'UTC',
       'InGePlus-Android/1.0.0 (Samsung SM-A125M; Android 12)',null::timestamptz from account_fixture
union all select newer_id,user_id,now()-interval '1 day',now(),now() at time zone 'UTC',
       'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36',null from account_fixture
union all select foreign_id,other_user,now(),now(),null,'Test other account',null from account_fixture
union all select expired_id,user_id,now()-interval '5 days',now(),null,'Test expired',now()-interval '1 second' from account_fixture;
-- Only test tokens are generated; neither selected nor printed.
insert into auth.refresh_tokens(token,user_id,session_id,revoked,created_at,updated_at)
select gen_random_uuid()::text,user_id::text,revoke_id,false,now(),now() from account_fixture;
set local role authenticated;
do $$
declare f record; result jsonb; row jsonb; removed jsonb; total_keys integer;
begin
  select * into strict f from account_fixture;
  result:=public.list_my_auth_sessions_v01();
  if jsonb_typeof(result)<>'array' or result->0->>'id'<>f.current_id::text
     or result->0->>'current'<>'true' then raise exception 'FAIL_CURRENT_FIRST'; end if;
  if exists(select 1 from jsonb_array_elements(result) x where x->>'id' in(f.foreign_id::text,f.expired_id::text)) then raise exception 'FAIL_SESSION_ISOLATION'; end if;
  if result->1->>'id'<>f.newer_id::text then raise exception 'FAIL_ACTIVITY_ORDER'; end if;
  for row in select * from jsonb_array_elements(result) loop
    select count(*) into total_keys from jsonb_object_keys(row);
    if total_keys<>8 or not row ?& array['id','current','platform','platform_label','device_label','location','created_at','last_active_at']
      or row->'location'<>'null'::jsonb then raise exception 'FAIL_SESSION_PRIVACY'; end if;
  end loop;
  select x into strict row from jsonb_array_elements(result) x where x->>'id'=f.revoke_id::text;
  if row->>'platform'<>'android' or row->>'device_label'<>'Samsung SM-A125M' then raise exception 'FAIL_ANDROID_DEVICE'; end if;
  select x into strict row from jsonb_array_elements(result) x where x->>'id'=f.newer_id::text;
  if row->>'platform'<>'web' or row->>'platform_label'<>'Windows · Chrome' or row->>'device_label'<>'PC · Chrome' then raise exception 'FAIL_BROWSER_DEVICE'; end if;
  begin
    perform public.revoke_my_auth_session_v01(f.current_id);
    raise exception 'FAIL_CURRENT_REVOKED';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.revoke_my_auth_session_v01(f.foreign_id);
    raise exception 'FAIL_OTHER_REVOKED';
  exception when sqlstate 'P0002' then null;
  end;
  begin
    perform public.revoke_my_auth_session_v01(gen_random_uuid());
    raise exception 'FAIL_MISSING_REVOKED';
  exception when sqlstate 'P0002' then null;
  end;
  removed:=public.revoke_my_auth_session_v01(f.revoke_id);
  if removed<>'{"ok":true}'::jsonb then raise exception 'FAIL_REVOKE_RESULT'; end if;
  if exists(select 1 from jsonb_array_elements(public.list_my_auth_sessions_v01()) x where x->>'id'=f.revoke_id::text) then raise exception 'FAIL_SESSION_STILL_LISTED'; end if;
  begin
    update public.profiles set area='forbidden' where id=f.user_id;
    raise exception 'FAIL_OWNER_AREA_WRITE';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.set_profile_area_controlled_v01(f.user_id,'forbidden',now());
    raise exception 'FAIL_OWNER_AREA_RPC';
  exception when insufficient_privilege then null;
  end;
  if not exists(select 1 from public.profiles where id=f.user_id) then raise exception 'FAIL_OWNER_PROFILE_READ'; end if;
  if exists(select 1 from public.profiles where id=f.other_user) then raise exception 'FAIL_OTHER_PROFILE_READ'; end if;
  if not private.owns_profile_avatar_v01('avatars',f.user_id::text||'/avatar/avatar.png')
     or private.owns_profile_avatar_v01('avatars',f.other_user::text||'/avatar/avatar.png')
     or private.owns_profile_avatar_v01('avatars',f.user_id::text||'/../avatar/avatar.png') then raise exception 'FAIL_AVATAR_OWNER_BOUNDARY'; end if;
end $$;
reset role;
do $$
declare f record; before_row jsonb; after_row jsonb;
begin
  select * into strict f from account_fixture;
  if exists(select 1 from auth.sessions where id=f.revoke_id)
    or exists(select 1 from auth.refresh_tokens where session_id=f.revoke_id) then raise exception 'FAIL_REVOKE_CASCADE'; end if;
  if not exists(select 1 from auth.sessions where id=f.current_id and user_id=f.user_id)
    or not exists(select 1 from auth.sessions where id=f.foreign_id and user_id=f.other_user) then raise exception 'FAIL_UNRELATED_SESSION_CHANGED'; end if;
  select to_jsonb(p) into before_row from public.profiles p where id=f.user_id;
  update auth.users set raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||
    '{"full_name":"Prueba de perfil","phone":"","area":"forbidden","position":"forbidden","role":"ADMINISTRADOR_GENERAL","global_role":"ADMINISTRADOR_GENERAL","status":"BLOQUEADO"}'::jsonb
    where id=f.user_id;
  select to_jsonb(p) into after_row from public.profiles p where id=f.user_id;
  if after_row->>'full_name'<>'Prueba de perfil' or after_row->>'phone'<>'' then raise exception 'FAIL_METADATA_SYNC'; end if;
  if (before_row-array['full_name','phone','updated_at']) is distinct from (after_row-array['full_name','phone','updated_at']) then raise exception 'FAIL_METADATA_PRIVILEGE_ESCALATION'; end if;
  if has_function_privilege('anon','public.list_my_auth_sessions_v01()','EXECUTE')
     or has_function_privilege('anon','public.revoke_my_auth_session_v01(uuid)','EXECUTE') then raise exception 'FAIL_ANON_EXECUTE'; end if;
  perform set_config('request.jwt.claims','{}',true);
  begin
    perform public.list_my_auth_sessions_v01();
    raise exception 'FAIL_NO_AUTH_LIST';
  exception when invalid_authorization_specification then null;
  end;
end $$;
-- Administrator uses the same authorization boundary as institutional roles.
do $$
declare admin_id uuid;
begin
  select id into strict admin_id from public.profiles
  where status::text='ACTIVO' and global_role::text='ADMINISTRADOR_GENERAL'
  order by id limit 1;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
end $$;
set local role authenticated;
do $$
declare f record; stamp timestamptz; result jsonb;
begin
  select * into strict f from account_fixture;
  select updated_at into strict stamp from public.profiles where id=f.user_id;
  result:=public.set_profile_area_controlled_v01(f.user_id,'Prueba de área',stamp);
  if result->>'area'<>'Prueba de área' then raise exception 'FAIL_ADMIN_AREA_SETTER'; end if;
  begin
    perform public.set_profile_area_controlled_v01(f.user_id,'stale',stamp-interval '1 day');
    raise exception 'FAIL_ADMIN_STALE_WRITE';
  exception when serialization_failure then null;
  end;
end $$;
reset role;
do $$
declare f record;
begin
  select * into strict f from account_fixture;
  if not exists(select 1 from public.activity_logs where action='PROFILE_AREA_UPDATED' and entity_id=f.user_id)
    then raise exception 'FAIL_AREA_AUDIT'; end if;
end $$;
-- Signup regression under the maintenance connection. The hosted connector
-- rejects SET ROLE supabase_auth_admin; no privileges are expanded to bypass it.
do $$ begin perform set_config('request.jwt.claims','{}',true); end $$;
do $$
declare f record;
begin
  select * into strict f from account_fixture;
  update auth.users set raw_user_meta_data=raw_user_meta_data||'{"full_name":"Prueba desde Auth"}'::jsonb where id=f.user_id;
  insert into auth.users(id,aud,role,email,raw_user_meta_data)
  values(gen_random_uuid(),'authenticated','authenticated','account-check@invalid.example',
    '{"full_name":"Prueba de alta","phone":"test-phone","area":"forbidden","role":"ADMINISTRADOR_GENERAL","status":"ACTIVO"}'::jsonb);
end $$;
do $$
begin
  if not exists(select 1 from public.profiles p join account_fixture f on p.id=f.user_id where p.full_name='Prueba desde Auth') then raise exception 'FAIL_AUTH_ROLE_SYNC'; end if;
  if not exists(select 1 from public.profiles where email='account-check@invalid.example'
    and full_name='Prueba de alta' and phone='test-phone' and area is null and role::text='LECTOR' and status::text='PENDIENTE' and global_role is null)
    then raise exception 'FAIL_SIGNUP_DEFAULTS_OR_SYNC'; end if;
end $$;
select jsonb_build_object('tests','PASS','revoke_result',jsonb_build_object('ok',true),
  'current_preserved',exists(select 1 from auth.sessions s join account_fixture f on s.id=f.current_id),
  'foreign_preserved',exists(select 1 from auth.sessions s join account_fixture f on s.id=f.foreign_id)) as summary;
rollback;
