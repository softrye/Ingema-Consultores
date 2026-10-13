-- Reject incomplete derivative metadata explicitly; preserve existing data,
-- RPC signature, reservation paths, privileges and READY versions.
CREATE OR REPLACE FUNCTION public.reserve_my_calicata_media_version_v01(p_media_id uuid, p_version_id uuid, p_original_file_name text, p_original_mime_type text, p_original_size_bytes bigint, p_original_width integer, p_original_height integer, p_original_sha256 text, p_derivative_file_name text, p_derivative_mime_type text, p_derivative_size_bytes bigint, p_derivative_width integer, p_derivative_height integer, p_derivative_sha256 text, p_annotation jsonb)
 RETURNS SETOF calicata_media_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_media public.calicata_media;
  v_existing public.calicata_media_versions;
  v_version public.calicata_media_versions;
  v_version_number integer;
  v_original_name text;
  v_derivative_name text;
  v_prefix text;
BEGIN
  SELECT * INTO v_media
  FROM public.calicata_media
  WHERE media_id = p_media_id
  FOR UPDATE;

  IF NOT FOUND OR v_media.resource_type <> 'PHOTO'
     OR auth.uid() IS NULL
     OR (v_media.created_by IS DISTINCT FROM auth.uid() AND v_media.active_version_id IS NULL)
     OR NOT private.can_write_calicata_media_v01(v_media.project_id, v_media.calicata_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'CALICATA_MEDIA_VERSION: reservation not authorized';
  END IF;

  -- CHECK constraints accept UNKNOWN; explicitly require a complete optional
  -- derivative bundle before creating or recovering a reservation.
  IF p_derivative_file_name IS NULL THEN
    IF p_derivative_mime_type IS NOT NULL OR p_derivative_size_bytes IS NOT NULL
       OR p_derivative_width IS NOT NULL OR p_derivative_height IS NOT NULL
       OR p_derivative_sha256 IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = '23514',
        MESSAGE = 'CALICATA_MEDIA_VERSION: derivative must be absent or complete';
    END IF;
  ELSIF p_derivative_mime_type IS NULL OR p_derivative_size_bytes IS NULL
        OR p_derivative_width IS NULL OR p_derivative_height IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'CALICATA_MEDIA_VERSION: derivative must be absent or complete';
  END IF;

  SELECT * INTO v_existing
  FROM public.calicata_media_versions
  WHERE version_id = p_version_id
  FOR UPDATE;

  IF FOUND THEN
    IF v_existing.media_id IS DISTINCT FROM p_media_id
       OR v_existing.created_by IS DISTINCT FROM auth.uid()
       OR v_existing.original_file_name IS DISTINCT FROM btrim(p_original_file_name)
       OR v_existing.original_mime_type IS DISTINCT FROM p_original_mime_type
       OR v_existing.original_size_bytes IS DISTINCT FROM p_original_size_bytes
       OR v_existing.original_width IS DISTINCT FROM p_original_width
       OR v_existing.original_height IS DISTINCT FROM p_original_height
       OR v_existing.original_sha256 IS DISTINCT FROM lower(p_original_sha256)
       OR v_existing.derivative_file_name IS DISTINCT FROM NULLIF(btrim(p_derivative_file_name), '')
       OR v_existing.derivative_mime_type IS DISTINCT FROM p_derivative_mime_type
       OR v_existing.derivative_size_bytes IS DISTINCT FROM p_derivative_size_bytes
       OR v_existing.derivative_width IS DISTINCT FROM p_derivative_width
       OR v_existing.derivative_height IS DISTINCT FROM p_derivative_height
       OR v_existing.derivative_sha256 IS DISTINCT FROM lower(p_derivative_sha256)
       OR v_existing.annotation IS DISTINCT FROM COALESCE(p_annotation, '{}'::jsonb) THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'CALICATA_MEDIA_VERSION: version_id belongs to another revision';
    END IF;
    IF v_existing.state = 'FAILED' THEN
      UPDATE public.calicata_media_versions
      SET state = 'UPLOADING', finalized_at = NULL
      WHERE version_id = p_version_id
      RETURNING * INTO v_existing;
    END IF;
    RETURN NEXT v_existing;
    RETURN;
  END IF;

  SELECT COALESCE(max(version_number), 0) + 1 INTO v_version_number
  FROM public.calicata_media_versions
  WHERE media_id = p_media_id;

  v_original_name := regexp_replace(btrim(p_original_file_name), '\.[^.]*$', '')
    || '.' || private.calicata_media_extension_v01(p_original_mime_type);
  IF p_derivative_file_name IS NOT NULL THEN
    v_derivative_name := regexp_replace(btrim(p_derivative_file_name), '\.[^.]*$', '')
      || '.' || private.calicata_media_extension_v01(p_derivative_mime_type);
  END IF;
  v_prefix := 'projects/' || lower(v_media.project_id::text)
    || '/calicatas/' || lower(v_media.calicata_id::text)
    || '/media/' || lower(v_media.media_id::text);

  INSERT INTO public.calicata_media_versions (
    version_id, media_id, version_number,
    original_storage_path, original_file_name, original_mime_type,
    original_size_bytes, original_width, original_height, original_sha256,
    derivative_bucket, derivative_storage_path, derivative_file_name,
    derivative_mime_type, derivative_size_bytes, derivative_width,
    derivative_height, derivative_sha256, annotation, created_by
  )
  VALUES (
    p_version_id, p_media_id, v_version_number,
    CASE WHEN v_version_number = 1
      THEN v_prefix || '/original/' || v_original_name
      ELSE v_prefix || '/versions/' || lower(p_version_id::text) || '/original/' || v_original_name
    END,
    btrim(p_original_file_name), p_original_mime_type,
    p_original_size_bytes, p_original_width, p_original_height, lower(p_original_sha256),
    CASE WHEN p_derivative_file_name IS NULL THEN NULL ELSE 'calicata-media' END,
    CASE WHEN p_derivative_file_name IS NULL THEN NULL
      ELSE v_prefix || '/versions/' || lower(p_version_id::text) || '/derivative/' || v_derivative_name
    END,
    NULLIF(btrim(p_derivative_file_name), ''), p_derivative_mime_type,
    p_derivative_size_bytes, p_derivative_width, p_derivative_height,
    lower(p_derivative_sha256), COALESCE(p_annotation, '{}'::jsonb), auth.uid()
  )
  RETURNING * INTO v_version;

  IF v_version_number = 1 THEN
    IF v_media.original_file_name IS DISTINCT FROM btrim(p_original_file_name)
       OR v_media.original_mime_type IS DISTINCT FROM p_original_mime_type
       OR v_media.original_size_bytes IS DISTINCT FROM p_original_size_bytes
       OR v_media.original_width IS DISTINCT FROM p_original_width
       OR v_media.original_height IS DISTINCT FROM p_original_height
       OR v_media.original_sha256 IS DISTINCT FROM lower(p_original_sha256) THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'CALICATA_MEDIA_VERSION: first version differs from media foundation';
    END IF;
    UPDATE public.calicata_media
    SET original_bucket = 'calicata-media',
        original_storage_path = v_version.original_storage_path,
        sync_state = 'UPLOADING',
        updated_at = now()
    WHERE media_id = p_media_id;
  END IF;

  RETURN NEXT v_version;
END;
$function$
