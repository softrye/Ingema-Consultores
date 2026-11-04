-- Rendiciones: las consultas RLS no deben serializarse mediante un
-- bloqueo GLOBAL de escritura. Evidencia 2026-11-04: 55P03 en
-- list_my_rendition_review_notices_v01 -> private.rendition_metadata_readable_v01.
-- Conserva las dos verificaciones de autorización, sin modificar datos.
-- Los RPC que MUTAN la rendición siguen aplicando sus propios bloqueos.
begin;
create or replace function private.rendition_metadata_readable_v01(
    p_actor uuid, p_rendition uuid
) returns boolean
language plpgsql
stable
security definer
set search_path = ''
set lock_timeout = '750ms'
as $function$
begin
    -- Lectura STABLE bajo snapshot MVCC; nunca adquirir
    -- pg_advisory_xact_lock(6041106) en una policy de lectura.
    return private.rendition_domain_readable_v02_before_archive_v07(p_actor, p_rendition)
       and private.files_archive_domain_read_v07(p_rendition, p_actor);
end;
$function$;
commit;
