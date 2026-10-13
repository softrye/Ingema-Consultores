-- Calicatas / Laboratorio: datos técnicos de laboratorio y clasificación de campo durables.
-- NOT APPLIED by Android tooling (no db push). Additive only: new nullable/defaulted
-- columns, new RPCs; existing RPCs, RLS and Web contracts are untouched.
--
-- A) Técnicos de laboratorio (antes solo locales en Android):
--    d10_mm / d30_mm / d60_mm   (Cu y Cc son derivados: sin columna)
--    is_nonplastic              NP explícito: distinto de "sin ensayo" (LP NULL) y de LP = 0
--    lab_observations           observaciones del ensayo (no las del estrato de campo)
--    visual_classification      'A-8' visual confirmado explícitamente (A-8 no está en el
--                               catálogo AASHTO de `aashto`, por eso va aparte)
-- B) Clasificación de CAMPO: calicata_strata.sucs / aashto ya existen, pero ninguna RPC
--    las escribía; Android enviaba el SUCS de campo como primary_sucs de laboratorio.
--    set_my_calicata_stratum_field_classification_v01 separa ambas fuentes.
-- Confirmación: no requiere columna; el estado final queda en primary_sucs / aashto
-- (laboratorio) frente a calicata_strata.sucs / aashto (campo).

ALTER TABLE public.calicata_lab_results
  ADD COLUMN IF NOT EXISTS d10_mm numeric(10,4),
  ADD COLUMN IF NOT EXISTS d30_mm numeric(10,4),
  ADD COLUMN IF NOT EXISTS d60_mm numeric(10,4),
  ADD COLUMN IF NOT EXISTS is_nonplastic boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS lab_observations text,
  ADD COLUMN IF NOT EXISTS visual_classification text;

ALTER TABLE public.calicata_lab_results
  ADD CONSTRAINT calicata_lab_results_gradation_check CHECK (
    (d10_mm IS NULL OR d10_mm > 0) AND (d30_mm IS NULL OR d30_mm > 0) AND (d60_mm IS NULL OR d60_mm > 0)
    AND (d10_mm IS NULL OR d30_mm IS NULL OR d10_mm <= d30_mm)
    AND (d30_mm IS NULL OR d60_mm IS NULL OR d30_mm <= d60_mm)
    AND (d10_mm IS NULL OR d60_mm IS NULL OR d10_mm <= d60_mm)),
  ADD CONSTRAINT calicata_lab_results_nonplastic_check CHECK (NOT is_nonplastic OR plastic_limit IS NULL),
  ADD CONSTRAINT calicata_lab_results_visual_classification_check CHECK (
    visual_classification IS NULL OR visual_classification = 'A-8'),
  ADD CONSTRAINT calicata_lab_results_lab_observations_length_check CHECK (
    lab_observations IS NULL OR pg_catalog.char_length(lab_observations) <= 2000);

-- Same authorization and row_version CAS as update_my_calicata_stratum_v03.
CREATE OR REPLACE FUNCTION public.set_my_calicata_lab_extension_v01(
  p_project_id uuid, p_calicata_id uuid, p_stratum_id uuid, p_expected_calicata_row_version bigint,
  p_d10_mm numeric, p_d30_mm numeric, p_d60_mm numeric, p_is_nonplastic boolean,
  p_lab_observations text, p_visual_classification text)
RETURNS TABLE (stratum_id uuid, d10_mm numeric, d30_mm numeric, d60_mm numeric, is_nonplastic boolean,
               lab_observations text, visual_classification text, calicata_row_version bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_calicata public.calicatas%ROWTYPE;
  v_new_row_version bigint;
  v_observations text := NULLIF(pg_catalog.btrim(p_lab_observations), '');
  v_visual text := NULLIF(pg_catalog.upper(pg_catalog.btrim(p_visual_classification)), '');
BEGIN
  IF p_expected_calicata_row_version IS NULL OR p_expected_calicata_row_version < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'CALICATA_LAB_EXTENSION: invalid expected row version';
  END IF;
  IF v_visual IS NOT NULL AND v_visual <> 'A-8' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'CALICATA_LAB_EXTENSION: unsupported visual classification';
  END IF;

  SELECT calicata.* INTO v_calicata FROM public.calicatas AS calicata
  WHERE calicata.id = p_calicata_id AND calicata.project_id = p_project_id
  FOR UPDATE;
  IF NOT FOUND OR NOT private.can_mutate_calicata_strata(v_calicata.project_id, v_calicata.created_by, v_calicata.status) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CALICATA_LAB_EXTENSION: mutation is not authorized';
  END IF;
  IF v_calicata.row_version <> p_expected_calicata_row_version THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'CALICATA_STRATA_STALE';
  END IF;
  PERFORM 1 FROM public.calicata_strata AS stratum
  WHERE stratum.id = p_stratum_id AND stratum.calicata_id = p_calicata_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CALICATA_LAB_EXTENSION: stratum is not available';
  END IF;

  UPDATE public.calicata_lab_results AS lab
  SET d10_mm = p_d10_mm, d30_mm = p_d30_mm, d60_mm = p_d60_mm,
      is_nonplastic = COALESCE(p_is_nonplastic, false),
      plastic_limit = CASE WHEN COALESCE(p_is_nonplastic, false) THEN NULL ELSE lab.plastic_limit END,
      lab_observations = v_observations, visual_classification = v_visual,
      updated_by = auth.uid(), updated_at = pg_catalog.now()
  WHERE lab.calicata_id = p_calicata_id AND lab.stratum_id = p_stratum_id;
  IF NOT FOUND THEN
    INSERT INTO public.calicata_lab_results (project_id, calicata_id, stratum_id, d10_mm, d30_mm, d60_mm,
      is_nonplastic, lab_observations, visual_classification, created_by, updated_by)
    VALUES (p_project_id, p_calicata_id, p_stratum_id, p_d10_mm, p_d30_mm, p_d60_mm,
      COALESCE(p_is_nonplastic, false), v_observations, v_visual, auth.uid(), auth.uid());
  END IF;

  UPDATE public.calicatas AS calicata SET updated_at = pg_catalog.now()
  WHERE calicata.id = p_calicata_id
  RETURNING calicata.row_version INTO v_new_row_version;

  RETURN QUERY
  SELECT lab.stratum_id, lab.d10_mm, lab.d30_mm, lab.d60_mm, lab.is_nonplastic,
         lab.lab_observations, lab.visual_classification, v_new_row_version
  FROM public.calicata_lab_results AS lab
  WHERE lab.calicata_id = p_calicata_id AND lab.stratum_id = p_stratum_id;
END
$function$;

-- Campo (Perfil): SUCS/AASHTO observados en campo; RA nunca es SUCS ni AASHTO.
CREATE OR REPLACE FUNCTION public.set_my_calicata_stratum_field_classification_v01(
  p_project_id uuid, p_calicata_id uuid, p_stratum_id uuid, p_expected_calicata_row_version bigint,
  p_sucs text, p_aashto text)
RETURNS TABLE (stratum_id uuid, sucs text, aashto text, calicata_row_version bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_calicata public.calicatas%ROWTYPE;
  v_new_row_version bigint;
  v_sucs text := NULLIF(pg_catalog.btrim(p_sucs), '');
  v_aashto text := NULLIF(pg_catalog.btrim(p_aashto), '');
BEGIN
  IF p_expected_calicata_row_version IS NULL OR p_expected_calicata_row_version < 1 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'CALICATA_FIELD_CLASSIFICATION: invalid expected row version';
  END IF;
  IF v_sucs IS NOT NULL AND (pg_catalog.upper(v_sucs) = 'RA' OR v_sucs !~ '^[A-Za-z]{1,2}(-[A-Za-z]{1,2})?$') THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'CALICATA_FIELD_CLASSIFICATION: unsupported SUCS';
  END IF;
  IF v_aashto IS NOT NULL AND v_aashto <> ALL (ARRAY['A-1-a', 'A-1-b', 'A-2-4', 'A-2-5', 'A-2-6', 'A-2-7',
      'A-3', 'A-4', 'A-5', 'A-6', 'A-7-5', 'A-7-6']::text[]) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'CALICATA_FIELD_CLASSIFICATION: unsupported AASHTO';
  END IF;

  SELECT calicata.* INTO v_calicata FROM public.calicatas AS calicata
  WHERE calicata.id = p_calicata_id AND calicata.project_id = p_project_id
  FOR UPDATE;
  IF NOT FOUND OR NOT private.can_mutate_calicata_strata(v_calicata.project_id, v_calicata.created_by, v_calicata.status) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CALICATA_FIELD_CLASSIFICATION: mutation is not authorized';
  END IF;
  IF v_calicata.row_version <> p_expected_calicata_row_version THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'CALICATA_STRATA_STALE';
  END IF;

  UPDATE public.calicata_strata AS stratum
  SET sucs = v_sucs, aashto = v_aashto, updated_at = pg_catalog.now()
  WHERE stratum.id = p_stratum_id AND stratum.calicata_id = p_calicata_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CALICATA_FIELD_CLASSIFICATION: stratum is not available';
  END IF;

  UPDATE public.calicatas AS calicata SET updated_at = pg_catalog.now()
  WHERE calicata.id = p_calicata_id
  RETURNING calicata.row_version INTO v_new_row_version;

  RETURN QUERY SELECT p_stratum_id, v_sucs, v_aashto, v_new_row_version;
END
$function$;

REVOKE ALL ON FUNCTION public.set_my_calicata_lab_extension_v01(uuid, uuid, uuid, bigint, numeric, numeric, numeric, boolean, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_calicata_lab_extension_v01(uuid, uuid, uuid, bigint, numeric, numeric, numeric, boolean, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.set_my_calicata_stratum_field_classification_v01(uuid, uuid, uuid, bigint, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_calicata_stratum_field_classification_v01(uuid, uuid, uuid, bigint, text, text) TO authenticated;
