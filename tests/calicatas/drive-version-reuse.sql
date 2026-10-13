-- Simulates Storage metadata only, inside ROLLBACK; no object bytes or user data are changed.
BEGIN;
SELECT set_config('request.jwt.claims','{"sub":"d043f2a5-5210-4cf1-ac62-6f22b6487e73","role":"authenticated"}',true);
SET LOCAL ROLE authenticated;
DO $t$
DECLARE a record;
BEGIN
  SELECT * INTO STRICT a FROM public.reserve_my_calicata_json_v01(
    'f4547c5d-5290-4de9-b999-8f1e260af012','cf3740fb-0a46-46dd-8273-0b85bc1e17e4',
    null,2,repeat('c',64),gen_random_uuid());
  PERFORM public.begin_binary_document_upload_v01(a.attempt_id);
  PERFORM set_config('test.slot',to_jsonb(a)::text,true);
END;
$t$;
RESET ROLE;
INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
SELECT s->>'bucket',s->>'storage_path','d043f2a5-5210-4cf1-ac62-6f22b6487e73',
  jsonb_build_object('size',2,'mimetype','application/json')
FROM (SELECT current_setting('test.slot')::jsonb s) q;
SET LOCAL ROLE authenticated;
DO $t$
DECLARE a jsonb:=current_setting('test.slot')::jsonb; b record; c record;
BEGIN
  PERFORM public.finalize_binary_document_upload_v01((a->>'attempt_id')::uuid);
  SELECT * INTO STRICT b FROM public.reserve_my_calicata_json_v01(
    'f4547c5d-5290-4de9-b999-8f1e260af012','cf3740fb-0a46-46dd-8273-0b85bc1e17e4',
    null,2,repeat('c',64),gen_random_uuid());
  IF b.document_node_id<>(a->>'document_node_id')::uuid OR b.attempt_status<>'FINALIZADO'
    OR b.document_version_id<>(a->>'document_version_id')::uuid THEN RAISE EXCEPTION 'completed replay mismatch'; END IF;
  SELECT * INTO STRICT c FROM public.reserve_my_calicata_json_v01(
    'f4547c5d-5290-4de9-b999-8f1e260af012','cf3740fb-0a46-46dd-8273-0b85bc1e17e4',
    null,3,repeat('d',64),gen_random_uuid());
  IF c.document_node_id<>b.document_node_id OR c.version_number<>b.version_number+1 THEN
    RAISE EXCEPTION 'updated content did not reuse node'; END IF;
END;
$t$;
ROLLBACK;
SELECT 'PASS completed replay and changed content reuse one node; Storage metadata rolled back' result;
