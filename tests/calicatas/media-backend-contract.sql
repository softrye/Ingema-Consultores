-- Integration test against InGePlus-Dev. All writes, including synthetic
-- Storage metadata, are rolled back. This is NOT an HTTP upload test.
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"bf9f0f82-10f9-4da3-bf74-cb7a3f3f755a","role":"authenticated"}', true);
SELECT set_config('storage.operation', 'storage.object.upload', true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  m public.calicata_media;
  v public.calicata_media_versions;
  v2 public.calicata_media_versions;
  original_v public.calicata_media_versions;
  mid uuid := gen_random_uuid();
  logo_id uuid := gen_random_uuid();
  vid uuid := gen_random_uuid();
  vid2 uuid := gen_random_uuid();
  vid3 uuid := gen_random_uuid();
  before_row bigint;
  n integer;
BEGIN
  IF has_function_privilege('authenticated', 'private.rendition_attachment_storage_uploadable_v01(text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'private.rendition_attachment_storage_uploadable_v01(text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'private Rendiciones function exposed';
  END IF;
  SELECT * INTO STRICT m FROM public.create_my_calicata_media_v01(
    'f4547c5d-5290-4de9-b999-8f1e260af012', 'cf3740fb-0a46-46dd-8273-0b85bc1e17e4',
    'PHOTO', 'EXECUTION', 'backend-test.png', 'image/png', 68, 1, 1, NULL, mid);
  PERFORM public.create_my_calicata_media_v01(m.project_id,m.calicata_id,'PHOTO','EXECUTION',
    'backend-test.png','image/png',68,1,1,NULL,mid);
  SELECT count(*) INTO n FROM public.calicata_media WHERE media_id=mid;
  IF n<>1 THEN RAISE EXCEPTION 'CREATE is not idempotent'; END IF;
  SELECT * INTO STRICT v FROM public.reserve_my_calicata_media_version_v01(
    mid,vid,'backend-test.png','image/png',68,1,1,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}');
  IF v.state<>'UPLOADING' OR v.original_bucket<>'calicata-media' OR v.derivative_storage_path IS NOT NULL THEN
    RAISE EXCEPTION 'invalid reservation';
  END IF;
  IF (SELECT active_version_id FROM public.calicata_media WHERE media_id=mid) IS NOT NULL THEN
    RAISE EXCEPTION 'reserve activated incomplete version';
  END IF;
  -- A failed first revision must not inherit upload permission from the
  -- media-level UPLOADING flag of the legacy original pipeline.
  PERFORM public.fail_my_calicata_media_version_v01(vid);
  BEGIN
    INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
      VALUES(v.original_bucket,v.original_storage_path,auth.uid()::text,'{"size":68,"mimetype":"image/png"}');
    RAISE EXCEPTION 'legacy policy accepts FAILED PHOTO original';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM public.reserve_my_calicata_media_version_v01(
    mid,vid,'backend-test.png','image/png',68,1,1,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}');
  -- Exact reserved path must succeed; this reproduces the reported failure.
  INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
    VALUES(v.original_bucket,v.original_storage_path,auth.uid()::text,'{"size":68,"mimetype":"image/png"}');
  -- Arbitrary and cross-bucket writes must remain forbidden.
  BEGIN
    INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
      VALUES(v.original_bucket,v.original_storage_path||'.arbitrary',auth.uid()::text,'{}');
    RAISE EXCEPTION 'unreserved path accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
      VALUES('project-files',v.original_storage_path,auth.uid()::text,'{}');
    RAISE EXCEPTION 'cross-bucket path accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  SELECT * INTO STRICT original_v FROM public.finalize_my_calicata_media_version_v01(vid);
  SELECT row_version INTO before_row FROM public.calicata_media WHERE media_id=mid;
  PERFORM public.finalize_my_calicata_media_version_v01(vid);
  IF original_v.state IS DISTINCT FROM 'READY' OR (SELECT active_version_id FROM public.calicata_media WHERE media_id=mid) IS DISTINCT FROM vid
     OR (SELECT row_version FROM public.calicata_media WHERE media_id=mid) IS DISTINCT FROM before_row THEN
    RAISE EXCEPTION 'FINALIZE/optional derivative/idempotency failed';
  END IF;
  BEGIN
    PERFORM public.fail_my_calicata_media_version_v01(vid);
    RAISE EXCEPTION 'READY version can fail';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  BEGIN
    PERFORM public.reserve_my_calicata_media_version_v01(
      mid,gen_random_uuid(),'invalid-derivative.png','image/png',68,1,1,NULL,
      'derivative.png','image/png',NULL,1,1,NULL,'{}');
    RAISE EXCEPTION 'incomplete derivative reservation accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  SELECT * INTO STRICT v2 FROM public.reserve_my_calicata_media_version_v01(
    mid,vid2,'backend-test-v2.png','image/png',68,1,1,NULL,'backend-test-derivative.png','image/png',68,1,1,NULL,'{}');
  -- Another authorized collaborator can read this Calicata but must not
  -- upload/fail/finalize someone else's reservation.
  PERFORM set_config('request.jwt.claims','{"sub":"d043f2a5-5210-4cf1-ac62-6f22b6487e73","role":"authenticated"}',true);
  BEGIN
    INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
      VALUES(v2.original_bucket,v2.original_storage_path,auth.uid()::text,'{"size":68,"mimetype":"image/png"}');
    RAISE EXCEPTION 'collaborator uploaded another users reservation';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.fail_my_calicata_media_version_v01(vid2);
    RAISE EXCEPTION 'collaborator failed another users reservation';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.finalize_my_calicata_media_version_v01(vid2);
    RAISE EXCEPTION 'collaborator finalized another users reservation';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
  IF EXISTS(SELECT 1 FROM public.calicata_media WHERE media_id=mid) THEN
    RAISE EXCEPTION 'nonmember can read media';
  END IF;
  BEGIN
    PERFORM public.create_my_calicata_media_v01(m.project_id,m.calicata_id,'PHOTO','EXECUTION',
      'nonmember.png','image/png',68,1,1,NULL,gen_random_uuid());
    RAISE EXCEPTION 'nonmember can create media';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims','{"sub":"bf9f0f82-10f9-4da3-bf74-cb7a3f3f755a","role":"authenticated"}',true);
  IF (SELECT active_version_id FROM public.calicata_media WHERE media_id=mid) IS DISTINCT FROM vid THEN
    RAISE EXCEPTION 'second reserve replaced active';
  END IF;
  BEGIN
    PERFORM public.finalize_my_calicata_media_version_v01(vid2);
    RAISE EXCEPTION 'missing original finalized';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
    VALUES(v2.original_bucket,v2.original_storage_path,auth.uid()::text,'{"size":68,"mimetype":"image/png"}');
  BEGIN
    PERFORM public.finalize_my_calicata_media_version_v01(vid2);
    RAISE EXCEPTION 'missing reserved derivative finalized';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM public.fail_my_calicata_media_version_v01(vid2);
  PERFORM public.fail_my_calicata_media_version_v01(vid2);
  IF (SELECT active_version_id FROM public.calicata_media WHERE media_id=mid) IS DISTINCT FROM vid
     OR (SELECT state FROM public.calicata_media_versions WHERE version_id=vid2) IS DISTINCT FROM 'FAILED' THEN
    RAISE EXCEPTION 'FAIL changed active or is not idempotent';
  END IF;
  BEGIN
    INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
      VALUES(v2.derivative_bucket,v2.derivative_storage_path,auth.uid()::text,'{"size":68,"mimetype":"image/png"}');
    RAISE EXCEPTION 'FAILED reservation accepts upload';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.reserve_my_calicata_media_version_v01(
      mid,vid2,NULL,NULL,NULL,NULL,NULL,NULL,'backend-test-derivative.png','image/png',68,1,1,NULL,'{}');
    RAISE EXCEPTION 'retry accepts null required identity';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  SELECT * INTO STRICT v FROM public.reserve_my_calicata_media_version_v01(
    mid,vid2,'backend-test-v2.png','image/png',68,1,1,NULL,'backend-test-derivative.png','image/png',68,1,1,NULL,'{}');
  IF v.version_id<>vid2 OR v.version_number<>2 OR v.state<>'UPLOADING'
     OR v.original_storage_path<>v2.original_storage_path THEN
    RAISE EXCEPTION 'RETRY generated another revision/path';
  END IF;
  -- Retrying an existing original cannot overwrite immutable bytes.
  BEGIN
    INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
      VALUES(v.original_bucket,v.original_storage_path,auth.uid()::text,'{"size":68,"mimetype":"image/png"}');
    RAISE EXCEPTION 'duplicate original accepted';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
    VALUES(v.derivative_bucket,v.derivative_storage_path,auth.uid()::text,'{"size":68,"mimetype":"image/png"}');
  PERFORM public.finalize_my_calicata_media_version_v01(vid2);
  IF (SELECT active_version_id FROM public.calicata_media WHERE media_id=mid) IS DISTINCT FROM vid2
     OR (SELECT count(*) FROM public.calicata_media_versions WHERE media_id=mid)<>2 THEN
    RAISE EXCEPTION 'retry finalization inconsistent';
  END IF;
  UPDATE storage.objects SET metadata='{"size":1,"mimetype":"image/png"}'
    WHERE bucket_id=v.original_bucket AND name=v.original_storage_path;
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>0 THEN RAISE EXCEPTION 'READY object overwritten'; END IF;
  -- Separate malformed synthetic object; no direct Storage deletions, which
  -- current Supabase explicitly prohibits even for transactional fixtures.
  SELECT * INTO STRICT v FROM public.reserve_my_calicata_media_version_v01(
    mid,vid3,'backend-test-v3.png','image/png',68,1,1,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}');
  INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
    VALUES(v.original_bucket,v.original_storage_path,auth.uid()::text,'{"size":67,"mimetype":"image/png"}');
  BEGIN
    PERFORM public.finalize_my_calicata_media_version_v01(vid3);
    RAISE EXCEPTION 'wrong object size finalized';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM public.fail_my_calicata_media_version_v01(vid3);
  IF (SELECT active_version_id FROM public.calicata_media WHERE media_id=mid) IS DISTINCT FROM vid2 THEN
    RAISE EXCEPTION 'malformed object replaced active version';
  END IF;
  -- Existing LOGO contract remains usable after narrowing PHOTO policy.
  SELECT * INTO STRICT m FROM public.create_my_calicata_media_v01(
    m.project_id,m.calicata_id,'LOGO','PROJECT','backend-logo.png','image/png',68,1,1,NULL,logo_id);
  SELECT * INTO STRICT m FROM public.reserve_my_calicata_media_original_v01(logo_id,
    'projects/'||m.project_id||'/calicatas/'||m.calicata_id||'/media/'||logo_id||'/original/backend-logo.png');
  INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
    VALUES(m.original_bucket,m.original_storage_path,auth.uid()::text,'{"size":68,"mimetype":"image/png"}');
  SELECT * INTO STRICT m FROM public.finalize_my_calicata_media_original_v01(logo_id);
  IF m.sync_state<>'UPLOADED' THEN RAISE EXCEPTION 'LOGO regression'; END IF;
  BEGIN
    PERFORM public.set_my_calicata_media_active_version_v01(logo_id,vid2,m.row_version);
    RAISE EXCEPTION 'version can activate on unrelated media';
  EXCEPTION WHEN no_data_found THEN NULL; END;
  -- No caller identity: RPCs must reject even known existing IDs.
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.finalize_my_calicata_media_version_v01(vid2);
    RAISE EXCEPTION 'anonymous identity finalized';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('test.media_backend',
    '{"CREATE":"PASS","RESERVE":"PASS","SQL_UPLOAD_RLS":"PASS","FINALIZE":"PASS","FAIL":"PASS","RETRY":"PASS","OPTIONAL_DERIVATIVE":"PASS","REQUIRED_DERIVATIVE":"PASS","INCOMPLETE_DERIVATIVE_REJECTED":"PASS","IMMUTABLE_READY":"PASS","NULL_RETRY_REJECTED":"PASS","FAILED_ORIGINAL_REJECTED":"PASS","CROSS_USER_REJECTED":"PASS","NONMEMBER_REJECTED":"PASS","LOGO_REGRESSION":"PASS","WRONG_MEDIA_VERSION_REJECTED":"PASS","rollback":true,"HTTP_UPLOAD":"NOT_RUN"}',true);
END;
$test$;
SELECT current_setting('test.media_backend')::jsonb AS result;
ROLLBACK;
