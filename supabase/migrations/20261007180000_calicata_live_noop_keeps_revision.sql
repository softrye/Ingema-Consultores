-- 20261007180000_calicata_live_noop_keeps_revision
--
-- Causa demostrada en DEV (transacción revertida, ficha temporal):
--   autosave (CAS) row_version 2->3; live title Z->Z (valor ya vigente) => el
--   trigger contó 0 columnas cambiadas, no lo reconoció como cambio live y
--   sumó +1 (3->4) sin devolver la revisión; el Guardar siguiente con CAS=3
--   actualizó 0 filas => 40001 contra una escritura propia.
--
-- Regla: UN NO-OP NO CAMBIA row_version.
--  1) apply_calicata_field_change_v02 (FICHA): si el valor nuevo IS NOT DISTINCT
--     FROM el vigente no ejecuta UPDATE (sin updated_at, sin row_version, sin
--     triggers de auditoría). El contrato (RETURNS calicata_field_changes) no cambia.
--  2) Defensa en profundidad SOLO en la ruta live (flag calicata.live_field_change):
--     is_calicata_live_field_change_v01 acepta 0 o 1 columnas live cambiadas.
--     El trigger global NO se toca: las RPC de estratos/muestras/laboratorio y el
--     PATCH completo siguen moviendo row_version a propósito (CAS del padre).
--
-- Idempotente (CREATE OR REPLACE con la misma firma y grants).
-- Reversión manual: volver a aplicar las definiciones previas guardadas en
-- supabase/rollback/20261007180000_calicata_live_noop_keeps_revision.rollback.sql.

CREATE OR REPLACE FUNCTION private.is_calicata_live_field_change_v01(p_old public.calicatas, p_new public.calicatas)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  WITH changed AS (
    SELECT after.key
    FROM pg_catalog.jsonb_each(pg_catalog.to_jsonb(p_new)) AS after
    JOIN pg_catalog.jsonb_each(pg_catalog.to_jsonb(p_old)) AS before
      ON before.key = after.key
    WHERE after.value IS DISTINCT FROM before.value
      AND after.key <> 'updated_at'
      AND after.key <> 'row_version'
  )
  -- 0 columnas (no-op) o exactamente 1 columna live: el token no se mueve.
  SELECT pg_catalog.count(*) <= 1
     AND COALESCE(pg_catalog.bool_and(private.is_calicata_live_field_v01(key)), true)
  FROM changed;
$function$;

CREATE OR REPLACE FUNCTION public.apply_calicata_field_change_v02(p_project_id uuid, p_calicata_id uuid, p_target_type public.calicata_change_target, p_target_id uuid, p_change_id uuid, p_field text, p_value text, p_client_at timestamp with time zone)
 RETURNS public.calicata_field_changes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_calicata public.calicatas;
  v_column_type text;
  v_target_table text;
  v_row_id uuid;
  v_winner public.calicata_field_changes;
  v_unchanged boolean;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '28000', MESSAGE = 'CALICATA_FIELD_CHANGE: authentication required';
  END IF;
  IF p_change_id IS NULL OR p_client_at IS NULL OR p_target_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22004', MESSAGE = 'CALICATA_FIELD_CHANGE: change id, target and client time are required';
  END IF;
  IF NOT private.is_calicata_change_field_v01(p_target_type, p_field) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'CALICATA_FIELD_CHANGE: unknown field';
  END IF;

  SELECT * INTO v_calicata
  FROM public.calicatas
  WHERE id = p_calicata_id AND project_id = p_project_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'CALICATA_FIELD_CHANGE: ficha not found';
  END IF;

  -- Each part answers to the rules it already had: the ficha's own columns to
  -- the media write predicate, a corte and a sample to the one their RPCs
  -- consult.
  IF p_target_type = 'CALICATA'::public.calicata_change_target THEN
    IF p_target_id <> p_calicata_id THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'CALICATA_FIELD_CHANGE: target is not this ficha';
    END IF;
    IF NOT private.can_write_calicata_media_v01(p_project_id, p_calicata_id) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CALICATA_FIELD_CHANGE: not authorized to edit this ficha';
    END IF;
    v_target_table := 'public.calicatas';
    v_row_id := p_calicata_id;
  ELSE
    IF NOT private.can_mutate_calicata_strata(v_calicata.project_id, v_calicata.created_by, v_calicata.status) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CALICATA_FIELD_CHANGE: not authorized to edit this ficha';
    END IF;
    -- Both a corte and a sample are addressed by the corte's id: it is what the
    -- sheet knows, and for the laboratory it is also the unique key of a row
    -- that may not exist yet.
    IF NOT EXISTS (
      SELECT 1 FROM public.calicata_strata
      WHERE id = p_target_id AND calicata_id = p_calicata_id
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'CALICATA_FIELD_CHANGE: corte not found on this ficha';
    END IF;

    IF p_target_type = 'STRATUM'::public.calicata_change_target THEN
      v_target_table := 'public.calicata_strata';
      v_row_id := p_target_id;
    ELSE
      -- The first value anybody types for a sample is also what creates it.
      INSERT INTO public.calicata_lab_results (
        project_id, calicata_id, stratum_id, created_by, updated_by
      )
      VALUES (p_project_id, p_calicata_id, p_target_id, v_actor, v_actor)
      ON CONFLICT (stratum_id) DO NOTHING;

      SELECT id INTO v_row_id
      FROM public.calicata_lab_results
      WHERE stratum_id = p_target_id;
      v_target_table := 'public.calicata_lab_results';
    END IF;
  END IF;

  -- A ficha that has left draft is being closed, not filled in.
  IF v_calicata.status <> 'BORRADOR'::public.calicata_status THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CALICATA_FIELD_CHANGE: live editing is for drafts only';
  END IF;

  INSERT INTO public.calicata_field_changes (
    id, project_id, calicata_id, target_type, target_id, field, value, author_id, client_at
  )
  VALUES (
    p_change_id, p_project_id, p_calicata_id, p_target_type, p_target_id, p_field, p_value, v_actor, p_client_at
  )
  ON CONFLICT (id) DO NOTHING;

  SELECT * INTO v_winner
  FROM public.calicata_field_changes
  WHERE calicata_id = p_calicata_id
    AND target_type = p_target_type
    AND target_id = p_target_id
    AND field = p_field
  ORDER BY client_at DESC, id DESC
  LIMIT 1;

  IF v_winner.id = p_change_id THEN
    SELECT pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
    INTO v_column_type
    FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid = v_target_table::regclass
      AND attribute.attname = p_field
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped;

    IF p_target_type = 'CALICATA'::public.calicata_change_target THEN
      -- No-op (valor ya vigente, comparado con el tipo real de la columna:
      -- 661554.00 = 661554): no hay escritura, así que row_version, updated_at
      -- y la auditoría quedan exactamente como estaban.
      EXECUTE pg_catalog.format(
        'SELECT %I IS NOT DISTINCT FROM $1::%s FROM public.calicatas WHERE id = $2',
        p_field,
        v_column_type
      )
      INTO v_unchanged
      USING nullif(p_value, ''), v_row_id;

      IF NOT COALESCE(v_unchanged, false) THEN
        -- The token stays where it is for this write, and the trigger checks
        -- that claim against what actually changed before it believes it.
        PERFORM pg_catalog.set_config('calicata.live_field_change', 'on', true);
        EXECUTE pg_catalog.format(
          'UPDATE public.calicatas SET %I = $1::%s, updated_at = pg_catalog.now() WHERE id = $2',
          p_field,
          v_column_type
        )
        USING nullif(p_value, ''), v_row_id;
        PERFORM pg_catalog.set_config('calicata.live_field_change', 'off', true);
      END IF;
    ELSIF p_target_type = 'STRATUM'::public.calicata_change_target THEN
      -- No flag here: writing a corte does not touch the ficha's row, so its
      -- token was never going to move.
      EXECUTE pg_catalog.format(
        'UPDATE public.calicata_strata SET %I = $1::%s WHERE id = $2',
        p_field,
        v_column_type
      )
      USING nullif(p_value, ''), v_row_id;
    ELSE
      -- `updated_by` is written here because this table keeps one and the
      -- person who typed the value is exactly what it is for.
      EXECUTE pg_catalog.format(
        'UPDATE public.calicata_lab_results SET %I = $1::%s, updated_by = $3, updated_at = pg_catalog.now() WHERE id = $2',
        p_field,
        v_column_type
      )
      USING nullif(p_value, ''), v_row_id, v_actor;
    END IF;
  END IF;

  RETURN v_winner;
END;
$function$;
