BEGIN;
SELECT set_config('request.jwt.claims','{"sub":"d043f2a5-5210-4cf1-ac62-6f22b6487e73","role":"authenticated"}',true);
SET LOCAL ROLE authenticated;
DO $t$ DECLARE a record; b record;
BEGIN
  SELECT * INTO STRICT a FROM public.reserve_my_calicata_json_v01(
    'f4547c5d-5290-4de9-b999-8f1e260af012','cf3740fb-0a46-46dd-8273-0b85bc1e17e4',null,2,repeat('e',64),gen_random_uuid());
  PERFORM public.abort_binary_document_upload_v01(a.attempt_id);
  SELECT * INTO STRICT b FROM public.reserve_my_calicata_json_v01(
    'f4547c5d-5290-4de9-b999-8f1e260af012','cf3740fb-0a46-46dd-8273-0b85bc1e17e4',null,2,repeat('e',64),gen_random_uuid());
  PERFORM public.begin_binary_document_upload_v01(b.attempt_id);
  IF a.document_node_id<>b.document_node_id OR a.document_version_id<>b.document_version_id OR a.attempt_id=b.attempt_id THEN
    RAISE EXCEPTION 'retry identity mismatch';
  END IF;
END;$t$;
ROLLBACK;
SELECT 'PASS retry begins on same node/version with original CAS baseline' result;
