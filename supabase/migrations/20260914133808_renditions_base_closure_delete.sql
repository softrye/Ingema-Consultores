CREATE OR REPLACE FUNCTION public.delete_my_rendition_expense_v01(p_rendition_id uuid, p_expense_id uuid, p_expected_expense_row_version bigint, p_expected_rendition_row_version bigint)
 RETURNS TABLE(expense_id uuid, expense_row_version bigint, rendition_row_version bigint, result_code text, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_at timestamptz := pg_catalog.transaction_timestamp();
  v_rendition public.renditions%ROWTYPE;
  v_expense public.rendition_expenses%ROWTYPE;
  v_expense_version bigint;
  v_rendition_version bigint;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION USING ERRCODE = '28000', MESSAGE = 'AUTH_REQUIRED'; END IF;
  PERFORM 1 FROM public.profiles AS actor_profile
  WHERE actor_profile.id = v_actor
    AND actor_profile.status = 'ACTIVO'::public.profile_status;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'PROFILE_NOT_ACTIVE'; END IF;

  SELECT rendition.* INTO v_rendition FROM public.renditions AS rendition
  WHERE rendition.id = p_rendition_id AND rendition.owner_user_id = v_actor
    AND rendition.archived_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RENDITION_NOT_FOUND_OR_FORBIDDEN'; END IF;
  IF v_rendition.status <> 'BORRADOR' OR v_rendition.current_version_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RENDITION_NOT_EDITABLE';
  END IF;

  SELECT expense.* INTO v_expense FROM public.rendition_expenses AS expense
  WHERE expense.id = p_expense_id AND expense.rendition_id = p_rendition_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RENDITION_EXPENSE_NOT_FOUND_OR_FORBIDDEN'; END IF;
  IF v_expense.archived_at IS NOT NULL THEN
    RETURN QUERY SELECT v_expense.id, v_expense.row_version, v_rendition.row_version, 'IDEMPOTENT_REPLAY'::text, v_expense.updated_at;
    RETURN;
  END IF;
  IF p_expected_rendition_row_version IS NULL OR p_expected_rendition_row_version <> v_rendition.row_version THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RENDITION_VERSION_CONFLICT';
  END IF;
  IF p_expected_expense_row_version IS NULL OR p_expected_expense_row_version <> v_expense.row_version THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RENDITION_EXPENSE_VERSION_CONFLICT';
  END IF;
  IF v_expense.review_status <> 'PENDIENTE' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RENDITION_NOT_EDITABLE';
  END IF;

  UPDATE public.rendition_expenses AS expense
  SET archived_at = v_at, archived_by = v_actor, updated_at = v_at,
      updated_by = v_actor, row_version = expense.row_version + 1
  WHERE expense.id = v_expense.id AND expense.row_version = p_expected_expense_row_version
  RETURNING expense.row_version INTO v_expense_version;

  UPDATE public.rendition_expense_attachments AS attachment
  SET archived_at=v_at, archived_by=v_actor, row_version=attachment.row_version+1
  WHERE attachment.expense_id=v_expense.id AND attachment.archived_at IS NULL;

  UPDATE public.renditions AS rendition
  SET updated_at = v_at, updated_by = v_actor, row_version = rendition.row_version + 1
  WHERE rendition.id = v_rendition.id AND rendition.row_version = p_expected_rendition_row_version
  RETURNING rendition.row_version INTO v_rendition_version;

  IF v_expense_version IS NULL THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RENDITION_EXPENSE_VERSION_CONFLICT'; END IF;
  IF v_rendition_version IS NULL THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RENDITION_VERSION_CONFLICT'; END IF;

  PERFORM private.write_activity_log(
    'RENDITION_EXPENSE_ARCHIVED',
    v_expense.project_id,
    p_rendition_id,
    private.rendition_client_platform_v01(),
    'Se archivo un gasto de la rendicion.',
    pg_catalog.jsonb_build_object(
      'expense_id', v_expense.id::text,
      'row_version', v_rendition_version,
      'result_code', 'DELETED'
    )
  );

  RETURN QUERY SELECT v_expense.id, v_expense_version,
    v_rendition_version, 'DELETED'::text, v_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_my_rendition_draft_v01(p_rendition_id uuid, p_expected_row_version bigint)
RETURNS TABLE(rendition_id uuid, row_version bigint, archived_at timestamptz, result_code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.renditions%ROWTYPE;
  v_at timestamptz := pg_catalog.transaction_timestamp();
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='AUTH_REQUIRED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=v_actor AND p.status='ACTIVO'::public.profile_status) THEN
    RAISE EXCEPTION 'PROFILE_NOT_ACTIVE';
  END IF;
  SELECT r.* INTO v_row FROM public.renditions r
  WHERE r.id=p_rendition_id AND r.owner_user_id=v_actor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RENDITION_NOT_FOUND_OR_FORBIDDEN'; END IF;
  IF v_row.status <> 'BORRADOR' OR v_row.current_version_id IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.rendition_versions v WHERE v.rendition_id=v_row.id) THEN
    RAISE EXCEPTION 'RENDITION_NOT_EDITABLE';
  END IF;
  IF v_row.archived_at IS NOT NULL THEN
    RETURN QUERY SELECT v_row.id,v_row.row_version,v_row.archived_at,'IDEMPOTENT_REPLAY'::text; RETURN;
  END IF;
  IF p_expected_row_version IS NULL OR v_row.row_version<>p_expected_row_version THEN
    RAISE EXCEPTION 'RENDITION_VERSION_CONFLICT';
  END IF;
  UPDATE public.rendition_expense_attachments a SET archived_at=v_at,archived_by=v_actor,row_version=a.row_version+1
  WHERE a.rendition_id=v_row.id AND a.archived_at IS NULL;
  UPDATE public.rendition_expenses e SET archived_at=v_at,archived_by=v_actor,updated_at=v_at,updated_by=v_actor,row_version=e.row_version+1
  WHERE e.rendition_id=v_row.id AND e.archived_at IS NULL;
  UPDATE public.rendition_projects p SET archived_at=v_at,archived_by=v_actor
  WHERE p.rendition_id=v_row.id AND p.archived_at IS NULL;
  UPDATE public.renditions r SET archived_at=v_at,archived_by=v_actor,updated_at=v_at,updated_by=v_actor,row_version=r.row_version+1
  WHERE r.id=v_row.id RETURNING r.* INTO v_row;
  PERFORM private.write_activity_log('RENDITION_DRAFT_ARCHIVED',NULL,v_row.id,
    private.rendition_client_platform_v01(),'Se archivó un borrador de rendición.',
    pg_catalog.jsonb_build_object('result_code','DELETED'));
  RETURN QUERY SELECT v_row.id,v_row.row_version,v_row.archived_at,'DELETED'::text;
END;
$function$;
REVOKE ALL ON FUNCTION public.delete_my_rendition_draft_v01(uuid,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_rendition_draft_v01(uuid,bigint) TO authenticated;
NOTIFY pgrst, 'reload schema';
