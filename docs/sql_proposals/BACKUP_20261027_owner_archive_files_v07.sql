-- BACKUP previo: InGePlus-Dev / aalmeaqhhlhzwwzsbbxz, 2026-10-27.
-- Seis definiciones pg_get_functiondef exactas y ACL previas.
-- Reversion NO ejecutada. Aplicar como NUEVA migracion, solo con autorizacion.
BEGIN;

-- public.list_files_archive_children_v07: MD5 c7dc61f18ef1ff0826c19b6ed5b5a8e7; ACL {postgres=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.list_files_archive_children_v07(p_parent_id uuid DEFAULT NULL::uuid, p_after_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE items jsonb; breadcrumb jsonb; more boolean;
BEGIN
 IF NOT private.is_active_profile() THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
 IF NOT private.files_archive_authority_v07() THEN RAISE EXCEPTION 'ARCHIVE_FORBIDDEN'; END IF;
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
END $function$
;
REVOKE ALL ON FUNCTION public.list_files_archive_children_v07(p_parent_id uuid, p_after_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.list_files_archive_children_v07(p_parent_id uuid, p_after_id uuid, p_limit integer) TO authenticated;

-- private.files_recovery_access_v07: MD5 0658a72c5787d0f8801d18f3ca58e52f; ACL {postgres=X/postgres}
CREATE OR REPLACE FUNCTION private.files_recovery_access_v07(p_id uuid, p_write boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT private.is_active_profile() AND EXISTS(
  SELECT 1 FROM private.files_recovery_entries_v07() e WHERE e.id=p_id AND (private.files_archive_authority_v07() OR NOT EXISTS(SELECT 1 FROM private.files_recovery_tree_v07() t WHERE t.id=e.id AND t.effective_lifecycle='ARCHIVED'))
   AND (EXISTS(SELECT 1 FROM private.files_recovery_anchor_v07(e.id)) OR private.files_acl_domain_eligible_v01(auth.uid(),e.space_id))
   AND EXISTS(SELECT 1 FROM private.resolve_document_access_v01(auth.uid(),e.space_id,CASE WHEN e.kind='SPACE' THEN NULL ELSE e.id END) a WHERE a.can_read AND (NOT p_write OR a.can_write))
   AND NOT EXISTS(SELECT 1 FROM private.files_purges_v01 q WHERE q.node_id=e.id AND q.completed_at IS NOT NULL)
   AND NOT EXISTS(SELECT 1 FROM private.files_document_purge_entities_v06 q WHERE q.entity_id=e.id AND q.completed_at IS NOT NULL)
   AND NOT EXISTS(SELECT 1 FROM public.document_smart_bindings b WHERE b.node_id=e.id AND b.rendition_id IS NOT NULL AND NOT private.rendition_domain_readable_v02(auth.uid(),b.rendition_id)));
$function$
;
REVOKE ALL ON FUNCTION private.files_recovery_access_v07(p_id uuid, p_write boolean) FROM PUBLIC,anon,authenticated;

-- private.files_lifecycle_root_allowed_v07: MD5 a6bf30f30d74dbf039621ef2cb73d0b4; ACL {postgres=X/postgres}
CREATE OR REPLACE FUNCTION private.files_lifecycle_root_allowed_v07(p_id uuid, p_operation text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT private.files_recovery_access_v07(p_id,true) AND EXISTS(
  SELECT 1 FROM private.files_recovery_tree_v07() t LEFT JOIN public.document_nodes n ON n.id=t.id AND t.kind<>'SPACE'
  WHERE t.id=p_id AND (p_operation<>'ARCHIVE' OR private.files_archive_authority_v07())
   AND (t.kind<>'SPACE' OR private.files_archive_authority_v07()) AND (p_operation='ARCHIVE' AND t.effective_lifecycle='ACTIVE' OR p_operation='TRASH' AND t.effective_lifecycle IN('ACTIVE','ARCHIVED'))
   AND (t.kind='SPACE' AND private.files_space_manage_v04(t.id) AND EXISTS(SELECT 1 FROM public.document_spaces s WHERE s.id=t.id AND s.parent_space_id IS NOT NULL)
    OR t.kind<>'SPACE' AND n.structure_governance='FLEXIBLE')
   AND NOT EXISTS(SELECT 1 FROM private.files_project_containers_v01 c WHERE c.node_id=t.id)
   AND NOT EXISTS(SELECT 1 FROM private.legacy_project_node_conversions_v01 c WHERE c.legacy_node_id=t.id)
   AND NOT EXISTS(SELECT 1 FROM private.files_purges_v01 q WHERE q.node_id=t.id)
   AND NOT EXISTS(SELECT 1 FROM private.files_document_purge_entities_v06 q WHERE q.entity_id=t.id));
$function$
;
REVOKE ALL ON FUNCTION private.files_lifecycle_root_allowed_v07(p_id uuid, p_operation text) FROM PUBLIC,anon,authenticated;

-- private.files_archive_readonly_guard_v07: MD5 5f86de7a526e463c6de6a2c0578448e0; ACL {postgres=X/postgres}
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
END $function$
;
REVOKE ALL ON FUNCTION private.files_archive_readonly_guard_v07() FROM PUBLIC,anon,authenticated;

-- private.files_archive_domain_read_v07: MD5 7fd232161d8774431e1dd41a0ffc9c61; ACL {postgres=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION private.files_archive_domain_read_v07(p_id uuid, p_actor uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT private.files_archive_domain_lifecycle_v07(p_id)<>'ARCHIVED'
  OR private.files_archive_authority_v07(p_actor) AND NOT EXISTS(
   SELECT 1 FROM public.document_smart_bindings b JOIN private.files_recovery_tree_v07() t ON t.id=b.node_id
   CROSS JOIN LATERAL private.resolve_document_access_v01(p_actor,b.space_id,b.node_id) a
   WHERE (b.calicata_id=p_id OR b.rendition_id=p_id) AND t.effective_lifecycle='ARCHIVED' AND NOT a.can_read);
$function$
;
REVOKE ALL ON FUNCTION private.files_archive_domain_read_v07(p_id uuid, p_actor uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.files_archive_domain_read_v07(p_id uuid, p_actor uuid) TO authenticated;

-- public.get_my_archived_document_context_v07: MD5 4caf837eed994d791a8f77eaa4b7c8e3; ACL {postgres=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.get_my_archived_document_context_v07(p_node_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE n public.document_nodes; b public.document_smart_bindings;
BEGIN
 IF NOT private.files_archive_authority_v07() OR NOT private.files_recovery_access_v07(p_node_id)
  OR NOT EXISTS(SELECT 1 FROM private.files_recovery_tree_v07() t WHERE t.id=p_node_id AND t.effective_lifecycle='ARCHIVED') THEN RAISE EXCEPTION 'ARCHIVE_FORBIDDEN'; END IF;
 SELECT * INTO n FROM public.document_nodes WHERE id=p_node_id;
 IF NOT FOUND OR n.node_kind NOT IN('BINARY_DOCUMENT','SMART_DOCUMENT') THEN RAISE EXCEPTION 'ARCHIVE_FORBIDDEN'; END IF;
 SELECT * INTO b FROM public.document_smart_bindings WHERE node_id=n.id;
 RETURN jsonb_build_object('id',n.id,'space_id',n.space_id,'project_id',COALESCE(b.project_id,n.project_id),'name',n.name,'parent_node_id',n.parent_id,'kind',n.node_kind,'target_type',COALESCE(b.target_type,CASE WHEN b.calicata_id IS NOT NULL THEN 'CALICATA'::public.document_smart_target_type ELSE 'RENDITION'::public.document_smart_target_type END),'target_id',COALESCE(b.target_id,b.calicata_id,b.rendition_id));
END $function$
;
REVOKE ALL ON FUNCTION public.get_my_archived_document_context_v07(p_node_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_archived_document_context_v07(p_node_id uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.archive_my_rendition_v01(uuid,bigint,uuid);
DROP FUNCTION IF EXISTS private.rendition_file_archive_eligible_v01(uuid,uuid);
DROP FUNCTION IF EXISTS private.rendition_owned_archived_file_v01(uuid,uuid);
DROP FUNCTION IF EXISTS private.rendition_owned_file_v01(uuid,uuid);
-- Conservar ledger y catalogo de actividad para no borrar auditoria/receipts.
-- Additional backup BEFORE the active-list follow-up migration.
-- MD5 4fd68df089f99b7130983e6d362a6d67; ACL {postgres=X/postgres,authenticated=X/postgres}
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
REVOKE ALL ON FUNCTION public.list_renditions_effective_v06(integer,timestamptz,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.list_renditions_effective_v06(integer,timestamptz,uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
