-- InGePlus-Dev only. Draft trash uses the existing Files v07 lifecycle;
-- archived_at (legacy deletion), expenses and associations are preserved.
-- Applied via apply_migration, remote version 20261027145502 (2026-10-27).
BEGIN;

CREATE TABLE private.rendition_draft_trash_requests_v01 (
  actor_id uuid NOT NULL,
  request_id uuid NOT NULL,
  payload jsonb NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (actor_id, request_id)
);
ALTER TABLE private.rendition_draft_trash_requests_v01 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.rendition_draft_trash_requests_v01 FROM PUBLIC, anon, authenticated;

INSERT INTO private.activity_event_catalog
 (code,module,entity_type,project_id_required,entity_id_required,entity_id_equals_project_id,
 metadata_allowed,allowed_metadata_keys,active,description,maximum_metadata_bytes)
VALUES ('RENDITION_DRAFT_TRASHED','RENDITIONS','RENDITION',false,true,false,true,
 ARRAY['result_code','node_id','request_id'],true,'Borrador enviado a la Papelera de Files.',1024)
ON CONFLICT (code) DO NOTHING;

CREATE FUNCTION public.trash_my_rendition_draft_v01(
  p_rendition_id uuid, p_expected_row_version bigint, p_request_id uuid
)
RETURNS TABLE(rendition_id uuid, row_version bigint, node_id uuid,
              node_version bigint, lifecycle text, result_code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE
  actor uuid := auth.uid();
  draft public.renditions%ROWTYPE;
  doc public.document_nodes%ROWTYPE;
  binding public.document_smart_bindings%ROWTYPE;
  saved private.rendition_draft_trash_requests_v01%ROWTYPE;
  payload jsonb;
  roots jsonb;
  plan jsonb;
  result jsonb;
BEGIN
  IF actor IS NULL OR NOT private.is_active_profile() THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF p_request_id IS NULL THEN RAISE EXCEPTION 'RENDITION_REQUEST_ID_REQUIRED'; END IF;
  payload := jsonb_build_object('rendition_id',p_rendition_id,'version',p_expected_row_version);
  PERFORM pg_advisory_xact_lock(hashtextextended('rendition-trash:'||actor::text||p_request_id::text,3507));
  SELECT * INTO saved FROM private.rendition_draft_trash_requests_v01 t
    WHERE t.actor_id=actor AND t.request_id=p_request_id;
  IF FOUND THEN
    IF saved.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION 'RENDITION_IDEMPOTENCY_CONFLICT'; END IF;
    RETURN QUERY SELECT (saved.result->>'rendition_id')::uuid,
      (saved.result->>'row_version')::bigint,(saved.result->>'node_id')::uuid,
      (saved.result->>'node_version')::bigint,saved.result->>'lifecycle','IDEMPOTENT_REPLAY'::text;
    RETURN;
  END IF;
  -- Same lock order as Files lifecycle/recovery: global, space, node, domain.
  PERFORM pg_advisory_xact_lock(20261010,3504);
  PERFORM pg_advisory_xact_lock(6041106);
  SELECT * INTO binding FROM public.document_smart_bindings b WHERE b.rendition_id=p_rendition_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'RENDITION_DOCUMENT_LOCATION_REQUIRED'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(binding.space_id::text,3502));
  PERFORM 1 FROM public.document_spaces s WHERE s.id=binding.space_id FOR UPDATE;
  SELECT * INTO doc FROM public.document_nodes n
    WHERE n.id=binding.node_id AND n.space_id=binding.space_id FOR UPDATE;
  SELECT * INTO draft FROM public.renditions r
    WHERE r.id=p_rendition_id AND r.owner_user_id=actor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RENDITION_NOT_FOUND_OR_FORBIDDEN'; END IF;
  IF draft.status<>'BORRADOR' OR draft.current_version_id IS NOT NULL
    OR draft.archived_at IS NOT NULL
    OR EXISTS(SELECT 1 FROM public.rendition_versions v WHERE v.rendition_id=draft.id)
    THEN RAISE EXCEPTION 'RENDITION_NOT_EDITABLE'; END IF;
  IF draft.is_blocked THEN RAISE EXCEPTION 'RENDITION_BLOCKED'; END IF;
  IF p_expected_row_version IS NULL OR p_expected_row_version<>draft.row_version
    THEN RAISE EXCEPTION 'RENDITION_VERSION_CONFLICT'; END IF;
  IF doc.id IS NULL OR doc.lifecycle<>'ACTIVE' OR doc.node_kind<>'SMART_DOCUMENT'
    THEN RAISE EXCEPTION 'RENDITION_DOCUMENT_NOT_ACTIVE'; END IF;
  -- Bump the domain CAS while the node is ACTIVE. No expense is archived or deleted.
  UPDATE public.renditions r SET row_version=r.row_version+1,
    updated_at=clock_timestamp(),updated_by=actor
    WHERE r.id=draft.id RETURNING r.* INTO draft;
  roots := jsonb_build_array(jsonb_build_object('id',doc.id,'version',doc.node_version));
  plan := public.preview_files_lifecycle_v07(roots,'TRASH');
  PERFORM public.mutate_files_lifecycle_v07(roots,'TRASH',p_request_id,plan->>'token',true);
  SELECT * INTO doc FROM public.document_nodes n WHERE n.id=doc.id;
  IF doc.lifecycle<>'TRASHED' THEN RAISE EXCEPTION 'RENDITION_TRASH_INVALID_RESPONSE'; END IF;
  result := jsonb_build_object('rendition_id',draft.id,'row_version',draft.row_version,
    'node_id',doc.id,'node_version',doc.node_version,'lifecycle','TRASHED');
  INSERT INTO private.rendition_draft_trash_requests_v01(actor_id,request_id,payload,result)
    VALUES(actor,p_request_id,payload,result);
  PERFORM private.write_activity_log('RENDITION_DRAFT_TRASHED',NULL,draft.id,
    private.rendition_client_platform_v01(),'Borrador enviado a la Papelera.',
    jsonb_build_object('result_code','TRASHED','node_id',doc.id,'request_id',p_request_id));
  RETURN QUERY SELECT draft.id,draft.row_version,doc.id,doc.node_version,'TRASHED'::text,'TRASHED'::text;
END;
$function$;
REVOKE ALL ON FUNCTION public.trash_my_rendition_draft_v01(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.trash_my_rendition_draft_v01(uuid,bigint,uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
