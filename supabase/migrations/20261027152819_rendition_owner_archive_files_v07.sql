-- Owner rendition archive, Files v07. InGePlus-Dev ONLY.
-- Preserves status, expenses, attachments and immutable versions; no business-row deletion.
-- Backups: docs/sql_proposals/BACKUP_20261027_owner_archive_files_v07.sql
BEGIN;

CREATE FUNCTION private.rendition_owned_file_v01(p_actor uuid,p_node uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
 SELECT EXISTS(SELECT 1 FROM public.profiles p
 JOIN public.renditions r ON r.owner_user_id=p.id AND r.archived_at IS NULL
 JOIN public.document_smart_bindings b ON b.rendition_id=r.id
 JOIN public.document_nodes n ON n.id=b.node_id AND n.space_id=b.space_id
 WHERE p.id=p_actor AND p.status='ACTIVO' AND n.id=p_node AND n.node_kind='SMART_DOCUMENT');
$function$;
CREATE FUNCTION private.rendition_owned_archived_file_v01(p_actor uuid,p_node uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
 SELECT private.rendition_owned_file_v01(p_actor,p_node) AND EXISTS(
 SELECT 1 FROM private.files_recovery_tree_v07() t WHERE t.id=p_node
 AND t.kind='SMART_DOCUMENT' AND t.own_lifecycle='ARCHIVED'
 AND t.effective_lifecycle='ARCHIVED' AND t.recovery_root_id=p_node);
$function$;
CREATE FUNCTION private.rendition_file_archive_eligible_v01(p_actor uuid,p_node uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
 SELECT private.rendition_owned_file_v01(p_actor,p_node) AND EXISTS(
 SELECT 1 FROM public.document_smart_bindings b JOIN public.renditions r ON r.id=b.rendition_id
 JOIN private.files_recovery_tree_v07() t ON t.id=b.node_id
 WHERE b.node_id=p_node AND t.effective_lifecycle='ACTIVE' AND t.own_lifecycle='ACTIVE'
 AND NOT r.is_blocked AND r.status IN('BORRADOR','OBSERVADO','APROBADO','REVISADO','ARCHIVADO','EXPORTADO')
 AND NOT EXISTS(SELECT 1 FROM private.rendition_edit_requests_v03 q WHERE q.rendition_id=r.id AND q.status='PENDING'));
$function$;
REVOKE ALL ON FUNCTION private.rendition_owned_file_v01(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.rendition_owned_archived_file_v01(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.rendition_file_archive_eligible_v01(uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.list_files_archive_children_v07(p_parent_id uuid DEFAULT NULL::uuid, p_after_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE items jsonb; breadcrumb jsonb; more boolean;
BEGIN
 IF NOT private.is_active_profile() THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
 -- Each entry is filtered by Files ACL plus the narrowly scoped owner exception.
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'INVALID_ARCHIVE_LIMIT'; END IF;
 IF p_parent_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private.files_recovery_tree_v07() t
  WHERE t.id=p_parent_id AND t.effective_lifecycle='ARCHIVED' AND t.kind IN('SPACE','FOLDER')
   AND private.files_recovery_access_v07(t.id)) THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
 WITH tree AS MATERIALIZED(SELECT * FROM private.files_recovery_tree_v07()), candidates AS MATERIALIZED(
  SELECT t.*,COALESCE(n.name,s.name) AS name,COALESCE(n.node_version,m.row_version,1) AS version,
   COALESCE(n.updated_at,m.updated_at,s.updated_at) AS updated_at,s.name AS space_name,s.project_id,
   n.parent_id,n.size_bytes,n.mime_type,s.sort_order,
   private.files_recovery_access_v07(t.id,true) AS writable,
   private.files_recovery_origin_state_v07(t.id) AS origin_state
  FROM tree t JOIN public.document_spaces s ON s.id=t.space_id
  LEFT JOIN public.document_nodes n ON n.id=t.id AND t.kind<>'SPACE'
  LEFT JOIN private.files_space_state_v04 m ON m.space_id=t.id AND t.kind='SPACE'
  WHERE t.effective_lifecycle='ARCHIVED' AND private.files_recovery_access_v07(t.id)
   AND (p_after_id IS NULL OR t.id>p_after_id)
   AND (private.files_archive_display_parent_v07(t.id) IS NOT DISTINCT FROM p_parent_id)
  ORDER BY t.id LIMIT p_limit+1
 ), page AS(SELECT * FROM candidates ORDER BY id LIMIT p_limit)
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',t.id,'kind',t.kind,'name',t.name,
  'space_id',t.space_id,'space_name',t.space_name,'project_id',t.project_id,'parent_node_id',t.parent_id,
  'parent_entity_id',t.parent_entity_id,'node_version',t.version,'updated_at',t.updated_at,
  'size_bytes',t.size_bytes,'mime_type',t.mime_type,'sort_order',CASE WHEN t.kind='SPACE' THEN t.sort_order ELSE 0 END,
  'started',false,'request_id',NULL,'lifecycle','ARCHIVED','can_browse',true,
  'can_restore',private.files_recovery_root_allowed_v07(t.id) AND t.origin_state='AVAILABLE',
  'can_reactivate',private.files_recovery_root_allowed_v07(t.id),
  'can_trash',private.files_recovery_root_allowed_v07(t.id),'origin_state',t.origin_state,'requires_destination',t.origin_state<>'AVAILABLE',
  'origin',private.files_recovery_path_label_v07((COALESCE(o.origin_path,private.files_recovery_ancestry_v07(t.id)))[1:
    cardinality(COALESCE(o.origin_path,private.files_recovery_ancestry_v07(t.id)))-1])
 ) ORDER BY t.id),'[]'),(SELECT count(*)>p_limit FROM candidates) INTO items,more
 FROM page t LEFT JOIN private.files_recovery_origins_v07 o ON o.entity_id=t.id;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',part.id,'name',COALESCE(n.name,s.name),'kind',t.kind) ORDER BY part.ordinality),'[]') INTO breadcrumb
 FROM private.files_recovery_tree_v07() current CROSS JOIN LATERAL unnest(private.files_recovery_ancestry_v07(current.id)) WITH ORDINALITY part(id,ordinality)
 JOIN private.files_recovery_tree_v07() t ON t.id=part.id
 LEFT JOIN public.document_nodes n ON n.id=t.id AND t.kind<>'SPACE'
 LEFT JOIN public.document_spaces s ON s.id=t.id AND t.kind='SPACE'
 WHERE current.id=p_parent_id AND t.effective_lifecycle='ARCHIVED' AND t.kind IN('SPACE','FOLDER')
  AND private.files_recovery_access_v07(t.id);
 RETURN jsonb_build_object('items',items,'breadcrumb',breadcrumb,'has_more',more,
  'next_id',CASE WHEN more THEN items->-1->>'id' ELSE NULL END);
END $function$;

CREATE OR REPLACE FUNCTION private.files_recovery_access_v07(p_id uuid, p_write boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT private.is_active_profile() AND EXISTS(
  SELECT 1 FROM private.files_recovery_entries_v07() e WHERE e.id=p_id AND (private.files_archive_authority_v07() OR private.rendition_owned_archived_file_v01(auth.uid(),e.id) OR NOT EXISTS(SELECT 1 FROM private.files_recovery_tree_v07() t WHERE t.id=e.id AND t.effective_lifecycle='ARCHIVED'))
   AND (EXISTS(SELECT 1 FROM private.files_recovery_anchor_v07(e.id)) OR private.files_acl_domain_eligible_v01(auth.uid(),e.space_id))
   AND EXISTS(SELECT 1 FROM private.resolve_document_access_v01(auth.uid(),e.space_id,CASE WHEN e.kind='SPACE' THEN NULL ELSE e.id END) a WHERE a.can_read AND (NOT p_write OR a.can_write))
   AND NOT EXISTS(SELECT 1 FROM private.files_purges_v01 q WHERE q.node_id=e.id AND q.completed_at IS NOT NULL)
   AND NOT EXISTS(SELECT 1 FROM private.files_document_purge_entities_v06 q WHERE q.entity_id=e.id AND q.completed_at IS NOT NULL)
   AND NOT EXISTS(SELECT 1 FROM public.document_smart_bindings b WHERE b.node_id=e.id AND b.rendition_id IS NOT NULL AND NOT private.rendition_domain_readable_v02(auth.uid(),b.rendition_id)));
$function$;

CREATE OR REPLACE FUNCTION private.files_lifecycle_root_allowed_v07(p_id uuid, p_operation text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT private.files_recovery_access_v07(p_id,true) AND EXISTS(
  SELECT 1 FROM private.files_recovery_tree_v07() t LEFT JOIN public.document_nodes n ON n.id=t.id AND t.kind<>'SPACE'
  WHERE t.id=p_id AND (p_operation<>'ARCHIVE' OR private.files_archive_authority_v07() OR private.rendition_file_archive_eligible_v01(auth.uid(),p_id))
   AND (t.kind<>'SPACE' OR private.files_archive_authority_v07()) AND (p_operation='ARCHIVE' AND t.effective_lifecycle='ACTIVE' OR p_operation='TRASH' AND t.effective_lifecycle IN('ACTIVE','ARCHIVED'))
   AND (t.kind='SPACE' AND private.files_space_manage_v04(t.id) AND EXISTS(SELECT 1 FROM public.document_spaces s WHERE s.id=t.id AND s.parent_space_id IS NOT NULL)
    OR t.kind<>'SPACE' AND n.structure_governance='FLEXIBLE')
   AND NOT EXISTS(SELECT 1 FROM private.files_project_containers_v01 c WHERE c.node_id=t.id)
   AND NOT EXISTS(SELECT 1 FROM private.legacy_project_node_conversions_v01 c WHERE c.legacy_node_id=t.id)
   AND NOT EXISTS(SELECT 1 FROM private.files_purges_v01 q WHERE q.node_id=t.id)
   AND NOT EXISTS(SELECT 1 FROM private.files_document_purge_entities_v06 q WHERE q.entity_id=t.id));
$function$;

CREATE OR REPLACE FUNCTION private.files_archive_readonly_guard_v07()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE data jsonb; old_data jsonb; target uuid; entity uuid; life text; operation text;
BEGIN
 PERFORM pg_advisory_xact_lock(6041106);
 data:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 old_data:=CASE WHEN TG_OP='INSERT' THEN '{}'::jsonb ELSE to_jsonb(OLD) END;
 IF TG_TABLE_NAME='projects' AND (TG_OP='DELETE' OR TG_OP='UPDATE' AND data->>'status' IS DISTINCT FROM old_data->>'status' AND data->>'status'<>'ACTIVO')
  AND NOT private.files_archive_authority_v07() THEN RAISE EXCEPTION 'PROJECT_LIFECYCLE_ADMIN_REQUIRED'; END IF;
 IF TG_TABLE_NAME='files_space_state_v04' AND data->>'lifecycle' IN('ARCHIVED','TRASHED')
  AND data->>'lifecycle' IS DISTINCT FROM old_data->>'lifecycle' AND NOT private.files_archive_authority_v07()
 THEN RAISE EXCEPTION 'PROJECT_LIFECYCLE_ADMIN_REQUIRED'; END IF;
 IF TG_TABLE_NAME='document_nodes' THEN
  entity:=(data->>'id')::uuid;
  IF data->>'lifecycle'='TRASHED' AND data->>'lifecycle' IS DISTINCT FROM old_data->>'lifecycle' AND NOT private.files_archive_authority_v07()
   AND EXISTS(SELECT 1 FROM private.files_recovery_tree_v07() t WHERE entity=ANY(private.files_recovery_ancestry_v07(t.id)) AND t.kind='SPACE') THEN RAISE EXCEPTION 'PROJECT_LIFECYCLE_ADMIN_REQUIRED'; END IF;
  IF data->>'lifecycle'='ARCHIVED' AND data->>'lifecycle' IS DISTINCT FROM old_data->>'lifecycle' AND NOT private.files_archive_authority_v07()
   AND NOT (TG_OP='UPDATE' AND private.rendition_file_archive_eligible_v01(auth.uid(),entity)
    AND EXISTS(SELECT 1 FROM private.files_recovery_write_guards_v07 g WHERE g.transaction_id=txid_current()
     AND g.actor_id=auth.uid() AND g.node_id=entity AND g.operation='ARCHIVE'))
   THEN RAISE EXCEPTION 'ARCHIVE_ADMIN_REQUIRED'; END IF;
 ELSIF TG_TABLE_NAME='document_versions' OR TG_TABLE_NAME='document_smart_bindings' THEN entity:=(data->>'document_node_id')::uuid;
  IF TG_TABLE_NAME='document_smart_bindings' THEN entity:=(data->>'node_id')::uuid; END IF;
 END IF;
 IF entity IS NOT NULL THEN
  SELECT effective_lifecycle INTO life FROM private.files_recovery_tree_v07() WHERE id=entity;
  IF life='ARCHIVED' AND NOT EXISTS(SELECT 1 FROM private.files_recovery_write_guards_v07 g WHERE g.transaction_id=txid_current() AND g.actor_id=auth.uid() AND g.node_id=entity)
   THEN RAISE EXCEPTION 'ARCHIVE_READ_ONLY'; END IF;
 END IF;
 FOR data IN SELECT value FROM (VALUES(data),(old_data)) AS rows(value) LOOP
  target:=COALESCE((data->>'rendition_id')::uuid,(data->>'calicata_id')::uuid);
  IF TG_TABLE_NAME IN('renditions','calicatas') THEN target:=(data->>'id')::uuid; END IF;
  IF TG_TABLE_NAME='calicata_media_versions' THEN SELECT calicata_id INTO target FROM public.calicata_media WHERE media_id=(data->>'media_id')::uuid; END IF;
  IF target IS NOT NULL AND private.files_archive_domain_lifecycle_v07(target)='ARCHIVED'
   AND NOT private.files_recovery_domain_guard_v07(target,(data->>'project_id')::uuid)
   AND NOT (TG_TABLE_NAME IN('document_nodes','document_smart_bindings') AND EXISTS(SELECT 1 FROM private.files_recovery_write_guards_v07 g WHERE g.transaction_id=txid_current() AND g.actor_id=auth.uid() AND g.node_id=entity))
  THEN RAISE EXCEPTION 'ARCHIVE_READ_ONLY'; END IF;
 END LOOP;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $function$;

CREATE OR REPLACE FUNCTION private.files_archive_domain_read_v07(p_id uuid, p_actor uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT private.files_archive_domain_lifecycle_v07(p_id)<>'ARCHIVED'
  OR (private.files_archive_authority_v07(p_actor) OR EXISTS(SELECT 1 FROM public.document_smart_bindings owned
   WHERE owned.rendition_id=p_id AND private.rendition_owned_archived_file_v01(p_actor,owned.node_id))) AND NOT EXISTS(
   SELECT 1 FROM public.document_smart_bindings b JOIN private.files_recovery_tree_v07() t ON t.id=b.node_id
   CROSS JOIN LATERAL private.resolve_document_access_v01(p_actor,b.space_id,b.node_id) a
   WHERE (b.calicata_id=p_id OR b.rendition_id=p_id) AND t.effective_lifecycle='ARCHIVED' AND NOT a.can_read);
$function$;

CREATE OR REPLACE FUNCTION public.get_my_archived_document_context_v07(p_node_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE n public.document_nodes; b public.document_smart_bindings;
BEGIN
 IF (NOT private.files_archive_authority_v07() AND NOT private.rendition_owned_archived_file_v01(auth.uid(),p_node_id)) OR NOT private.files_recovery_access_v07(p_node_id)
  OR NOT EXISTS(SELECT 1 FROM private.files_recovery_tree_v07() t WHERE t.id=p_node_id AND t.effective_lifecycle='ARCHIVED') THEN RAISE EXCEPTION 'ARCHIVE_FORBIDDEN'; END IF;
 SELECT * INTO n FROM public.document_nodes WHERE id=p_node_id;
 IF NOT FOUND OR n.node_kind NOT IN('BINARY_DOCUMENT','SMART_DOCUMENT') THEN RAISE EXCEPTION 'ARCHIVE_FORBIDDEN'; END IF;
 SELECT * INTO b FROM public.document_smart_bindings WHERE node_id=n.id;
 RETURN jsonb_build_object('id',n.id,'space_id',n.space_id,'project_id',COALESCE(b.project_id,n.project_id),'name',n.name,'parent_node_id',n.parent_id,'kind',n.node_kind,'target_type',COALESCE(b.target_type,CASE WHEN b.calicata_id IS NOT NULL THEN 'CALICATA'::public.document_smart_target_type ELSE 'RENDITION'::public.document_smart_target_type END),'target_id',COALESCE(b.target_id,b.calicata_id,b.rendition_id));
END $function$;

CREATE TABLE private.rendition_archive_requests_v01 (
  actor_id uuid NOT NULL,
  request_id uuid NOT NULL,
  payload jsonb NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (actor_id, request_id)
);
ALTER TABLE private.rendition_archive_requests_v01 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.rendition_archive_requests_v01 FROM PUBLIC, anon, authenticated;

INSERT INTO private.activity_event_catalog
 (code,module,entity_type,project_id_required,entity_id_required,entity_id_equals_project_id,
 metadata_allowed,allowed_metadata_keys,active,description,maximum_metadata_bytes)
VALUES ('RENDITION_ARCHIVED','RENDITIONS','RENDITION',false,true,false,true,
 ARRAY['result_code','node_id','request_id'],true,'Rendición enviada al Archivero de Files.',1024)
ON CONFLICT (code) DO NOTHING;

CREATE FUNCTION public.archive_my_rendition_v01(
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
  saved private.rendition_archive_requests_v01%ROWTYPE;
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
  PERFORM pg_advisory_xact_lock(hashtextextended('rendition-archive:'||actor::text||p_request_id::text,3507));
  SELECT * INTO saved FROM private.rendition_archive_requests_v01 t
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
  IF draft.status='EN_REVISION' OR EXISTS(SELECT 1 FROM private.rendition_edit_requests_v03 q
    WHERE q.rendition_id=draft.id AND q.status='PENDING')
    THEN RAISE EXCEPTION 'RENDITION_ARCHIVE_REVIEW_PENDING'; END IF;
  IF draft.archived_at IS NOT NULL OR draft.status NOT IN('BORRADOR','OBSERVADO','APROBADO','REVISADO','ARCHIVADO','EXPORTADO')
    THEN RAISE EXCEPTION 'RENDITION_NOT_ARCHIVABLE'; END IF;
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
  plan := public.preview_files_lifecycle_v07(roots,'ARCHIVE');
  PERFORM public.mutate_files_lifecycle_v07(roots,'ARCHIVE',p_request_id,plan->>'token',true);
  SELECT * INTO doc FROM public.document_nodes n WHERE n.id=doc.id;
  IF doc.lifecycle<>'ARCHIVED' THEN RAISE EXCEPTION 'RENDITION_ARCHIVE_INVALID_RESPONSE'; END IF;
  result := jsonb_build_object('rendition_id',draft.id,'row_version',draft.row_version,
    'node_id',doc.id,'node_version',doc.node_version,'lifecycle','ARCHIVED');
  INSERT INTO private.rendition_archive_requests_v01(actor_id,request_id,payload,result)
    VALUES(actor,p_request_id,payload,result);
  PERFORM private.write_activity_log('RENDITION_ARCHIVED',NULL,draft.id,
    private.rendition_client_platform_v01(),'Rendición enviada al Archivero.',
    jsonb_build_object('result_code','ARCHIVED','node_id',doc.id,'request_id',p_request_id));
  RETURN QUERY SELECT draft.id,draft.row_version,doc.id,doc.node_version,'ARCHIVED'::text,'ARCHIVED'::text;
END;
$function$;
REVOKE ALL ON FUNCTION public.archive_my_rendition_v01(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.archive_my_rendition_v01(uuid,bigint,uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';

COMMIT;
