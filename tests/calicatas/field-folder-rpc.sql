-- Run with the Supabase SQL connection. Does not require a build or device.
-- Regression: missing deployment or incompatible RPC contract must fail.
BEGIN;
DO $test$
DECLARE
  v_fn regprocedure := to_regprocedure('public.ensure_calicata_field_folder_v01(uuid)');
BEGIN
  IF v_fn IS NULL THEN
    RAISE EXCEPTION 'FAIL: Calicatas field-folder RPC is not deployed';
  END IF;
  IF NOT has_function_privilege('authenticated', v_fn, 'EXECUTE')
     OR has_function_privilege('anon', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: RPC execution permissions';
  END IF;
END;
$test$;

-- Regression: creation/binding/idempotency must work under the actual client
-- role, and the following Smart Document RPC must accept the resulting FIELD.
-- Actors and projects are discovered from this database; no saved credentials.
DO $flows$
DECLARE
  v_space record;
  v_profile record;
  v_actor uuid;
  v_last_actor uuid;
  v_result record;
  v_replay record;
  v_expected text;
  v_calicata uuid;
  v_smart record;
  v_count integer := 0;
  v_denied boolean;
BEGIN
  FOR v_space IN
    SELECT id, project_id FROM public.document_spaces
    WHERE space_type = 'PROJECT' AND status = 'ACTIVO' ORDER BY id
  LOOP
    v_actor := NULL;
    FOR v_profile IN SELECT id FROM public.profiles WHERE status = 'ACTIVO' ORDER BY id LOOP
      PERFORM set_config('request.jwt.claim.sub', v_profile.id::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub',v_profile.id,'role','authenticated')::text, true);
      IF private.can_read_project(v_space.project_id)
         AND private.can_write_document_space_content_v01(v_space.id) THEN
        v_actor := v_profile.id;
        EXIT;
      END IF;
    END LOOP;
    IF v_actor IS NULL THEN
      RAISE EXCEPTION 'FAIL: no authorized test actor for project %', v_space.project_id;
    END IF;
    v_last_actor := v_actor;
    v_expected := CASE
      WHEN EXISTS (SELECT 1 FROM public.document_nodes WHERE space_id=v_space.id AND structural_context='FIELD')
        THEN 'IDEMPOTENT_REPLAY'
      WHEN EXISTS (SELECT 1 FROM public.document_nodes WHERE space_id=v_space.id AND parent_id IS NULL AND name='06_GABINETE' AND lifecycle='ACTIVE')
        THEN 'BOUND'
      ELSE 'CREATED' END;

    SET LOCAL ROLE authenticated;
    SELECT * INTO STRICT v_result
    FROM public.ensure_calicata_field_folder_v01(p_project_id => v_space.project_id);
    SELECT * INTO STRICT v_replay
    FROM public.ensure_calicata_field_folder_v01(p_project_id => v_space.project_id);
    RESET ROLE;
    IF v_result.space_id <> v_space.id OR v_result.folder_id IS NULL
       OR v_result.result_code <> v_expected
       OR v_replay.folder_id <> v_result.folder_id
       OR v_replay.result_code <> 'IDEMPOTENT_REPLAY' THEN
      RAISE EXCEPTION 'FAIL: field folder result/replay for project %', v_space.project_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.document_nodes
                   WHERE id=v_result.folder_id AND space_id=v_space.id
                     AND structural_context='FIELD' AND name='06_GABINETE'
                     AND parent_id IS NULL AND node_kind='FOLDER' AND lifecycle='ACTIVE') THEN
      RAISE EXCEPTION 'FAIL: canonical FIELD not persisted';
    END IF;

    -- A client cannot remove/change the binding or write its private guard.
    SET LOCAL ROLE authenticated;
    v_denied := false;
    BEGIN
      UPDATE public.document_nodes SET structural_context=NULL WHERE id=v_result.folder_id;
    EXCEPTION WHEN insufficient_privilege THEN v_denied := true;
    END;
    RESET ROLE;
    IF NOT v_denied AND EXISTS (SELECT 1 FROM public.document_nodes WHERE id=v_result.folder_id AND structural_context IS NULL) THEN
      RAISE EXCEPTION 'FAIL: client removed FIELD binding';
    END IF;

    SELECT id INTO v_calicata FROM public.calicatas WHERE project_id=v_space.project_id ORDER BY id LIMIT 1;
    IF v_calicata IS NOT NULL THEN
      SET LOCAL ROLE authenticated;
      SELECT * INTO STRICT v_smart FROM public.ensure_calicata_smart_document_v01(v_calicata);
      RESET ROLE;
      IF v_smart.project_id <> v_space.project_id OR v_smart.target_id <> v_calicata
         OR v_smart.document_node_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: downstream Smart Document';
      END IF;
    END IF;
    v_count := v_count + 1;
  END LOOP;
  IF v_count = 0 THEN RAISE EXCEPTION 'FAIL: no project exercised'; END IF;
  IF EXISTS (SELECT 1 FROM private.document_field_binding_guards_v01) THEN
    RAISE EXCEPTION 'FAIL: leaked FIELD guard';
  END IF;

  SET LOCAL ROLE authenticated;
  v_denied := false;
  BEGIN
    INSERT INTO private.document_field_binding_guards_v01 VALUES (txid_current(), v_last_actor, gen_random_uuid());
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: client can forge FIELD guard'; END IF;

  v_denied := false;
  BEGIN
    PERFORM public.ensure_calicata_field_folder_v01(gen_random_uuid());
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'FIELD_FOLDER_NOT_FOUND_OR_FORBIDDEN' THEN RAISE; END IF;
    v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: nonexistent project accepted'; END IF;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
  v_denied := false;
  BEGIN
    PERFORM public.ensure_calicata_field_folder_v01(v_space.project_id);
  EXCEPTION WHEN SQLSTATE '28000' THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: missing identity accepted'; END IF;
  RESET ROLE;

  SET LOCAL ROLE anon;
  v_denied := false;
  BEGIN
    PERFORM public.ensure_calicata_field_folder_v01(v_space.project_id);
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: anon executed RPC'; END IF;
  RESET ROLE;
END;
$flows$;

-- Regression: a real active identity without project/space permission must not
-- acquire a FIELD folder through this SECURITY DEFINER RPC.
DO $denied_projects$
DECLARE
  v_profile record;
  v_space record;
  v_denied boolean;
  v_checked integer := 0;
BEGIN
  FOR v_profile IN SELECT id FROM public.profiles WHERE status='ACTIVO' LOOP
    PERFORM set_config('request.jwt.claim.sub',v_profile.id::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_profile.id,'role','authenticated')::text,true);
    FOR v_space IN SELECT id,project_id FROM public.document_spaces WHERE space_type='PROJECT' AND status='ACTIVO' LOOP
      IF private.can_read_project(v_space.project_id)
         AND private.can_write_document_space_content_v01(v_space.id) THEN CONTINUE; END IF;
      SET LOCAL ROLE authenticated;
      v_denied := false;
      BEGIN
        PERFORM public.ensure_calicata_field_folder_v01(v_space.project_id);
      EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'FIELD_FOLDER_NOT_FOUND_OR_FORBIDDEN' THEN RAISE; END IF;
        v_denied := true;
      END;
      RESET ROLE;
      IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: unauthorized project accepted'; END IF;
      v_checked := v_checked + 1;
    END LOOP;
  END LOOP;
  IF v_checked = 0 THEN RAISE EXCEPTION 'FAIL: no unauthorized project fixture'; END IF;

  -- Identity without an active profile must also fail (no profile mutation).
  PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  v_denied := false;
  BEGIN
    PERFORM public.ensure_calicata_field_folder_v01(v_space.project_id);
  EXCEPTION WHEN insufficient_privilege THEN
    IF SQLERRM <> 'PROFILE_NOT_ACTIVE' THEN RAISE; END IF;
    v_denied := true;
  END;
  RESET ROLE;
  IF NOT v_denied THEN RAISE EXCEPTION 'FAIL: identity without active profile accepted'; END IF;
END;
$denied_projects$;
ROLLBACK;
SELECT 'PASS: RPC contract, all active projects, replay, Smart Document, access denials; test data rolled back' AS validation;
