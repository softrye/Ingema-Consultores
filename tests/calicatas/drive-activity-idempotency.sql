BEGIN;
SELECT set_config('request.jwt.claims','{"sub":"d043f2a5-5210-4cf1-ac62-6f22b6487e73","role":"authenticated"}',true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE a record; b record; e uuid:=gen_random_uuid(); n integer;
BEGIN
  SELECT * INTO STRICT a FROM public.reserve_my_calicata_json_v01(
    'f4547c5d-5290-4de9-b999-8f1e260af012','cf3740fb-0a46-46dd-8273-0b85bc1e17e4',
    null,2,repeat('a',64),gen_random_uuid());
  SELECT * INTO STRICT b FROM public.reserve_my_calicata_json_v01(
    'f4547c5d-5290-4de9-b999-8f1e260af012','cf3740fb-0a46-46dd-8273-0b85bc1e17e4',
    null,2,repeat('a',64),gen_random_uuid());
  IF a.document_node_id<>b.document_node_id OR a.attempt_id<>b.attempt_id
     OR a.document_version_id<>b.document_version_id OR b.result_code<>'IDEMPOTENT_REPLAY' THEN
    RAISE EXCEPTION 'duplicate reservation';
  END IF;
  SELECT count(*) INTO n FROM public.document_nodes WHERE id=a.document_node_id;
  IF n<>1 THEN RAISE EXCEPTION 'node count invalid'; END IF;
  PERFORM public.record_my_calicata_export_v02(e,'f4547c5d-5290-4de9-b999-8f1e260af012',
    'cf3740fb-0a46-46dd-8273-0b85bc1e17e4','excel','ANDROID');
  PERFORM public.record_my_calicata_export_v02(e,'f4547c5d-5290-4de9-b999-8f1e260af012',
    'cf3740fb-0a46-46dd-8273-0b85bc1e17e4','excel','ANDROID');
  SELECT count(*) INTO n FROM public.activity_logs WHERE id=e;
  IF n<>1 THEN RAISE EXCEPTION 'activity duplicate'; END IF;
  BEGIN
    PERFORM public.record_my_calicata_export_v02(e,'f4547c5d-5290-4de9-b999-8f1e260af012',
      'cf3740fb-0a46-46dd-8273-0b85bc1e17e4','pdf','ANDROID');
    RAISE EXCEPTION 'event reuse accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF has_table_privilege('authenticated','public.activity_logs','INSERT') THEN
    RAISE EXCEPTION 'activity direct insert opened';
  END IF;
  PERFORM set_config('test.drive',jsonb_build_object('same_save_twice','PASS','same_node','PASS',
    'activity_idempotent','PASS','activity_42501_fixed','PASS','table_grants_unchanged','PASS',
    'file_name',a.file_name,'rollback',true)::text,true);
END;
$test$;
SELECT current_setting('test.drive') AS result;
ROLLBACK;
