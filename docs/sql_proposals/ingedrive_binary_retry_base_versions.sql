-- PROPOSAL ONLY. NOT EXECUTED. Requires coordinated backend review.
-- Preserve the original optimistic concurrency baseline on retry attempts.
-- No new table, bucket, policy, credentials or object identity.
-- Source: InGePlus-Dev function definition inspected on 2026-09-25.
-- Apply BEFORE enabling expired canonical binary retries in production.
-- Existing broken attempts with NULL baselines require separate audited repair;
-- do not adopt the current node versions, which would hide real conflicts.
BEGIN;
CREATE OR REPLACE FUNCTION public.retry_document_upload_controlled(p_document_version_id uuid, p_idempotency_key uuid)
 RETURNS TABLE(document_node_id uuid, document_version_id uuid, attempt_id uuid, attempt_number integer, version_number integer, bucket text, storage_path text, file_name text, mime_type text, size_bytes bigint, attempt_status document_upload_attempt_status, upload_expires_at timestamp with time zone, next_action text, result_code text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor_id uuid := auth.uid();
  v_existing_attempt public.document_upload_attempts%ROWTYPE;
  v_existing_version public.document_versions%ROWTYPE;
  v_existing_node public.document_nodes%ROWTYPE;
  v_previous_attempt public.document_upload_attempts%ROWTYPE;
  v_version public.document_versions%ROWTYPE;
  v_node public.document_nodes%ROWTYPE;
  v_new_attempt public.document_upload_attempts%ROWTYPE;
  v_object_state text;
  v_attempt_status public.document_upload_attempt_status;
  v_failure_code public.document_upload_failure_code;
  v_failure_reason text;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_expires_at timestamptz := v_now + interval '15 minutes';
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '28000',
      MESSAGE = 'P0_C1_RETRY: authentication required';
  END IF;

  IF p_document_version_id IS NULL OR p_idempotency_key IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '22004',
      MESSAGE = 'P0_C1_RETRY: version and idempotency key are required';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_actor_id::text || ':' || p_idempotency_key::text,
      0
    )
  );

  SELECT attempt_row.*
  INTO v_existing_attempt
  FROM public.document_upload_attempts AS attempt_row
  WHERE attempt_row.actor_id = v_actor_id
    AND attempt_row.idempotency_key = p_idempotency_key
  FOR UPDATE;

  IF FOUND THEN
    SELECT version_row.*
    INTO STRICT v_existing_version
    FROM public.document_versions AS version_row
    WHERE version_row.id = v_existing_attempt.document_version_id
    FOR UPDATE;

    SELECT node_row.*
    INTO STRICT v_existing_node
    FROM public.document_nodes AS node_row
    WHERE node_row.id = v_existing_version.document_node_id
    FOR UPDATE;

    IF v_existing_attempt.document_version_id IS DISTINCT FROM
      p_document_version_id THEN
      PERFORM private.write_document_upload_activity(
        'DOCUMENT_IDEMPOTENCY_CONFLICT',
        v_existing_node.project_id,
        v_existing_attempt.id,
        'WEB'
      );

      RETURN QUERY
      SELECT
        v_existing_node.id,
        v_existing_version.id,
        v_existing_attempt.id,
        v_existing_attempt.attempt_number,
        v_existing_version.version_number,
        v_existing_version.storage_bucket,
        v_existing_version.storage_path,
        v_existing_version.file_name,
        v_existing_version.mime_type,
        v_existing_version.size_bytes,
        v_existing_attempt.status,
        v_existing_attempt.expires_at,
        'NONE'::text,
        'IDEMPOTENCY_CONFLICT'::text;
      RETURN;
    END IF;

    IF v_existing_attempt.status IN (
         'RESERVADO'::public.document_upload_attempt_status,
         'EN_CARGA'::public.document_upload_attempt_status,
         'OBJETO_CARGADO'::public.document_upload_attempt_status,
         'INDETERMINADO'::public.document_upload_attempt_status
       )
       AND v_existing_attempt.expires_at <= v_now THEN
      PERFORM private.expire_document_upload_attempt_locked(
        v_existing_attempt.id,
        'WEB',
        false
      );

      SELECT attempt_row.*
      INTO STRICT v_existing_attempt
      FROM public.document_upload_attempts AS attempt_row
      WHERE attempt_row.id = v_existing_attempt.id;
    END IF;

    RETURN QUERY
    SELECT
      v_existing_node.id,
      v_existing_version.id,
      v_existing_attempt.id,
      v_existing_attempt.attempt_number,
      v_existing_version.version_number,
      v_existing_version.storage_bucket,
      v_existing_version.storage_path,
      v_existing_version.file_name,
      v_existing_version.mime_type,
      v_existing_version.size_bytes,
      v_existing_attempt.status,
      v_existing_attempt.expires_at,
      private.document_upload_attempt_next_action(v_existing_attempt.status),
      CASE
        WHEN v_existing_attempt.status =
          'EXPIRADO'::public.document_upload_attempt_status
          THEN 'EXPIRED'
        ELSE 'IDEMPOTENT_REPLAY'
      END;
    RETURN;
  END IF;

  SELECT attempt_row.*
  INTO v_previous_attempt
  FROM public.document_upload_attempts AS attempt_row
  WHERE attempt_row.document_version_id = p_document_version_id
  ORDER BY attempt_row.attempt_number DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0002',
      MESSAGE = 'P0_C1_RETRY: version has no upload attempt';
  END IF;

  SELECT version_row.*
  INTO STRICT v_version
  FROM public.document_versions AS version_row
  WHERE version_row.id = p_document_version_id
  FOR UPDATE;

  SELECT node_row.*
  INTO STRICT v_node
  FROM public.document_nodes AS node_row
  WHERE node_row.id = v_version.document_node_id
  FOR UPDATE;

  IF NOT private.document_upload_actor_can_write(v_node.project_id) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'P0_C1_RETRY: project upload is not authorized';
  END IF;

  IF v_previous_attempt.status IN (
       'RESERVADO'::public.document_upload_attempt_status,
       'EN_CARGA'::public.document_upload_attempt_status,
       'OBJETO_CARGADO'::public.document_upload_attempt_status,
       'INDETERMINADO'::public.document_upload_attempt_status
     )
     AND v_previous_attempt.expires_at <= v_now THEN
    PERFORM private.expire_document_upload_attempt_locked(
      v_previous_attempt.id,
      'WEB',
      false
    );

    SELECT attempt_row.*
    INTO STRICT v_previous_attempt
    FROM public.document_upload_attempts AS attempt_row
    WHERE attempt_row.id = v_previous_attempt.id;

    SELECT version_row.*
    INTO STRICT v_version
    FROM public.document_versions AS version_row
    WHERE version_row.id = p_document_version_id
    FOR UPDATE;
  END IF;

  IF v_previous_attempt.status IN (
    'RESERVADO'::public.document_upload_attempt_status,
    'EN_CARGA'::public.document_upload_attempt_status,
    'OBJETO_CARGADO'::public.document_upload_attempt_status,
    'INDETERMINADO'::public.document_upload_attempt_status
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'P0_C1_RETRY: another active attempt already exists';
  END IF;

  IF v_previous_attempt.status =
    'FINALIZADO'::public.document_upload_attempt_status
     OR v_version.upload_status =
      'SUBIDO'::public.document_upload_status THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'P0_C1_RETRY: completed versions cannot be retried';
  END IF;

  IF v_previous_attempt.status NOT IN (
       'FALLIDO'::public.document_upload_attempt_status,
       'EXPIRADO'::public.document_upload_attempt_status
     )
     OR v_version.upload_status NOT IN (
       'FALLIDO'::public.document_upload_status,
       'EXPIRADO'::public.document_upload_status
     ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'P0_C1_RETRY: only failed or expired uploads can retry';
  END IF;

  v_object_state :=
    private.document_upload_object_state(v_version.id);

  IF v_object_state = 'EXACT' THEN
    v_attempt_status :=
      'OBJETO_CARGADO'::public.document_upload_attempt_status;
    v_failure_code := NULL;
    v_failure_reason := NULL;
  ELSIF v_object_state = 'INCOMPATIBLE' THEN
    v_attempt_status :=
      'INDETERMINADO'::public.document_upload_attempt_status;
    v_failure_code :=
      'OBJECT_INCOMPATIBLE'::public.document_upload_failure_code;
    v_failure_reason :=
      private.document_upload_failure_reason(v_failure_code);
  ELSE
    v_attempt_status :=
      'RESERVADO'::public.document_upload_attempt_status;
    v_failure_code := NULL;
    v_failure_reason := NULL;
  END IF;

  PERFORM pg_catalog.set_config(
    'ingeplus.document_upload_retry',
    'on',
    true
  );

  UPDATE public.document_versions AS version_row
  SET upload_status = 'PENDIENTE'::public.document_upload_status,
      uploaded_at = NULL,
      failure_reason = NULL
  WHERE version_row.id = v_version.id
  RETURNING version_row.* INTO v_version;

  PERFORM pg_catalog.set_config(
    'ingeplus.document_upload_retry',
    'off',
    true
  );

  INSERT INTO public.document_upload_attempts (
    document_version_id,
    actor_id,
    attempt_number,
    idempotency_key,
    status,
    created_at,
    started_at,
    last_heartbeat_at,
    expires_at,
    retry_of_attempt_id,
    failure_code,
    failure_reason,
    base_node_version,
    base_content_version,
    binary_request_context
  )
  VALUES (
    v_version.id,
    v_actor_id,
    v_previous_attempt.attempt_number + 1,
    p_idempotency_key,
    v_attempt_status,
    v_now,
    CASE
      WHEN v_attempt_status IN (
        'OBJETO_CARGADO'::public.document_upload_attempt_status,
        'INDETERMINADO'::public.document_upload_attempt_status
      ) THEN v_now
      ELSE NULL
    END,
    CASE
      WHEN v_attempt_status IN (
        'OBJETO_CARGADO'::public.document_upload_attempt_status,
        'INDETERMINADO'::public.document_upload_attempt_status
      ) THEN v_now
      ELSE NULL
    END,
    v_expires_at,
    v_previous_attempt.id,
    v_failure_code,
    v_failure_reason,
    v_previous_attempt.base_node_version,
    v_previous_attempt.base_content_version,
    v_previous_attempt.binary_request_context
  )
  RETURNING * INTO v_new_attempt;

  PERFORM private.write_document_upload_activity(
    'DOCUMENT_UPLOAD_RETRIED',
    v_node.project_id,
    v_new_attempt.id,
    'WEB'
  );

  RETURN QUERY
  SELECT
    v_node.id,
    v_version.id,
    v_new_attempt.id,
    v_new_attempt.attempt_number,
    v_version.version_number,
    v_version.storage_bucket,
    v_version.storage_path,
    v_version.file_name,
    v_version.mime_type,
    v_version.size_bytes,
    v_new_attempt.status,
    v_new_attempt.expires_at,
    private.document_upload_attempt_next_action(v_new_attempt.status),
    'RETRIED'::text;
END;
$function$

COMMIT;

