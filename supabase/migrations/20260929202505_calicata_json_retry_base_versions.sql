BEGIN;
CREATE OR REPLACE FUNCTION public.reserve_my_calicata_json_v01(
  p_project_id uuid, p_calicata_id uuid, p_parent_node_id uuid,
  p_size_bytes bigint, p_content_hash text, p_idempotency_key uuid
)
RETURNS SETOF public.document_binary_upload_reservation
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fn$
DECLARE
  v_actor uuid := auth.uid();
  v_cal public.calicatas%ROWTYPE;
  v_space public.document_spaces%ROWTYPE;
  v_binding private.calicata_json_bindings_v01%ROWTYPE;
  v_node public.document_nodes%ROWTYPE;
  v_attempt public.document_upload_attempts%ROWTYPE;
  v_version public.document_versions%ROWTYPE;
  v_slot public.document_binary_upload_reservation;
  v_parent uuid;
  v_name text;
  v_move jsonb;
  v_retry record;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='AUTH_REQUIRED'; END IF;
  SELECT * INTO v_cal FROM public.calicatas
  WHERE id=p_calicata_id AND project_id=p_project_id AND private.can_read_project(project_id);
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='CALICATA_JSON_FORBIDDEN'; END IF;
  SELECT * INTO v_space FROM public.document_spaces
  WHERE project_id=p_project_id AND space_type='PROJECT' AND status='ACTIVO';
  IF NOT FOUND OR NOT private.can_write_document_space_content_v01(v_space.id) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='CALICATA_JSON_FORBIDDEN';
  END IF;
  IF p_content_hash IS NULL OR p_content_hash !~ '^[0-9a-f]{64}$'
     OR p_size_bytes IS NULL OR p_size_bytes<1 OR p_size_bytes>52428800
     OR p_idempotency_key IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='CALICATA_JSON_INVALID_REQUEST';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('CALICATA_JSON:'||p_calicata_id::text,0));
  SELECT * INTO v_binding FROM private.calicata_json_bindings_v01 WHERE calicata_id=p_calicata_id;
  IF FOUND THEN
    SELECT * INTO STRICT v_node FROM public.document_nodes WHERE id=v_binding.node_id;
    IF v_node.space_id<>v_space.id OR v_node.node_kind<>'BINARY_DOCUMENT' OR v_node.lifecycle<>'ACTIVE'
       OR NOT private.files_acl_can_access_v01(v_actor,v_space.id,v_node.id,'WRITE'::private.document_access_level) THEN
      RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='CALICATA_JSON_NODE_UNAVAILABLE';
    END IF;
    SELECT * INTO STRICT v_attempt FROM public.document_upload_attempts WHERE id=v_binding.attempt_id;
    SELECT * INTO STRICT v_version FROM public.document_versions WHERE id=v_attempt.document_version_id;
    -- A completed identical snapshot is reusable by every authorized collaborator.
    -- An unfinished attempt can only be resumed by its owner.
    IF v_binding.content_hash=p_content_hash
       AND ((v_attempt.status='FINALIZADO' AND v_node.current_version_id=v_version.id)
            OR (v_attempt.actor_id=v_actor AND v_attempt.status IN ('RESERVADO','EN_CARGA','OBJETO_CARGADO','EXPIRADO','FALLIDO'))) THEN
      IF v_attempt.status<>'FINALIZADO' AND (v_attempt.expires_at<=clock_timestamp() OR v_attempt.status IN ('EXPIRADO','FALLIDO')) THEN
        SELECT * INTO STRICT v_retry FROM public.retry_document_upload_controlled(v_version.id,p_idempotency_key);
        -- The generic retry predates binary CAS and leaves these fields NULL.
        -- Preserve the original base; never replace it with a newer node version.
        UPDATE public.document_upload_attempts AS retry_attempt
        SET base_node_version=v_attempt.base_node_version,
            base_content_version=v_attempt.base_content_version,
            binary_request_context=v_attempt.binary_request_context
        WHERE retry_attempt.id=v_retry.attempt_id;
        SELECT * INTO STRICT v_attempt FROM public.document_upload_attempts WHERE id=v_retry.attempt_id;
        UPDATE private.calicata_json_bindings_v01 SET attempt_id=v_attempt.id WHERE calicata_id=p_calicata_id;
      END IF;
      -- Moving a pending upload invalidates its base version; require it to finish.
      IF p_parent_node_id IS NOT NULL AND p_parent_node_id IS DISTINCT FROM v_node.parent_id THEN
        IF v_attempt.status<>'FINALIZADO' THEN RAISE EXCEPTION 'CALICATA_JSON_UPLOAD_BUSY'; END IF;
        SELECT * INTO STRICT v_move FROM public.inge_drive_mutate_v03(
          p_idempotency_key,'MOVE',v_space.id,v_node.id,p_parent_node_id,NULL,v_node.node_version,false);
        IF NOT coalesce((v_move->>'success')::boolean,false) THEN RAISE EXCEPTION '%',coalesce(v_move->>'error_code','MOVE_FAILED'); END IF;
        SELECT * INTO STRICT v_node FROM public.document_nodes WHERE id=v_binding.node_id;
      END IF;
      RETURN NEXT (v_node.id,v_version.id,v_attempt.id,v_version.version_number,
        v_node.node_version,v_node.binary_content_version,v_version.storage_bucket,v_version.storage_path,
        v_version.file_name,v_version.mime_type,v_version.size_bytes,v_attempt.status,
        v_attempt.expires_at,'IDEMPOTENT_REPLAY')::public.document_binary_upload_reservation;
      RETURN;
    END IF;
    IF EXISTS(SELECT 1 FROM public.document_versions WHERE document_node_id=v_node.id AND upload_status='PENDIENTE') THEN
      RAISE EXCEPTION 'CALICATA_JSON_UPLOAD_BUSY';
    END IF;
    IF p_parent_node_id IS NOT NULL AND p_parent_node_id IS DISTINCT FROM v_node.parent_id THEN
      SELECT * INTO STRICT v_move FROM public.inge_drive_mutate_v03(
        p_idempotency_key,'MOVE',v_space.id,v_node.id,p_parent_node_id,NULL,v_node.node_version,false);
      IF NOT coalesce((v_move->>'success')::boolean,false) THEN RAISE EXCEPTION '%',coalesce(v_move->>'error_code','MOVE_FAILED'); END IF;
      SELECT * INTO STRICT v_node FROM public.document_nodes WHERE id=v_binding.node_id;
    END IF;
    v_parent:=v_node.parent_id;
    v_name:=v_version.file_name;
  ELSE
    v_parent:=p_parent_node_id;
    IF v_parent IS NULL THEN
      SELECT folder_id INTO STRICT v_parent FROM public.ensure_calicata_field_folder_v01(p_project_id);
    END IF;
    -- Binary strips the last extension to derive the node name, and the active
    -- sibling index compares names without extension. The JSON node therefore
    -- must never reduce to the Smart Document <code>.calicata: it is
    -- ficha-<code sin puntos>-<8 hex del id>, with no dot before ".json"
    -- (readable, deterministic, unique per calicata, stable after code edits
    -- because later saves version the bound node instead of creating one).
    v_name:=pg_catalog.lower(pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(v_cal.code,'')),
      '[^A-Za-z0-9+_-]+','-','g'));
    v_name:='ficha-'||CASE WHEN v_name='' THEN '' ELSE v_name||'-' END
      ||pg_catalog.left(p_calicata_id::text,8)||'.json';
  END IF;
  SELECT * INTO STRICT v_slot FROM private.reserve_binary_upload_core_v01(
    v_space.id, CASE WHEN v_node.id IS NULL THEN v_parent ELSE NULL END,
    v_node.id,v_node.node_version,v_node.binary_content_version,v_name,'application/json',p_size_bytes,p_idempotency_key);
  INSERT INTO private.calicata_json_bindings_v01(calicata_id,node_id,content_hash,attempt_id)
  VALUES(p_calicata_id,v_slot.document_node_id,p_content_hash,v_slot.attempt_id)
  ON CONFLICT(calicata_id) DO UPDATE SET content_hash=excluded.content_hash,attempt_id=excluded.attempt_id;
  RETURN NEXT v_slot;
END;
$fn$;

NOTIFY pgrst,'reload schema';
COMMIT;
