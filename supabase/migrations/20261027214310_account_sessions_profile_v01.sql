-- InGePlus-Dev: Mi cuenta. No auth token/IP/user-agent is returned or logged.
create function private.auth_session_labels_v01(p_user_agent text)
returns jsonb language plpgsql immutable set search_path=''
as $fn$
declare
  ua text:=left(coalesce(p_user_agent,''),512);
  platform text:='other'; os text:=''; browser text:=''; device text:='Dispositivo';
  model text;
begin
  if ua ~* 'Android' then
    platform:='android'; os:='Android'; device:='Android';
    model:=substring(ua from '^InGePlus-Android/[^[:space:]]+ \(([A-Za-z0-9 ._-]{1,96}); Android [A-Za-z0-9._-]{1,32}\)$');
    if model is not null then device:=model;
    elsif ua ~ 'SM-[A-Za-z0-9-]+' then device:='Samsung '||substring(ua from '(SM-[A-Za-z0-9-]+)'); end if;
  elsif ua ~* '(iPhone|iPad|InGePlus-iOS)' then
    platform:='ios'; os:='iOS'; device:=case when ua ~* 'iPad' then 'iPad' else 'iPhone' end;
  elsif ua ~ '^InGePlus-Desktop/' then
    platform:='desktop'; device:='PC';
    os:=case when ua ~* 'Windows' then 'Windows' when ua ~* '(macOS|Macintosh|Darwin)' then 'macOS'
             when ua ~* 'Linux' then 'Linux' else 'Escritorio' end;
  elsif ua ~* '(Mozilla/|Chrome/|Firefox/|Safari/|Edg/)' then
    platform:='web'; device:='PC';
    os:=case when ua ~* 'Windows' then 'Windows' when ua ~* '(Macintosh|Mac OS)' then 'macOS'
             when ua ~* 'Linux' then 'Linux' else 'Web' end;
  end if;
  browser:=case when ua ~* '(Edg/|EdgA/|EdgiOS/)' then 'Edge'
                when ua ~* '(Firefox/|FxiOS/)' then 'Firefox'
                when ua ~* '(Chrome/|CriOS/)' then 'Chrome'
                when ua ~* 'Safari/' then 'Safari' else '' end;
  return jsonb_build_object('platform',platform,
    'platform_label',case when os='' then 'Otro' else os end||case when browser<>'' then ' · '||browser else '' end,
    'device_label',device||case when browser<>'' then ' · '||browser else '' end);
end $fn$;
revoke all on function private.auth_session_labels_v01(text) from public,anon,authenticated,service_role;

create function public.list_my_auth_sessions_v01()
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare actor uuid:=auth.uid(); current_id text:=auth.jwt()->>'session_id'; result jsonb;
begin
  if actor is null then raise exception using errcode='28000',message='Debes iniciar sesión para consultar tus dispositivos.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'current',coalesce(s.id::text=current_id,false),
    'platform',labels->>'platform','platform_label',labels->>'platform_label','device_label',labels->>'device_label',
    'location',null,'created_at',s.created_at,
    'last_active_at',coalesce(s.refreshed_at at time zone 'UTC',s.updated_at,s.created_at))
    order by coalesce(s.id::text=current_id,false) desc,
      coalesce(s.refreshed_at at time zone 'UTC',s.updated_at,s.created_at) desc nulls last,s.id),'[]'::jsonb)
  into result from auth.sessions s
  cross join lateral (select private.auth_session_labels_v01(s.user_agent) as labels) d
  where s.user_id=actor and (s.not_after is null or s.not_after>=now());
  return result;
end $fn$;

create function public.revoke_my_auth_session_v01(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare actor uuid:=auth.uid(); current_id text:=auth.jwt()->>'session_id';
begin
  if actor is null or nullif(current_id,'') is null then
    raise exception using errcode='28000',message='Debes iniciar sesión para cerrar otros dispositivos.';
  end if;
  if p_session_id::text=current_id then
    raise exception using errcode='22023',message='No puedes cerrar la sesión actual desde esta opción. Usa Cerrar sesión.';
  end if;
  if not exists(select 1 from auth.sessions where user_id=actor and id::text=current_id
    and (not_after is null or not_after>=now())) then
    raise exception using errcode='28000',message='Tu sesión ya no está activa. Vuelve a iniciar sesión.';
  end if;
  delete from auth.sessions where id=p_session_id and user_id=actor and id::text<>current_id;
  if not found then raise exception using errcode='P0002',message='No se encontró esa sesión en tu cuenta.'; end if;
  -- The existing FK deletes associated refresh_tokens. Already-issued JWTs
  -- remain usable until exp (normally about one hour); no JWT secret is used.
  return jsonb_build_object('ok',true);
end $fn$;
revoke all on function public.list_my_auth_sessions_v01() from public,anon,service_role;
revoke all on function public.revoke_my_auth_session_v01(uuid) from public,anon,service_role;
grant execute on function public.list_my_auth_sessions_v01() to authenticated;
grant execute on function public.revoke_my_auth_session_v01(uuid) to authenticated;

alter table public.profiles add column area text;
comment on column public.profiles.area is 'Área asignada exclusivamente por administración; nunca procede de user_metadata.';
-- profiles retains SELECT-only privileges and its existing own/global SELECT
-- policy. No UPDATE grant or owner UPDATE policy is added.
insert into private.activity_event_catalog(code,module,entity_type,project_id_required,
  entity_id_required,metadata_allowed,description)
values('PROFILE_AREA_UPDATED','AUTHORIZATION','PROFILE',false,true,false,'Cambio administrativo del área de un perfil.');

create function public.set_profile_area_controlled_v01(p_profile_id uuid,p_area text,p_expected_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare target public.profiles%rowtype; value text:=nullif(btrim(p_area),'');
begin
  perform private.files_admin_require_v01();
  select * into target from public.profiles where id=p_profile_id for update;
  if not found or target.status<>'ACTIVO' or p_profile_id=auth.uid() then
    raise exception using errcode='42501',message='USER_ADMIN_TARGET_NOT_ALLOWED';
  end if;
  if target.global_role in ('ADMINISTRADOR_GENERAL','GERENCIA') and not exists(
    select 1 from public.profiles where id=auth.uid() and global_role in ('ADMINISTRADOR_GENERAL','GERENCIA')) then
    raise exception using errcode='42501',message='USER_ADMIN_TARGET_ADMIN_PROTECTED';
  end if;
  if target.updated_at is distinct from p_expected_updated_at or p_expected_updated_at is null then
    raise exception using errcode='40001',message='USER_ADMIN_STALE_PROFILE';
  end if;
  if length(value)>120 or value ~ '[[:cntrl:]]' then raise exception using errcode='22023',message='El área no es válida.'; end if;
  update public.profiles set area=value where id=p_profile_id returning * into target;
  perform private.write_activity_log('PROFILE_AREA_UPDATED',null,p_profile_id,'WEB','Área del perfil actualizada','{}'::jsonb);
  return jsonb_build_object('ok',true,'area',target.area,'updated_at',target.updated_at);
end $fn$;
revoke all on function public.set_profile_area_controlled_v01(uuid,text,timestamptz) from public,anon,service_role;
grant execute on function public.set_profile_area_controlled_v01(uuid,text,timestamptz) to authenticated;

-- Private avatars: a stable storage reference is persisted, never a signed URL.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('avatars','avatars',false,5242880,array['image/png','image/jpeg']);
create function private.owns_profile_avatar_v01(p_bucket text,p_path text)
returns boolean language sql stable set search_path=''
as $fn$
  select coalesce(p_bucket='avatars' and auth.uid() is not null and
    p_path=any(array[auth.uid()::text||'/avatar/avatar.png',auth.uid()::text||'/avatar/avatar.jpg',
                    auth.uid()::text||'/avatar/avatar.jpeg']),false);
$fn$;
revoke all on function private.owns_profile_avatar_v01(text,text) from public,anon,service_role;
grant execute on function private.owns_profile_avatar_v01(text,text) to authenticated;
create policy avatars_owner_select_v01 on storage.objects for select to authenticated
  using(private.owns_profile_avatar_v01(bucket_id,name));
create policy avatars_owner_insert_v01 on storage.objects for insert to authenticated
  with check(private.owns_profile_avatar_v01(bucket_id,name));
create policy avatars_owner_update_v01 on storage.objects for update to authenticated
  using(private.owns_profile_avatar_v01(bucket_id,name)) with check(private.owns_profile_avatar_v01(bucket_id,name));
create policy avatars_owner_delete_v01 on storage.objects for delete to authenticated
  using(private.owns_profile_avatar_v01(bucket_id,name));
-- Prevent any unrelated permissive policy from widening avatars access.
create policy avatars_owner_admission_v01 on storage.objects as restrictive for all to authenticated
  using(bucket_id<>'avatars' or private.owns_profile_avatar_v01(bucket_id,name))
  with check(bucket_id<>'avatars' or private.owns_profile_avatar_v01(bucket_id,name));

create function private.sync_auth_profile_metadata_v01()
returns trigger language plpgsql security definer set search_path=''
as $fn$
declare prior jsonb:='{}'::jsonb; data jsonb:=coalesce(new.raw_user_meta_data,'{}'::jsonb);
  name_changed boolean; phone_changed boolean; avatar_changed boolean; avatar_path text; avatar_ref text;
begin
  if tg_op='UPDATE' then prior:=coalesce(old.raw_user_meta_data,'{}'::jsonb); end if;
  name_changed:=data ? 'full_name' and (tg_op='INSERT' or data->'full_name' is distinct from prior->'full_name');
  phone_changed:=data ? 'phone' and (tg_op='INSERT' or data->'phone' is distinct from prior->'phone');
  avatar_changed:=data ? 'avatar_path' and (tg_op='INSERT' or data->'avatar_path' is distinct from prior->'avatar_path');
  if name_changed and jsonb_typeof(data->'full_name') not in ('string','null') then
    raise exception using errcode='22023',message='El nombre no es válido.';
  end if;
  if phone_changed and jsonb_typeof(data->'phone') not in ('string','null') then
    raise exception using errcode='22023',message='El teléfono no es válido.';
  end if;
  if avatar_changed then
    avatar_path:=nullif(data->>'avatar_path','');
    if avatar_path is not null then
      if not (avatar_path=any(array[new.id::text||'/avatar/avatar.png',new.id::text||'/avatar/avatar.jpg',new.id::text||'/avatar/avatar.jpeg']))
        or not exists(select 1 from storage.objects where bucket_id='avatars' and name=avatar_path) then
        raise exception using errcode='42501',message='La foto de perfil no pertenece a tu cuenta o no está subida.';
      end if;
      avatar_ref:='storage://avatars/'||avatar_path;
    end if;
  end if;
  if name_changed or phone_changed or avatar_changed then
    update public.profiles set
      full_name=case when name_changed then data->>'full_name' else full_name end,
      phone=case when phone_changed then data->>'phone' else phone end,
      avatar_url=case when avatar_changed then avatar_ref else avatar_url end
    where id=new.id;
  end if;
  -- Never copy email, position, area, role, status, global_role or app_metadata.
  return new;
end $fn$;
revoke all on function private.sync_auth_profile_metadata_v01() from public,anon,authenticated,service_role;
-- Runs after the existing on_auth_user_created trigger; that trigger remains
-- the sole source of profile provisioning, initial status and administration.
create trigger zz_sync_auth_profile_metadata_v01 after insert or update of raw_user_meta_data on auth.users
for each row execute function private.sync_auth_profile_metadata_v01();
-- Fill only missing phone values. Do not overwrite existing names or any
-- administrative assignments during this migration.
update public.profiles p set phone=u.raw_user_meta_data->>'phone'
from auth.users u where u.id=p.id and p.phone is null
  and jsonb_typeof(u.raw_user_meta_data->'phone')='string';
