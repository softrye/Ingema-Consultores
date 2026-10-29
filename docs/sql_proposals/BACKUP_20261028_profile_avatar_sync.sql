-- InGePlus-Dev only. Prestate for avatar sync v02; apply as a NEW rollback migration.
BEGIN;
CREATE OR REPLACE FUNCTION private.owns_profile_avatar_v01(p_bucket text, p_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(p_bucket='avatars' and auth.uid() is not null and
    p_path=any(array[auth.uid()::text||'/avatar/avatar.png',auth.uid()::text||'/avatar/avatar.jpg',
                    auth.uid()::text||'/avatar/avatar.jpeg']),false);
$function$
;

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
end $function$
;
DROP POLICY IF EXISTS avatars_read_admission_v02 ON storage.objects;
DROP POLICY IF EXISTS avatars_insert_admission_v02 ON storage.objects;
DROP POLICY IF EXISTS avatars_update_admission_v02 ON storage.objects;
DROP POLICY IF EXISTS avatars_delete_admission_v02 ON storage.objects;
ALTER POLICY avatars_owner_select_v01 ON storage.objects USING (private.owns_profile_avatar_v01(bucket_id,name));
CREATE POLICY avatars_owner_admission_v01 ON storage.objects AS RESTRICTIVE FOR ALL TO authenticated USING (((bucket_id <> 'avatars'::text) OR private.owns_profile_avatar_v01(bucket_id, name))) WITH CHECK (((bucket_id <> 'avatars'::text) OR private.owns_profile_avatar_v01(bucket_id, name)));
DROP FUNCTION IF EXISTS private.can_read_profile_avatar_v02(text,text);
DROP FUNCTION IF EXISTS private.profile_avatar_owner_v02(text);
COMMIT;
-- No objects or profile data are deleted. New canonical references cease to be readable
-- under the original owner-path predicate; use only with a coordinated client rollback.
