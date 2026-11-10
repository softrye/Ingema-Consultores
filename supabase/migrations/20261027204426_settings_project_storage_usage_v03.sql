-- InGePlus-Dev only: project-wide Storage aggregates for Settings.
-- Compatible RPC signature and SETOF response; p_space_id is intentionally
-- accepted but does not restrict project totals. No filenames/IDs escape.
create or replace function public.inge_drive_storage_usage_v03(p_space_id uuid default null)
returns setof jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  capacity bigint;
  used_bytes bigint;
  unknown_sizes bigint;
  categories jsonb;
  scoped_bytes bigint;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  select c.capacity_bytes into capacity
  from private.inge_drive_project_storage_config c where c.singleton;
  if capacity is null or capacity <= 0 then
    raise exception 'STORAGE_QUOTA_NOT_CONFIGURED';
  end if;

  -- Domain categories take precedence over image MIME. EXISTS avoids double
  -- counting when several versions/bindings reference the same physical object.
  -- Keep archived, trashed, discarded and orphaned objects: they still use bytes.
  with objects as materialized (
    select case
      when o.metadata->>'size' ~ '^[0-9]{1,18}$'
        then (o.metadata->>'size')::bigint end as bytes,
      case
        when o.bucket_id = 'calicata-media'
          or exists(select 1 from public.calicata_media m
            where m.original_bucket=o.bucket_id and m.original_storage_path=o.name)
          or exists(select 1 from public.calicata_media_versions v
            where (v.original_bucket=o.bucket_id and v.original_storage_path=o.name)
               or (v.derivative_bucket=o.bucket_id and v.derivative_storage_path=o.name))
          then 'calicatas'
        when (o.bucket_id='project-files' and o.name like 'renditions/%')
          or exists(select 1 from public.rendition_expense_attachments a
            where a.storage_bucket=o.bucket_id and a.storage_path=o.name)
          then 'renditions'
        when lower(coalesce(o.metadata->>'mimetype','')) like 'image/%'
          then 'photos'
        when o.bucket_id='project-files'
          or exists(select 1 from public.document_versions v
            where v.storage_bucket=o.bucket_id and v.storage_path=o.name)
          or exists(select 1 from public.document_nodes n
            where n.storage_bucket=o.bucket_id and n.storage_path=o.name)
          then 'documents'
        else 'other'
      end as category
    from storage.objects o
  ), totals as (
    select category, sum(bytes)::bigint as bytes from objects group by category
  ), labels(key,label,position) as (
    values ('documents','Documentos',1), ('photos','Fotos',2),
           ('renditions','Rendiciones',3), ('calicatas','Calicatas',4),
           ('other','Otros',5)
  )
  select (select coalesce(sum(o.bytes),0)::bigint from objects o),
         (select count(*) from objects o where o.bytes is null),
         jsonb_agg(jsonb_build_object('key',l.key,'label',l.label,
                   'bytes',coalesce(t.bytes,0)) order by l.position)
  into used_bytes, unknown_sizes, categories
  from labels l left join totals t on t.category=l.key;

  if unknown_sizes > 0 then raise exception 'STORAGE_OBJECT_SIZE_UNAVAILABLE'; end if;

  -- Preserve the pre-existing optional scalar for older Drive consumers only.
  -- It never supplies the project total or the project category breakdown.
  select v.used into scoped_bytes from public.inge_drive_storage_usage_v02(p_space_id) v;
  return next jsonb_build_object(
    'used',used_bytes, 'total',capacity, 'remaining',capacity-used_bytes,
    'breakdown',categories, 'scope','project',
    'quota_kind','ADMIN_CONFIGURED_PROJECT_ALLOCATION',
    'measured_at',statement_timestamp(), 'drive_used',scoped_bytes);
end
$function$;

revoke all on function public.inge_drive_storage_usage_v03(uuid) from public, anon, service_role;
grant execute on function public.inge_drive_storage_usage_v03(uuid) to authenticated;
comment on function public.inge_drive_storage_usage_v03(uuid) is
  'Project Storage live object bytes, all buckets/users, aggregated categories only. p_space_id scopes legacy drive_used only. total is the private administrative project allocation; not physical disk capacity or organization billing usage.';

-- Refresh the evidence for the EXISTING allocation, without inventing a default
-- or overwriting a different administrator-configured quota.
-- get_organization(oszcomvakcnumfaecsfo) confirmed Free on 2026-10-27.
-- https://supabase.com/docs/guides/platform/manage-your-usage/storage-size
-- publishes Free=1 GB and uses 1073741824 bytes in its size conversion example.
-- Billing allowance belongs to the organization and averages usage over time;
-- this table instead records the explicit live project budget used by InGe+.
update private.inge_drive_project_storage_config
set verified_at=statement_timestamp(),
    verification_note='2026-10-27: get_organization confirmed Free. Existing administrator-configured project allocation is 1073741824 bytes (1 GiB), consistent with published Free 1 GB size units. This is an explicit project budget, not free physical disk, not a hard Storage limit, and not remaining organization billing allowance. Reverify after plan/allocation changes.'
where singleton and capacity_bytes=1073741824 and plan='free';
