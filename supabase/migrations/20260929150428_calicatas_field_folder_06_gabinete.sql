-- CALICATAS-FIELD-06-GABINETE (sincrónico, drift-safe)
-- La carpeta canónica de Calicatas (structural_context = FIELD) de cada espacio
-- PROJECT es 04_PROYECTOS/<proyecto>/06_GABINETE (raíz del espacio), sin excepciones.
-- ensure_calicata_smart_document_v01 coloca <código>.calicata en la carpeta FIELD;
-- la app llama antes, en la MISMA operación de Guardar, a
-- public.ensure_calicata_field_folder_v01(project_id), que crea/enlaza 06_GABINETE.
--
-- Seguridad (sin relajar ACL/RLS ni private.assign_…; sin pg_cron ni polling):
--   * El cliente no recibe escritura sobre structural_context.
--   * La RPC es SECURITY DEFINER (postgres), search_path '', deriva auth.uid(),
--     exige perfil ACTIVO, acceso al proyecto y escritura en su espacio.
--   * El enlace FIELD en tiempo de ejecución usa el patrón de guarda privada por
--     transacción (txid + actor + nodo) que solo esta RPC escribe.
--
-- Diagnostico 2026-09-29: la RPC no estaba desplegada y el trigger vivo ya no
-- contiene el antiguo binding B2A. Se adapta SOLO la condicion de inmutabilidad
-- del trigger actual; su guarda ADMINISTRATION y el resto del cuerpo se conservan.
-- No hay normalizacion masiva, renombrados ni movimientos de datos existentes.
-- Una carpeta FIELD no canonica produce un error explicito.

BEGIN;

-- 0) Precondiciones estrictas: si algo no coincide, abortar antes de cambiar nada.
DO $precheck$
DECLARE
  v_fn regprocedure := pg_catalog.to_regprocedure('private.enforce_document_node_structural_context_v01()');
  v_proc record;
BEGIN
  IF v_fn IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'CALICATAS_FIELD_PRECHECK: private.enforce_document_node_structural_context_v01() is missing';
  END IF;

  SELECT proc.prosecdef, proc.prorettype::regtype::text AS rettype,
         lang.lanname, owner_role.rolname
  INTO v_proc
  FROM pg_catalog.pg_proc AS proc
  JOIN pg_catalog.pg_language AS lang ON lang.oid = proc.prolang
  JOIN pg_catalog.pg_roles AS owner_role ON owner_role.oid = proc.proowner
  WHERE proc.oid = v_fn;
  IF v_proc.rettype <> 'trigger' OR v_proc.lanname <> 'plpgsql'
     OR NOT v_proc.prosecdef OR v_proc.rolname <> 'postgres' THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'CALICATAS_FIELD_PRECHECK: enforce_document_node_structural_context_v01 signature/owner/security changed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trg
    WHERE trg.tgrelid = 'public.document_nodes'::regclass
      AND trg.tgfoid = v_fn
      AND NOT trg.tgisinternal
      AND trg.tgenabled <> 'D'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'CALICATAS_FIELD_PRECHECK: structural context trigger on public.document_nodes is missing or disabled';
  END IF;

  IF pg_catalog.to_regprocedure(
       'private.assign_document_node_structural_context_v01(uuid,public.document_structural_context)') IS NULL
     OR pg_catalog.to_regprocedure('private.can_read_project(uuid)') IS NULL
     OR pg_catalog.to_regprocedure('private.can_write_document_space_content_v01(uuid)') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc AS proc
       JOIN pg_catalog.pg_namespace AS ns ON ns.oid = proc.pronamespace
       WHERE ns.nspname = 'private' AND proc.proname = 'apply_document_node_mutation_v01'
         AND proc.pronargs = 6)
     OR pg_catalog.to_regclass('public.document_nodes_space_structural_context_uidx') IS NULL
     OR pg_catalog.to_regclass('private.document_node_mutation_guards_v01') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_enum AS enum_value
       WHERE enum_value.enumtypid = 'public.document_structural_context'::regtype
         AND enum_value.enumlabel = 'FIELD')
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_enum AS enum_value
       WHERE enum_value.enumtypid = 'public.profile_status'::regtype
         AND enum_value.enumlabel = 'ACTIVO') THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'CALICATAS_FIELD_PRECHECK: FIELD/drive/profile contracts are missing or changed';
  END IF;

  IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_attribute AS att
      WHERE att.attrelid = 'public.document_nodes'::regclass AND NOT att.attisdropped
        AND att.attname IN ('id','space_id','parent_id','name','node_type','lifecycle','structural_context')) <> 7
     OR (SELECT pg_catalog.count(*) FROM pg_catalog.pg_attribute AS att
         WHERE att.attrelid = 'public.document_spaces'::regclass AND NOT att.attisdropped
           AND att.attname IN ('id','project_id','space_type','status')) <> 4
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS att
         WHERE att.attrelid = 'public.profiles'::regclass AND NOT att.attisdropped AND att.attname = 'status') THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'CALICATAS_FIELD_PRECHECK: document_nodes/document_spaces/profiles columns changed';
  END IF;

  -- Infraestructura de guarda: si ya existe, debe tener exactamente la forma esperada.
  IF pg_catalog.to_regclass('private.document_field_binding_guards_v01') IS NOT NULL
     AND (SELECT pg_catalog.count(*) FROM pg_catalog.pg_attribute AS att
          WHERE att.attrelid = pg_catalog.to_regclass('private.document_field_binding_guards_v01')
            AND att.attnum > 0 AND NOT att.attisdropped
            AND ((att.attname = 'transaction_id' AND att.atttypid = 'bigint'::regtype)
              OR (att.attname = 'actor_id' AND att.atttypid = 'uuid'::regtype)
              OR (att.attname = 'node_id' AND att.atttypid = 'uuid'::regtype))) <> 3 THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'CALICATAS_FIELD_PRECHECK: private.document_field_binding_guards_v01 has an unexpected shape';
  END IF;
END;
$precheck$;

-- 1) Guarda privada de enlace FIELD (sin permisos para ningún rol cliente).
CREATE TABLE IF NOT EXISTS private.document_field_binding_guards_v01 (
  transaction_id bigint NOT NULL,
  actor_id uuid NOT NULL,
  node_id uuid NOT NULL,
  PRIMARY KEY (transaction_id, node_id)
);
REVOKE ALL ON TABLE private.document_field_binding_guards_v01
  FROM PUBLIC, anon, authenticated, service_role;

-- 2) Excepcion minima al trigger VIVO: solo el enlace puro NULL -> FIELD de
-- 06_GABINETE autorizado por la RPC en la misma transaccion, actor y nodo.
DO $patch$
DECLARE
  v_fn regprocedure := 'private.enforce_document_node_structural_context_v01()'::regprocedure;
  v_def text := pg_catalog.pg_get_functiondef(v_fn);
  v_anchor constant text :=
    'ELSIF NEW.structural_context IS DISTINCT FROM OLD.structural_context THEN';
  v_replacement constant text := $replacement$ELSIF NEW.structural_context IS DISTINCT FROM OLD.structural_context
    -- CALICATAS-FIELD-06-GABINETE: enlace puro autorizado por la RPC.
    AND NOT (
      OLD.structural_context IS NULL
      AND NEW.structural_context = 'FIELD'::public.document_structural_context
      AND NEW.name = '06_GABINETE'
      AND NEW.parent_id IS NULL
      AND NEW.node_type = 'FOLDER'::public.document_node_type
      AND NEW.node_kind = 'FOLDER'::public.document_node_kind
      AND NEW.lifecycle = 'ACTIVE'::public.document_node_lifecycle
      AND (pg_catalog.to_jsonb(NEW) - 'structural_context')
        = (pg_catalog.to_jsonb(OLD) - 'structural_context')
      AND EXISTS (
        SELECT 1 FROM private.document_field_binding_guards_v01 AS field_guard
        WHERE field_guard.transaction_id = pg_catalog.txid_current()
          AND field_guard.actor_id = auth.uid()
          AND field_guard.node_id = NEW.id
      )
    ) THEN$replacement$;
BEGIN
  IF pg_catalog.strpos(v_def, 'CALICATAS-FIELD-06-GABINETE') > 0 THEN
    RETURN;
  END IF;
  IF (pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_anchor, '')))
       / pg_catalog.length(v_anchor) <> 1
     OR pg_catalog.strpos(v_def, 'PROJECT_FOLDER_CONTEXT_IMMUTABLE') = 0
     OR pg_catalog.strpos(v_def, 'PROJECT_FOLDER_CONTEXT_REQUIRES_FOLDER') = 0
     OR pg_catalog.strpos(v_def, 'project_structure_creation_guard_v01') = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'CALICATAS_FIELD_PATCH: live structural context trigger drifted; nothing changed';
  END IF;
  EXECUTE pg_catalog.replace(v_def, v_anchor, v_replacement);
END;
$patch$;

-- 3) RPC controlada y sincrónica: crea/enlaza 06_GABINETE como FIELD del proyecto.
--    Idempotente: con 06_GABINETE ya FIELD devuelve IDEMPOTENT_REPLAY sin cambios.
--    El actor sale de auth.uid(); no hay parámetro de actor.
CREATE OR REPLACE FUNCTION public.ensure_calicata_field_folder_v01(
  p_project_id uuid
)
RETURNS TABLE(space_id uuid, folder_id uuid, result_code text)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor_id uuid := auth.uid();
  v_space public.document_spaces%ROWTYPE;
  v_field public.document_nodes%ROWTYPE;
  v_folder public.document_nodes%ROWTYPE;
  v_mutation jsonb;
  v_code text := 'BOUND';
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '28000', MESSAGE = 'AUTH_REQUIRED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles AS profile
    WHERE profile.id = v_actor_id
      AND profile.status = 'ACTIVO'::public.profile_status
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'PROFILE_NOT_ACTIVE';
  END IF;

  IF p_project_id IS NULL OR NOT private.can_read_project(p_project_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FIELD_FOLDER_NOT_FOUND_OR_FORBIDDEN';
  END IF;

  SELECT space.* INTO v_space
  FROM public.document_spaces AS space
  WHERE space.space_type = 'PROJECT'::public.document_space_type
    AND space.project_id = p_project_id
    AND space.status = 'ACTIVO'::public.document_space_status;

  IF NOT FOUND OR NOT private.can_write_document_space_content_v01(v_space.id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FIELD_FOLDER_NOT_FOUND_OR_FORBIDDEN';
  END IF;

  -- Mismo lock que las mutaciones estructurales del espacio.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_space.id::text, 1301)
  );

  SELECT node.* INTO v_field
  FROM public.document_nodes AS node
  WHERE node.space_id = v_space.id
    AND node.structural_context = 'FIELD'::public.document_structural_context;

  IF FOUND THEN
    IF v_field.name = '06_GABINETE'
       AND v_field.parent_id IS NULL
       AND v_field.node_kind = 'FOLDER'::public.document_node_kind
       AND v_field.node_type = 'FOLDER'::public.document_node_type
       AND v_field.lifecycle = 'ACTIVE'::public.document_node_lifecycle THEN
      RETURN QUERY SELECT v_space.id, v_field.id, 'IDEMPOTENT_REPLAY'::text;
      RETURN;
    END IF;
    -- No renombrar ni mover carpetas existentes durante una sincronizacion.
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FIELD_FOLDER_NOT_CANONICAL';
  END IF;

  SELECT node.* INTO v_folder
  FROM public.document_nodes AS node
  WHERE node.space_id = v_space.id
    AND node.parent_id IS NULL
    AND node.node_type = 'FOLDER'::public.document_node_type
    AND node.lifecycle = 'ACTIVE'::public.document_node_lifecycle
    AND node.name = '06_GABINETE'
  ORDER BY node.id
  LIMIT 1;

  IF NOT FOUND THEN
    -- Creación por la ruta privada existente (permisos, guarda de mutación, trazas).
    SELECT pg_catalog.to_jsonb(private.apply_document_node_mutation_v01(
      'CREATE_FOLDER', v_space.id, pg_catalog.gen_random_uuid(), NULL, '06_GABINETE', NULL
    )) INTO v_mutation;
    IF NOT COALESCE((v_mutation ->> 'success')::boolean, false) THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = COALESCE(v_mutation ->> 'error_code', 'FIELD_FOLDER_CREATE_FAILED');
    END IF;
    SELECT node.* INTO STRICT v_folder
    FROM public.document_nodes AS node
    WHERE node.space_id = v_space.id
      AND node.parent_id IS NULL
      AND node.node_type = 'FOLDER'::public.document_node_type
      AND node.lifecycle = 'ACTIVE'::public.document_node_lifecycle
      AND node.name = '06_GABINETE'
    ORDER BY node.id
    LIMIT 1;
    v_code := 'CREATED';
  END IF;

  -- Enlace FIELD puro y guardado (única ruta en tiempo de ejecución).
  INSERT INTO private.document_field_binding_guards_v01 (transaction_id, actor_id, node_id)
  VALUES (pg_catalog.txid_current(), v_actor_id, v_folder.id)
  ON CONFLICT DO NOTHING;

  UPDATE public.document_nodes
  SET structural_context = 'FIELD'::public.document_structural_context
  WHERE id = v_folder.id
    AND structural_context IS NULL;

  DELETE FROM private.document_field_binding_guards_v01 AS field_guard
  WHERE field_guard.transaction_id = pg_catalog.txid_current()
    AND field_guard.node_id = v_folder.id;

  RETURN QUERY SELECT v_space.id, v_folder.id, v_code;
END;
$function$;

ALTER FUNCTION public.ensure_calicata_field_folder_v01(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.ensure_calicata_field_folder_v01(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.ensure_calicata_field_folder_v01(uuid) TO authenticated;

COMMENT ON FUNCTION public.ensure_calicata_field_folder_v01(uuid) IS
  'Synchronously ensures 04_PROYECTOS/<project>/06_GABINETE as the FIELD folder of the caller''s authorized PROJECT space (creates it if missing, binds FIELD through a private per-transaction guard). Idempotent; grants no structural_context write to clients.';

-- Publicar la RPC tras confirmar la transaccion.
NOTIFY pgrst, 'reload schema';

COMMIT;
