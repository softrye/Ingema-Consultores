-- Active list must exclude Files archive/trash, while archived getters remain readable.
BEGIN;
CREATE OR REPLACE FUNCTION public.list_renditions_effective_v06(p_limit integer DEFAULT 50, p_after_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_after_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND status = 'ACTIVO'
  ) THEN
    RAISE EXCEPTION 'PROFILE_NOT_ACTIVE';
  END IF;
  IF COALESCE(p_limit, 50) NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'RENDITION_INVALID_LIMIT';
  END IF;
  IF (p_after_updated_at IS NULL) <> (p_after_id IS NULL) THEN
    RAISE EXCEPTION 'RENDITION_INVALID_CURSOR';
  END IF;

  RETURN QUERY
  SELECT jsonb_build_object(
    'id', r.id,
    'visible_code', r.visible_code,
    'display_name', r.display_name,
    'period_start', r.period_start,
    'period_end', r.period_end,
    'status', r.status,
    'current_version_id', r.current_version_id,
    'base_currency_code', r.base_currency_code,
    'updated_at', r.updated_at,
    'row_version', r.row_version,
    'owner_user_id', r.owner_user_id,
    'owner_name', COALESCE(NULLIF(btrim(p.full_name), ''), 'Propietario'),
    'is_blocked', r.is_blocked,
    -- Mismo contrato de proyectos que get_rendition_effective_v06:
    -- un solo pull inicial permite filtrar por cualquiera de sus proyectos.
    'projects', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', pr.id,
          'code', pr.code,
          'name', pr.name,
          'is_primary', rp.is_primary
        ) ORDER BY rp.is_primary DESC, pr.id
      )
      FROM public.rendition_projects rp
      JOIN public.projects pr ON pr.id = rp.project_id
      WHERE rp.rendition_id = r.id
        AND rp.archived_at IS NULL
    ), '[]'::jsonb)
  )
  FROM public.renditions r
  JOIN public.profiles p ON p.id = r.owner_user_id
  WHERE r.archived_at IS NULL
    AND private.files_archive_domain_lifecycle_v07(r.id) = 'ACTIVE'
    AND private.rendition_readable_v02(auth.uid(), r.id)
    AND (
      p_after_updated_at IS NULL
      OR (r.updated_at, r.id) < (p_after_updated_at, p_after_id)
    )
  ORDER BY r.updated_at DESC, r.id DESC
  LIMIT COALESCE(p_limit, 50);
END;
$function$
;
NOTIFY pgrst, 'reload schema';
COMMIT;
