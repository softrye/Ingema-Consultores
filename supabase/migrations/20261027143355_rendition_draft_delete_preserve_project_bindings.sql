-- APLICADA con aprobacion del usuario mediante apply_migration.
-- Solo InGePlus-Dev / aalmeaqhhlhzwwzsbbxz. Version remota: 20261027143355.
-- Hora de version: 2026-10-27 14:33:55 UTC / 09:33:55 America/Lima.
-- Propuesta original: docs/sql_proposals/20261027142558_rendition_draft_delete_preserve_project_bindings.sql.
-- Archivo movido a supabase/migrations y alineado con la version remota.
--
-- Causa: el RPC desplegado archiva rendition_projects ANTES de actualizar la
-- cabecera. guard_rendition_financial_work_v03 consulta la capacidad efectiva,
-- que requiere un proyecto primario activo, y entonces rechaza la cabecera.
-- Ademas, enforce_rendition_smart_primary_project_v01 (diferido) requiere esa
-- asociacion mientras exista document_smart_bindings, incluso con la raiz archivada.
--
-- Cambio unico de comportamiento: conservar rendition_projects como historial
-- de la raiz eliminada logicamente. No basta mover su UPDATE al final: dejaria
-- pendiente el conflicto del trigger diferido con la vinculacion documental.
-- La raiz archivada queda excluida por list_renditions_effective_v06 y por
-- rendition_domain_readable_v02_before_archive_v07 (r.archived_at IS NULL).
-- Se conservan todos los guardas, RLS, bloqueos, permisos, CAS, idempotencia,
-- borrado logico de gastos/sustentos y auditoria existentes. No se amplian ACL.
-- No se modifica ninguna fila al aplicar esta definicion; solo futuros RPC.
-- Eliminar un borrador propio en un proyecto bloqueado/archivado sigue sujeto
-- a los triggers existentes: esta propuesta NO los desactiva ni los elude.
-- DDL/firma/ACL verificados sin ejecutar el RPC; prueba funcional pendiente en Android.

BEGIN;

CREATE OR REPLACE FUNCTION public.delete_my_rendition_draft_v01(
  p_rendition_id uuid,
  p_expected_row_version bigint
)
RETURNS TABLE(rendition_id uuid, row_version bigint, archived_at timestamptz, result_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.renditions%ROWTYPE;
  v_at timestamptz := pg_catalog.transaction_timestamp();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='28000', MESSAGE='AUTH_REQUIRED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id=v_actor AND p.status='ACTIVO'::public.profile_status
  ) THEN
    RAISE EXCEPTION 'PROFILE_NOT_ACTIVE';
  END IF;
  SELECT r.* INTO v_row FROM public.renditions r
  WHERE r.id=p_rendition_id AND r.owner_user_id=v_actor FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'RENDITION_NOT_FOUND_OR_FORBIDDEN';
  END IF;
  IF v_row.status <> 'BORRADOR' OR v_row.current_version_id IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.rendition_versions v WHERE v.rendition_id=v_row.id) THEN
    RAISE EXCEPTION 'RENDITION_NOT_EDITABLE';
  END IF;
  IF v_row.archived_at IS NOT NULL THEN
    RETURN QUERY SELECT v_row.id,v_row.row_version,v_row.archived_at,'IDEMPOTENT_REPLAY'::text;
    RETURN;
  END IF;
  IF p_expected_row_version IS NULL OR v_row.row_version<>p_expected_row_version THEN
    RAISE EXCEPTION 'RENDITION_VERSION_CONFLICT';
  END IF;

  UPDATE public.rendition_expense_attachments a
  SET archived_at=v_at,archived_by=v_actor,row_version=a.row_version+1
  WHERE a.rendition_id=v_row.id AND a.archived_at IS NULL;
  UPDATE public.rendition_expenses e
  SET archived_at=v_at,archived_by=v_actor,updated_at=v_at,updated_by=v_actor,row_version=e.row_version+1
  WHERE e.rendition_id=v_row.id AND e.archived_at IS NULL;

  -- No archivar rendition_projects: conserva la asociacion primaria y el
  -- contexto documental/financiero requerido por los triggers existentes.
  UPDATE public.renditions r
  SET archived_at=v_at,archived_by=v_actor,updated_at=v_at,updated_by=v_actor,row_version=r.row_version+1
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

COMMIT;
