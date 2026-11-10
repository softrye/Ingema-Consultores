-- InGePlus-Dev only. Stable references, own writes and project-scoped reads.
-- Legacy avatar/avatar.* paths remain readable/deletable for deployed clients.
create function private.profile_avatar_owner_v02(p_path text)
returns uuid language plpgsql immutable set search_path=''
as $fn$
begin
  if p_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/([A-Za-z0-9_-]+[.](jpg|jpeg|png)|avatar/avatar[.](jpg|jpeg|png))$' then
    return split_part(p_path,'/',1)::uuid;
  end if;
  return null;
end $fn$;
revoke all on function private.profile_avatar_owner_v02(text) from public,anon,authenticated,service_role;
grant execute on function private.profile_avatar_owner_v02(text) to authenticated;

create or replace function private.owns_profile_avatar_v01(p_bucket text,p_path text)
returns boolean language sql stable set search_path=''
as $fn$
 select coalesce(p_bucket='avatars' and auth.uid() is not null
   and private.profile_avatar_owner_v02(p_path)=auth.uid(),false);
$fn$;
-- Cross-profile/membership lookup must bypass their own SELECT RLS, not Storage RLS.
create function private.can_read_profile_avatar_v02(p_bucket text,p_path text)
returns boolean language sql stable security definer set search_path=''
as $fn$
 select coalesce(p_bucket='avatars' and auth.uid() is not null and exists(
   select 1 from public.profiles viewer
   join public.profiles owner on owner.id=private.profile_avatar_owner_v02(p_path)
   where viewer.id=auth.uid() and viewer.status='ACTIVO' and owner.status='ACTIVO'
   and (viewer.id=owner.id or viewer.global_role in ('ADMINISTRADOR','ADMINISTRADOR_GENERAL','GERENCIA')
     or exists(
       select 1 from public.project_members mine
       join public.project_members theirs on theirs.project_id=mine.project_id
       join public.projects project on project.id=mine.project_id
       where mine.profile_id=viewer.id and theirs.profile_id=owner.id
         and mine.status='ACTIVO' and theirs.status='ACTIVO' and project.status='ACTIVO'
         and (mine.starts_at is null or mine.starts_at<=now())
         and (theirs.starts_at is null or theirs.starts_at<=now())
         and (mine.ends_at is null or mine.ends_at>now())
         and (theirs.ends_at is null or theirs.ends_at>now())
     ))
 ),false);
$fn$;
revoke all on function private.can_read_profile_avatar_v02(text,text) from public,anon,authenticated,service_role;
grant execute on function private.can_read_profile_avatar_v02(text,text) to authenticated;

alter policy avatars_owner_select_v01 on storage.objects
 using(private.can_read_profile_avatar_v02(bucket_id,name));
drop policy avatars_owner_admission_v01 on storage.objects;
-- Per-command restrictive gates stop unrelated permissive policies widening access.
create policy avatars_read_admission_v02 on storage.objects as restrictive for select to authenticated
 using(bucket_id<>'avatars' or private.can_read_profile_avatar_v02(bucket_id,name));
create policy avatars_insert_admission_v02 on storage.objects as restrictive for insert to authenticated
 with check(bucket_id<>'avatars' or private.owns_profile_avatar_v01(bucket_id,name));
create policy avatars_update_admission_v02 on storage.objects as restrictive for update to authenticated
 using(bucket_id<>'avatars' or private.owns_profile_avatar_v01(bucket_id,name))
 with check(bucket_id<>'avatars' or private.owns_profile_avatar_v01(bucket_id,name));
create policy avatars_delete_admission_v02 on storage.objects as restrictive for delete to authenticated
 using(bucket_id<>'avatars' or private.owns_profile_avatar_v01(bucket_id,name));
update storage.buckets set public=false,file_size_limit=5242880,
 allowed_mime_types=array['image/png','image/jpeg'] where id='avatars';

CREATE OR REPLACE FUNCTION private.sync_auth_profile_metadata_v01()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare prior jsonb:='{}'::jsonb; data jsonb:=coalesce(new.raw_user_meta_data,'{}'::jsonb);
  name_changed boolean; phone_changed boolean; avatar_changed boolean; avatar_path text; avatar_ref text;
begin
  if tg_op='UPDATE' then prior:=coalesce(old.raw_user_meta_data,'{}'::jsonb); end if;
  name_changed:=data ? 'full_name' and (tg_op='INSERT' or data->'full_name' is distinct from prior->'full_name');
  phone_changed:=data ? 'phone' and (tg_op='INSERT' or data->'phone' is distinct from prior->'phone');
  avatar_changed:=(data ? 'avatar_url' and (tg_op='INSERT' or data->'avatar_url' is distinct from prior->'avatar_url'))
    or (data ? 'avatar_path' and (tg_op='INSERT' or data->'avatar_path' is distinct from prior->'avatar_path'));
  if name_changed and jsonb_typeof(data->'full_name') not in ('string','null') then
    raise exception using errcode='22023',message='El nombre no es válido.';
  end if;
  if phone_changed and jsonb_typeof(data->'phone') not in ('string','null') then
    raise exception using errcode='22023',message='El teléfono no es válido.';
  end if;
  if avatar_changed then
    if data ? 'avatar_url' and (tg_op='INSERT' or data->'avatar_url' is distinct from prior->'avatar_url') then
      if jsonb_typeof(data->'avatar_url') not in ('string','null') then
        raise exception using errcode='22023',message='La referencia de la foto no es válida.';
      end if;
      avatar_ref:=nullif(data->>'avatar_url','');
      if avatar_ref is not null then
        if left(avatar_ref,18)<>'storage://avatars/' then
          raise exception using errcode='22023',message='La foto debe usar una referencia privada de avatars.';
        end if;
        avatar_path:=substring(avatar_ref from 19);
      end if;
    else
      if jsonb_typeof(data->'avatar_path') not in ('string','null') then
        raise exception using errcode='22023',message='La ruta de la foto no es válida.';
      end if;
      avatar_path:=nullif(data->>'avatar_path','');
    end if;
    if avatar_path is not null then
      if private.profile_avatar_owner_v02(avatar_path) is distinct from new.id
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
end $function$
;
notify pgrst,'reload schema';
