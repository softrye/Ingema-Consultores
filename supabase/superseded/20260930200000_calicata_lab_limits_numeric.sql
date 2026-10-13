-- Calicatas / Laboratorio: LL y LP con decimales (MTC E110 / E111: LL 32.5, LP 18.4).
-- NOT APPLIED by Android tooling (no db push). Review and apply through the normal
-- backend flow.
--
-- Data-safe:
--   * integer -> numeric(6,2) is lossless; existing integer values are preserved.
--   * no column is dropped, no table is recreated, RLS/policies are untouched.
-- Backward-aware:
--   * upsert_my_calicata_lab_result_v01/v02 keep their integer parameters (older
--     Web/Android clients keep working); only their RETURNS TABLE columns become
--     numeric so RETURN QUERY matches the widened table.
--   * upsert_my_calicata_lab_result_v03 = v02 with numeric LL/LP parameters. Android
--     uses v03 only when LL/LP carry decimals.
-- The definitions are derived from the deployed ones (pg_get_functiondef), never
-- rewritten blind; any unexpected shape aborts the whole migration.
-- Follow-up (Web contract owner): apply_calicata_field_change_v02 must cast
-- LAB_RESULT liquid_limit/plastic_limit to numeric; until then Android does not send
-- decimal LL/LP live (the full save carries them).

DO $migration$
DECLARE
  v_name text;
  v_def text;
  v_defs text[] := ARRAY[]::text[];
  v_names text[] := ARRAY[]::text[];
  v_v02 text;
  v_v03 text;
  v_oid oid;
  i integer;
BEGIN
  -- 1) Capture the deployed definitions that return liquid_limit/plastic_limit.
  FOREACH v_name IN ARRAY ARRAY['upsert_my_calicata_lab_result_v01', 'upsert_my_calicata_lab_result_v02'] LOOP
    FOR v_oid IN
      SELECT p.oid FROM pg_catalog.pg_proc AS p
      JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = v_name
    LOOP
      v_def := pg_catalog.pg_get_functiondef(v_oid);
      IF v_def ~* '(liquid|plastic)_limit\s*::\s*int' THEN
        RAISE EXCEPTION 'CALICATA_LAB_NUMERIC: % casts LL/LP to integer; review manually', v_name;
      END IF;
      v_defs := v_defs || v_def;
      v_names := v_names || (v_oid::regprocedure)::text;
      IF v_name = 'upsert_my_calicata_lab_result_v02' THEN v_v02 := v_def; END IF;
    END LOOP;
  END LOOP;
  IF v_v02 IS NULL THEN
    RAISE EXCEPTION 'CALICATA_LAB_NUMERIC: upsert_my_calicata_lab_result_v02 not found';
  END IF;

  -- 2) Drop them (return type changes need DROP), widen the columns, recreate.
  FOR i IN 1 .. pg_catalog.array_length(v_names, 1) LOOP
    EXECUTE pg_catalog.format('DROP FUNCTION %s', v_names[i]);
  END LOOP;

  ALTER TABLE public.calicata_lab_results
    ALTER COLUMN liquid_limit TYPE numeric(6,2) USING liquid_limit::numeric(6,2),
    ALTER COLUMN plastic_limit TYPE numeric(6,2) USING plastic_limit::numeric(6,2);

  FOR i IN 1 .. pg_catalog.array_length(v_defs, 1) LOOP
    -- \m: whole word, so p_liquid_limit (parameters) stays integer for old clients.
    EXECUTE pg_catalog.regexp_replace(v_defs[i], '\m(liquid_limit|plastic_limit) integer', '\1 numeric', 'g');
    EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_names[i]);
    EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_names[i]);
  END LOOP;

  -- 3) v03: same body as v02, numeric LL/LP parameters and result columns.
  v_v03 := pg_catalog.replace(v_v02, 'upsert_my_calicata_lab_result_v02(', 'upsert_my_calicata_lab_result_v03(');
  v_v03 := pg_catalog.regexp_replace(v_v03, '\m(p_liquid_limit|p_plastic_limit|liquid_limit|plastic_limit) integer', '\1 numeric', 'g');
  IF v_v03 = v_v02
     OR pg_catalog.strpos(v_v03, 'upsert_my_calicata_lab_result_v03(') = 0
     OR pg_catalog.strpos(v_v03, 'p_liquid_limit numeric') = 0
     OR pg_catalog.strpos(v_v03, 'p_plastic_limit numeric') = 0 THEN
    RAISE EXCEPTION 'CALICATA_LAB_NUMERIC: unexpected v02 definition; review manually';
  END IF;
  EXECUTE v_v03;

  SELECT p.oid INTO v_oid FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'upsert_my_calicata_lab_result_v03';
  EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', (v_oid::regprocedure)::text);
  EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION %s TO authenticated', (v_oid::regprocedure)::text);
END
$migration$;

COMMENT ON COLUMN public.calicata_lab_results.liquid_limit IS 'LL (%), MTC E110. numeric(6,2): decimals are preserved.';
COMMENT ON COLUMN public.calicata_lab_results.plastic_limit IS 'LP (%), MTC E111. NULL when not tested or non-plastic (see is_nonplastic).';
