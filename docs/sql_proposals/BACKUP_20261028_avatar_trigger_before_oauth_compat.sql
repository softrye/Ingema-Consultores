-- Exact intermediate prestate. Restores v02 before OAuth compatibility only.
-- Prefer BACKUP_20261028_profile_avatar_sync.sql for a complete rollback.
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
