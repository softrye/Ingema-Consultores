-- Evita que lectura de avatares / calicata-media quede bloqueada por
-- una transacción de archivos working de Rendiciones.
-- Evidencia: Storage 2026-11-04 14:49 UTC, HTTP 400 ResourceLocked / SQLSTATE 55P03.
-- No modifica la autorización ni omite el lock para archivos working propios.
begin;
create or replace function private.rendition_working_file_allowed_v01(
    p_bucket text, p_path text, p_write boolean
) returns boolean
language plpgsql
security definer
set search_path = ''
set lock_timeout = '750ms'
as $function$
declare
    f private.rendition_working_files_v01;
    w private.rendition_working_rows_v01;
begin
    -- Filtro O(1) anterior al lock: la policy de storage.objects se evalúa
    -- también para avatares y calicata-media. Nunca bloquear esas lecturas.
    if p_bucket <> 'project-files'
       or auth.uid() is null
       or not exists (select 1 from public.profiles
                       where id = auth.uid() and status = 'ACTIVO')
    then
        return false;
    end if;

    -- Sólo los recursos de Rendiciones compiten con esta transacción.
    perform pg_advisory_xact_lock(6041106);
    select * into f from private.rendition_working_files_v01
     where storage_path = p_path;
    if not found then return false; end if;
    select * into w from private.rendition_working_rows_v01
     where id = f.working_id;
    if private.files_document_domain_frozen_v06(w.rendition_id)
       or not private.rendition_domain_readable_v02(auth.uid(), w.rendition_id)
    then return false; end if;

    if p_write then
        return w.state = 'ACTIVE'
           and f.actor = auth.uid()
           and f.status = 'RESERVED'
           and f.expires_at > clock_timestamp()
           and private.rendition_content_editable_v05(auth.uid(), w.rendition_id);
    end if;

    return f.status = 'READY'
       or (f.actor = auth.uid() and f.status = 'RESERVED'
           and private.rendition_content_editable_v05(auth.uid(), w.rendition_id));
end;
$function$;
commit;
