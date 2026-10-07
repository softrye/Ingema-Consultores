-- Integration regression. Every folder, move and reservation is rolled back.
BEGIN;
SET LOCAL statement_timeout = '15s';
DO $test$
DECLARE
  c record; u uuid; first_folder record; replay record; moved_folder record;
  custom_folder record; upload record; mutation jsonb; node_revision bigint;
  denied boolean := false;
BEGIN
  SELECT cal.id, cal.project_id, n.id AS json_node_id, n.space_id, n.parent_id INTO STRICT c
  FROM public.calicatas cal
  JOIN private.calicata_json_bindings_v01 b ON b.calicata_id=cal.id
  JOIN public.document_nodes n ON n.id=b.node_id
  JOIN public.document_upload_attempts a ON a.id=b.attempt_id
  WHERE n.lifecycle='ACTIVE' AND a.status='FINALIZADO'
  ORDER BY cal.updated_at DESC LIMIT 1;
  FOR u IN SELECT id FROM public.profiles WHERE status='ACTIVO' LOOP
    PERFORM set_config('request.jwt.claim.sub',u::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
    IF private.can_read_project(c.project_id)
       AND private.can_write_document_space_content_v01(c.space_id)
       AND private.files_acl_can_access_v01(u,c.space_id,c.json_node_id,'WRITE'::private.document_access_level) THEN EXIT; END IF;
    u := NULL;
  END LOOP;
  IF u IS NULL THEN RAISE EXCEPTION 'No authorized JSON fixture'; END IF;
  SET LOCAL ROLE authenticated;
  SELECT * INTO STRICT first_folder FROM public.ensure_my_calicata_exports_folder_v01(c.project_id,c.id);
  IF first_folder.space_id<>c.space_id OR first_folder.json_parent_id IS DISTINCT FROM c.parent_id
     OR (SELECT parent_id FROM public.document_nodes WHERE id=first_folder.folder_id) IS DISTINCT FROM c.parent_id
     OR (SELECT name FROM public.document_nodes WHERE id=first_folder.folder_id)<>'exports' THEN
    RAISE EXCEPTION 'Exports folder is not beside the bound JSON';
  END IF;
  SELECT * INTO STRICT replay FROM public.ensure_my_calicata_exports_folder_v01(c.project_id,c.id);
  IF replay.folder_id<>first_folder.folder_id OR replay.result_code<>'IDEMPOTENT_REPLAY' THEN
    RAISE EXCEPTION 'Repeated export creates another folder';
  END IF;
  SELECT * INTO STRICT replay FROM public.ensure_my_calicata_exports_folder_v01(c.project_id,NULL);
  IF replay.folder_id<>first_folder.folder_id THEN
    RAISE EXCEPTION 'First local export does not use the canonical JSON folder';
  END IF;
  SELECT * INTO STRICT upload FROM public.reserve_binary_document_upload_v01(
    first_folder.space_id,first_folder.folder_id,'exports-regression.xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',2,gen_random_uuid());
  IF (SELECT parent_id FROM public.document_nodes WHERE id=upload.document_node_id)<>first_folder.folder_id THEN
    RAISE EXCEPTION 'Excel reservation does not use exports';
  END IF;
  SELECT * INTO STRICT custom_folder FROM public.create_document_folder_v01(
    c.space_id,c.parent_id,'exports-probe-'||gen_random_uuid()::text);
  IF NOT custom_folder.success THEN RAISE EXCEPTION 'Cannot create custom folder fixture'; END IF;
  SELECT node_version INTO STRICT node_revision FROM public.document_nodes WHERE id=c.json_node_id;
  SELECT * INTO STRICT mutation FROM public.inge_drive_mutate_v03(
    gen_random_uuid(),'MOVE',c.space_id,c.json_node_id,custom_folder.node_id,NULL,node_revision,false);
  IF NOT coalesce((mutation->>'success')::boolean,false) THEN RAISE EXCEPTION 'Cannot move JSON fixture: %',mutation; END IF;
  SELECT * INTO STRICT moved_folder FROM public.ensure_my_calicata_exports_folder_v01(c.project_id,c.id);
  IF moved_folder.json_parent_id<>custom_folder.node_id
     OR (SELECT parent_id FROM public.document_nodes WHERE id=moved_folder.folder_id)<>custom_folder.node_id THEN
    RAISE EXCEPTION 'Resolver ignores the real relocated JSON folder';
  END IF;
  BEGIN
    PERFORM public.ensure_my_calicata_exports_folder_v01(gen_random_uuid(),c.id);
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Cross-project access was allowed'; END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','{}',true);
  denied := false;
  BEGIN
    PERFORM public.ensure_my_calicata_exports_folder_v01(c.project_id,c.id);
  EXCEPTION WHEN invalid_authorization_specification THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Unauthenticated access was allowed'; END IF;
END;
$test$;
ROLLBACK;
SELECT 'PASS exports: real JSON parent, idempotency, XLSX reservation, moved JSON, permissions' AS result;
