-- Respaldo antes de corregir can_browse; InGePlus-Dev solamente.
-- Captura: 2026-10-27 15:47:29.002515+00. Estado intermedio tras 20261027152819.
-- Para revertir TODO el archivado usar BACKUP_20261027_owner_archive_files_v07.sql.
BEGIN;
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
END $function$
;
NOTIFY pgrst, 'reload schema';
COMMIT;
