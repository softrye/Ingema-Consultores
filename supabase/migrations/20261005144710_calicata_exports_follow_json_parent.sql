-- Server-owned export destination, using the actual bound editable JSON parent.
CREATE OR REPLACE FUNCTION public.ensure_my_calicata_exports_folder_v01(
  p_project_id uuid, p_calicata_id uuid DEFAULT NULL
)
RETURNS TABLE(space_id uuid, folder_id uuid, json_parent_id uuid, result_code text, display_path text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_space public.document_spaces%ROWTYPE;
  v_json public.document_nodes%ROWTYPE;
  v_folder public.document_nodes%ROWTYPE;
  v_parent uuid;
  v_binding_node uuid;
  v_mutation public.document_node_mutation_result;
  v_code text := 'IDEMPOTENT_REPLAY';
  v_path text;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='AUTH_REQUIRED';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=v_actor AND p.status='ACTIVO') THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='PROFILE_NOT_ACTIVE';
  END IF;
  IF p_project_id IS NULL OR NOT private.can_read_project(p_project_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='CALICATA_EXPORTS_FORBIDDEN';
  END IF;
  SELECT s.* INTO v_space FROM public.document_spaces s
  WHERE s.project_id=p_project_id AND s.space_type='PROJECT' AND s.status='ACTIVO';
  IF NOT FOUND OR NOT private.can_write_document_space_content_v01(v_space.id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='CALICATA_EXPORTS_FORBIDDEN';
  END IF;
  IF p_calicata_id IS NOT NULL THEN
    IF NOT EXISTS(SELECT 1 FROM public.calicatas c WHERE c.id=p_calicata_id AND c.project_id=p_project_id) THEN
      RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='CALICATA_EXPORTS_FORBIDDEN';
    END IF;
    -- Same ordering as JSON publication, then the structural-space lock.
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('CALICATA_JSON:'||p_calicata_id::text,0));
    SELECT b.node_id INTO v_binding_node FROM private.calicata_json_bindings_v01 b WHERE b.calicata_id=p_calicata_id;
    IF FOUND THEN
      SELECT n.* INTO v_json FROM public.document_nodes n WHERE n.id=v_binding_node;
      IF NOT FOUND OR v_json.space_id<>v_space.id OR v_json.node_kind<>'BINARY_DOCUMENT'
         OR v_json.lifecycle<>'ACTIVE'
         OR NOT private.files_acl_can_access_v01(v_actor,v_space.id,v_json.id,'WRITE'::private.document_access_level) THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='CALICATA_EXPORTS_JSON_UNAVAILABLE';
      END IF;
      v_parent := v_json.parent_id;
    ELSE
      -- A ficha not yet published as JSON uses its normal canonical folder.
      SELECT f.folder_id INTO STRICT v_parent FROM public.ensure_calicata_field_folder_v01(p_project_id) f;
    END IF;
  ELSE
    -- First local export may precede the server's assignment of a calicata id.
    SELECT f.folder_id INTO STRICT v_parent FROM public.ensure_calicata_field_folder_v01(p_project_id) f;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_space.id::text,1301));
  IF v_parent IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.document_nodes p WHERE p.id=v_parent AND p.space_id=v_space.id
    AND p.node_kind='FOLDER' AND p.lifecycle='ACTIVE'
    AND private.files_acl_can_access_v01(v_actor,v_space.id,p.id,'WRITE'::private.document_access_level)
  ) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='CALICATA_EXPORTS_PARENT_UNAVAILABLE';
  END IF;
  SELECT n.* INTO v_folder FROM public.document_nodes n
  WHERE n.space_id=v_space.id AND n.parent_id IS NOT DISTINCT FROM v_parent
    AND pg_catalog.lower(n.name)='exports' AND n.lifecycle='ACTIVE';
  IF FOUND THEN
    IF v_folder.node_kind<>'FOLDER' OR v_folder.node_type<>'FOLDER'
       OR NOT private.files_acl_can_access_v01(v_actor,v_space.id,v_folder.id,'WRITE'::private.document_access_level) THEN
      RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='CALICATA_EXPORTS_NAME_CONFLICT_OR_FORBIDDEN';
    END IF;
  ELSE
    SELECT * INTO STRICT v_mutation FROM public.create_document_folder_v01(v_space.id,v_parent,'exports');
    IF NOT v_mutation.success THEN
      RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE=coalesce(v_mutation.error_code,'CALICATA_EXPORTS_CREATE_FAILED');
    END IF;
    SELECT n.* INTO STRICT v_folder FROM public.document_nodes n WHERE n.id=v_mutation.node_id;
    v_code := 'CREATED';
  END IF;
  WITH RECURSIVE ancestors AS (
    SELECT v_folder.id AS id,v_folder.parent_id AS parent_id,v_folder.name AS name,0 AS depth,ARRAY[v_folder.id] AS visited
    UNION ALL
    SELECT n.id,n.parent_id,n.name,a.depth+1,a.visited||n.id
    FROM public.document_nodes n JOIN ancestors a ON n.id=a.parent_id
    WHERE n.space_id=v_space.id AND a.depth<64 AND NOT n.id=ANY(a.visited)
  )
  SELECT pg_catalog.string_agg(a.name,'/' ORDER BY a.depth DESC) INTO v_path FROM ancestors a;
  RETURN QUERY SELECT v_space.id,v_folder.id,v_parent,v_code,v_path;
END;
$function$;
REVOKE ALL ON FUNCTION public.ensure_my_calicata_exports_folder_v01(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ensure_my_calicata_exports_folder_v01(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
