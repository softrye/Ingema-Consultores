-- Read-only audit. No JWTs, credentials, annotation contents or photographs.
SELECT n.nspname AS schema_name, p.proname,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS result_type,
  p.prosecdef AS security_definer, pg_get_userbyid(p.proowner) AS owner,
  p.proconfig AS configuration, p.proacl AS privileges,
  has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
  has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
  pg_get_functiondef(p.oid) AS definition
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname IN ('public','private') AND
  (p.proname ILIKE '%calicata%media%' OR p.proname IN
    ('storage_rendition_attachment_insert_allowed_v01',
     'rendition_attachment_storage_uploadable_v01',
     'rendition_attachment_storage_readable_v01','files_purge_object_allowed_v01'))
ORDER BY n.nspname,p.proname;

SELECT policyname,permissive,roles,cmd,qual,with_check
FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
ORDER BY policyname;

SELECT id,public,file_size_limit,allowed_mime_types
FROM storage.buckets WHERE id='calicata-media';

SELECT c.oid::regclass AS table_name,c.relrowsecurity,
  has_table_privilege('authenticated',c.oid,'SELECT') AS can_select,
  has_table_privilege('authenticated',c.oid,'INSERT') AS can_insert,
  has_table_privilege('authenticated',c.oid,'UPDATE') AS can_update,
  has_table_privilege('authenticated',c.oid,'DELETE') AS can_delete
FROM pg_class c WHERE c.oid IN
  ('public.calicata_media'::regclass,'public.calicata_media_versions'::regclass);

SELECT conrelid::regclass AS table_name,conname,pg_get_constraintdef(oid)
FROM pg_constraint WHERE conrelid IN
  ('public.calicata_media'::regclass,'public.calicata_media_versions'::regclass);

SELECT count(*) AS invalid_active_versions
FROM public.calicata_media m JOIN public.calicata_media_versions v ON v.version_id=m.active_version_id
WHERE v.media_id<>m.media_id OR v.state<>'READY' OR v.discarded_at IS NOT NULL;

SELECT v.version_id,v.media_id,v.state,v.version_number,v.created_at,v.finalized_at,
  m.active_version_id,v.original_bucket,v.original_storage_path,
  v.derivative_bucket,v.derivative_storage_path,
  private.calicata_media_object_matches_v01(v.original_bucket,v.original_storage_path,
    v.created_by,v.original_size_bytes,v.original_mime_type) AS original_matches,
  CASE WHEN v.derivative_storage_path IS NULL THEN NULL ELSE
    private.calicata_media_object_matches_v01(v.derivative_bucket,v.derivative_storage_path,
      v.created_by,v.derivative_size_bytes,v.derivative_mime_type) END AS derivative_matches
FROM public.calicata_media_versions v JOIN public.calicata_media m USING(media_id)
WHERE m.calicata_id='cf3740fb-0a46-46dd-8273-0b85bc1e17e4'
ORDER BY v.created_at DESC;

SELECT version,name FROM supabase_migrations.schema_migrations
WHERE name IN ('calicata_media_storage_policy_isolation',
  'calicata_media_derivative_reservation_validation') ORDER BY version;
