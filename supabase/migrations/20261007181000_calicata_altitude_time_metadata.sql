-- 20261007181000_calicata_altitude_time_metadata
--
-- Persistencia remota (cross-device) de datos que hasta ahora solo vivían en el
-- header local / JSON portable de Android:
--   * start_time          = hora de la ficha (Android hora_inicio, opcional).
--                           Par de start_date (fecha de la ficha).
--   * altitude_*          = metadato de la cota. El VALOR sigue siendo
--                           altitude_m (columna existente, no se duplica).
--   * altitude_evidence   = evidencias del servicio de elevación (fuentes,
--                           valores, referencia vertical) para auditoría.
-- Además habilita la operación 'elevation' en la cuota compartida de IA (la
-- Edge Function resolve-calicata-elevation usa Gemini como validador).
--
-- Columnas nulas y sin default: Web y clientes existentes no cambian; la RPC
-- get_my_calicata_snapshot_v01 usa to_jsonb(c), así que el pull las incluye.
-- No son campos "live" (is_calicata_live_field_v01 no cambia): viajan con el
-- guardado completo (CAS).
--
-- Idempotente: ADD COLUMN IF NOT EXISTS; constraints creadas solo si faltan.
-- Reversión manual (pierde los datos de estas columnas):
--   ALTER TABLE public.calicatas DROP COLUMN IF EXISTS start_time,
--     DROP COLUMN IF EXISTS altitude_source, DROP COLUMN IF EXISTS altitude_mode,
--     DROP COLUMN IF EXISTS altitude_confidence, DROP COLUMN IF EXISTS altitude_accuracy_m,
--     DROP COLUMN IF EXISTS altitude_vertical_reference, DROP COLUMN IF EXISTS altitude_resolved_at,
--     DROP COLUMN IF EXISTS altitude_evidence;
--   y restaurar inge_gemini_quota_operation_check / consume_inge_gemini_quota a ('chat','live-token').

ALTER TABLE public.calicatas
  ADD COLUMN IF NOT EXISTS start_time time without time zone,
  ADD COLUMN IF NOT EXISTS altitude_source text,
  ADD COLUMN IF NOT EXISTS altitude_mode text,
  ADD COLUMN IF NOT EXISTS altitude_confidence text,
  ADD COLUMN IF NOT EXISTS altitude_accuracy_m numeric,
  ADD COLUMN IF NOT EXISTS altitude_vertical_reference text,
  ADD COLUMN IF NOT EXISTS altitude_resolved_at timestamptz,
  ADD COLUMN IF NOT EXISTS altitude_evidence jsonb;

COMMENT ON COLUMN public.calicatas.start_time IS 'Hora de la ficha (opcional). Rótulo documental de las fotos junto a start_date.';
COMMENT ON COLUMN public.calicatas.altitude_source IS 'Origen de altitude_m: MANUAL | GOOGLE_ELEVATION | DEM | GPS_ELIPSOIDAL.';
COMMENT ON COLUMN public.calicatas.altitude_mode IS 'MANUAL (escrita/confirmada por el técnico) | AUTOMATICA.';
COMMENT ON COLUMN public.calicatas.altitude_confidence IS 'ALTA | MEDIA | BAJA (servicio de elevación).';
COMMENT ON COLUMN public.calicatas.altitude_accuracy_m IS 'Exactitud vertical declarada de la fuente (m).';
COMMENT ON COLUMN public.calicatas.altitude_vertical_reference IS 'terrain_msl (terreno, m.s.n.m.) | ellipsoid (GPS) | unknown.';
COMMENT ON COLUMN public.calicatas.altitude_resolved_at IS 'Momento en que el servicio de elevación resolvió la cota.';
COMMENT ON COLUMN public.calicatas.altitude_evidence IS 'Evidencias del servicio de elevación (array JSON; ninguna cifra la genera la IA).';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'calicatas_altitude_source_check'
                 AND conrelid = 'public.calicatas'::regclass) THEN
    ALTER TABLE public.calicatas ADD CONSTRAINT calicatas_altitude_source_check
      CHECK (altitude_source IS NULL OR altitude_source IN ('MANUAL', 'GOOGLE_ELEVATION', 'DEM', 'GPS_ELIPSOIDAL'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'calicatas_altitude_mode_check'
                 AND conrelid = 'public.calicatas'::regclass) THEN
    ALTER TABLE public.calicatas ADD CONSTRAINT calicatas_altitude_mode_check
      CHECK (altitude_mode IS NULL OR altitude_mode IN ('MANUAL', 'AUTOMATICA'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'calicatas_altitude_confidence_check'
                 AND conrelid = 'public.calicatas'::regclass) THEN
    ALTER TABLE public.calicatas ADD CONSTRAINT calicatas_altitude_confidence_check
      CHECK (altitude_confidence IS NULL OR altitude_confidence IN ('ALTA', 'MEDIA', 'BAJA'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'calicatas_altitude_vertical_reference_check'
                 AND conrelid = 'public.calicatas'::regclass) THEN
    ALTER TABLE public.calicatas ADD CONSTRAINT calicatas_altitude_vertical_reference_check
      CHECK (altitude_vertical_reference IS NULL OR altitude_vertical_reference IN ('terrain_msl', 'ellipsoid', 'unknown'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'calicatas_altitude_accuracy_check'
                 AND conrelid = 'public.calicatas'::regclass) THEN
    ALTER TABLE public.calicatas ADD CONSTRAINT calicatas_altitude_accuracy_check
      CHECK (altitude_accuracy_m IS NULL OR (altitude_accuracy_m >= 0 AND altitude_accuracy_m < 10000));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'calicatas_altitude_evidence_check'
                 AND conrelid = 'public.calicatas'::regclass) THEN
    ALTER TABLE public.calicatas ADD CONSTRAINT calicatas_altitude_evidence_check
      CHECK (altitude_evidence IS NULL OR (pg_catalog.jsonb_typeof(altitude_evidence) = 'array'
                                           AND pg_catalog.octet_length(altitude_evidence::text) <= 16384));
  END IF;
END $$;

-- Cuota compartida de IA: operación 'elevation' (validación Gemini de la cota).
ALTER TABLE public.inge_gemini_quota DROP CONSTRAINT IF EXISTS inge_gemini_quota_operation_check;
ALTER TABLE public.inge_gemini_quota ADD CONSTRAINT inge_gemini_quota_operation_check
  CHECK (operation IN ('chat', 'live-token', 'elevation'));

CREATE OR REPLACE FUNCTION public.consume_inge_gemini_quota(p_operation text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_user uuid := auth.uid(); v_count integer; v_limit integer;
BEGIN
  IF v_user IS NULL OR p_operation NOT IN ('chat', 'live-token', 'elevation') THEN
    RAISE EXCEPTION 'Unauthenticated or invalid operation';
  END IF;
  v_limit := CASE WHEN p_operation = 'live-token' THEN 3 WHEN p_operation = 'elevation' THEN 30 ELSE 20 END;
  DELETE FROM public.inge_gemini_quota WHERE user_id = v_user AND bucket < now() - interval '1 day';
  INSERT INTO public.inge_gemini_quota(user_id, operation, bucket, used)
    VALUES (v_user, p_operation, date_trunc('minute', now()), 1)
  ON CONFLICT (user_id, operation, bucket) DO UPDATE
    SET used = public.inge_gemini_quota.used + 1
    WHERE public.inge_gemini_quota.used < v_limit
  RETURNING used INTO v_count;
  RETURN v_count IS NOT NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.consume_inge_gemini_quota(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.consume_inge_gemini_quota(text) TO authenticated;
