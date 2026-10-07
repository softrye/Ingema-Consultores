-- Regression: Calicatas JSON identity in InGeDrive + activity ACL.
-- Requires migrations 20260929150428/150713 (06_GABINETE FIELD) and
-- 20260929201351 (reserve_my_calicata_json_v01). All writes are rolled back.
-- Checks:
--  1. Smart Document <code>.calicata exists (fixture).
--  2. The JSON reservation coexists with it: no NAME_CONFLICT.
--  3. JSON node lives in the same FIELD folder 06_GABINETE, with a different name.
--  4. Same content repeated -> IDEMPOTENT_REPLAY, same node (no new node).
--  5. New content while the version is pending -> busy, never a second node.
--  6. Cross-project reservation is denied.
--  7. Direct INSERT into activity_logs stays denied (42501).
--  8. Backend audit trigger for calicatas is still installed.
BEGIN;
DO $test$
DECLARE
  c record; u uuid; other_project uuid; first_slot record; replay record;
  field_folder uuid; smart_name text; json_name text; blocked boolean; nodes integer;
  hash_a text := repeat('a', 64); hash_b text := repeat('b', 64);
BEGIN
  SELECT cal.id, cal.project_id, cal.code, n.space_id, n.parent_id, n.name AS smart_name INTO STRICT c
  FROM public.calicatas cal
  JOIN public.document_smart_bindings b ON b.calicata_id = cal.id
  JOIN public.document_nodes n ON n.id = b.node_id
  WHERE NOT EXISTS (SELECT 1 FROM private.calicata_json_bindings_v01 j WHERE j.calicata_id = cal.id)
  ORDER BY cal.created_at DESC LIMIT 1;

  FOR u IN SELECT id FROM public.profiles WHERE status = 'ACTIVO' LOOP
    PERFORM set_config('request.jwt.claim.sub', u::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', u, 'role', 'authenticated')::text, true);
    IF private.can_read_project(c.project_id) AND private.can_write_document_space_content_v01(c.space_id) THEN EXIT; END IF;
    u := NULL;
  END LOOP;
  IF u IS NULL THEN RAISE EXCEPTION 'No authorized fixture'; END IF;

  SELECT project.id INTO other_project FROM public.projects project
  WHERE project.id <> c.project_id AND NOT private.can_read_project(project.id) LIMIT 1;

  SET LOCAL ROLE authenticated;

  -- 3: canonical folder
  SELECT folder_id INTO STRICT field_folder FROM public.ensure_calicata_field_folder_v01(c.project_id);
  IF (SELECT name FROM public.document_nodes WHERE id = field_folder) <> '06_GABINETE' THEN
    RAISE EXCEPTION 'FIELD folder is not 06_GABINETE';
  END IF;

  -- 2: coexistence (a NAME_CONFLICT here raises and fails the test)
  SELECT * INTO STRICT first_slot FROM public.reserve_my_calicata_json_v01(
    c.project_id, c.id, NULL, 2, hash_a, gen_random_uuid());
  SELECT name INTO STRICT json_name FROM public.document_nodes WHERE id = first_slot.document_node_id;
  IF json_name = c.smart_name OR json_name LIKE '%.calicata' THEN RAISE EXCEPTION 'JSON node collides with Smart Document: %', json_name; END IF;
  IF (SELECT parent_id FROM public.document_nodes WHERE id = first_slot.document_node_id) IS DISTINCT FROM field_folder THEN
    RAISE EXCEPTION 'JSON node is not in 06_GABINETE';
  END IF;

  -- 4: repeated identical save
  SELECT * INTO STRICT replay FROM public.reserve_my_calicata_json_v01(
    c.project_id, c.id, NULL, 2, hash_a, gen_random_uuid());
  IF replay.document_node_id <> first_slot.document_node_id OR replay.attempt_id <> first_slot.attempt_id THEN
    RAISE EXCEPTION 'Repeated save did not reuse the node/attempt';
  END IF;

  -- 5: new content while pending -> busy, no second node
  blocked := false;
  BEGIN
    PERFORM public.reserve_my_calicata_json_v01(c.project_id, c.id, NULL, 3, hash_b, gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'CALICATA_JSON_UPLOAD_BUSY' THEN RAISE; END IF;
    blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'Expected busy while the JSON version is pending'; END IF;
  RESET ROLE;
  SELECT count(*) INTO nodes FROM private.calicata_json_bindings_v01 WHERE calicata_id = c.id;
  SET LOCAL ROLE authenticated;
  IF nodes <> 1 THEN RAISE EXCEPTION 'Expected exactly one JSON binding, got %', nodes; END IF;

  -- 6: cross-project
  IF other_project IS NOT NULL THEN
    blocked := false;
    BEGIN
      PERFORM public.reserve_my_calicata_json_v01(other_project, c.id, NULL, 2, hash_a, gen_random_uuid());
    EXCEPTION WHEN insufficient_privilege THEN blocked := true;
    END;
    IF NOT blocked THEN RAISE EXCEPTION 'Cross-project JSON reservation was not denied'; END IF;
  END IF;

  -- 7: direct activity insert stays denied
  blocked := false;
  BEGIN
    INSERT INTO public.activity_logs(id,project_id,actor_id,module,action,entity_type,entity_id,platform,description,metadata)
    VALUES (gen_random_uuid(), c.project_id, u, 'CALICATAS', 'CALICATA_UPDATED', 'CALICATA', c.id, 'ANDROID', 'Test', '{}');
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'Direct activity_logs INSERT was not denied'; END IF;

  RESET ROLE;

  -- 8: backend audit still wired
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger trg JOIN pg_catalog.pg_proc p ON p.oid = trg.tgfoid
    WHERE trg.tgrelid = 'public.calicatas'::regclass AND NOT trg.tgisinternal
      AND p.proname LIKE 'audit_calicata_change%') THEN
    RAISE EXCEPTION 'Backend calicata audit trigger missing';
  END IF;
END;
$test$;
ROLLBACK;
SELECT 'PASS: Smart Document + JSON coexist in 06_GABINETE; single JSON identity; ACL/audit intact' AS result;
