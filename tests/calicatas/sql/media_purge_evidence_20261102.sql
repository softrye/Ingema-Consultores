-- Read-only evidence. InGePlus-Dev ONLY; observed on 2026-11-02.
-- Do not confuse purge entity_id (document node/space) with calicata_id.
with purge as (
  select * from private.files_document_purges_v06
  where id='5ced58f5-ef83-4ce3-971f-a5a74a472367'
), domains as (
  select (d->>'id')::uuid as id from purge,
    lateral jsonb_array_elements(preview->'domains') d where d->>'kind'='CALICATA'
)
select m.project_id,count(*) as uploaded,
  count(*) filter(where o.id is null) as missing_originals,
  count(distinct m.calicata_id) filter(where o.id is null) as affected_calicatas,
  count(*) filter(where o.id is null and d.id is not null) as missing_in_purge_domains,
  count(*) filter(where o.id is null and d.id is null) as missing_outside_purge_domains,
  count(*) filter(where o.id is null and c.id is not null) as media_with_surviving_calicata,
  count(*) filter(where o.id is null and p.preview->'objects' @>
    jsonb_build_array(jsonb_build_object('bucket',m.original_bucket,'path',m.original_storage_path))) as missing_in_purge_objects
from public.calicata_media m
left join storage.objects o on o.bucket_id=m.original_bucket and o.name=m.original_storage_path
left join domains d on d.id=m.calicata_id
left join public.calicatas c on c.id=m.calicata_id
cross join purge p
where m.sync_state='UPLOADED'
group by m.project_id order by m.project_id;
-- Observed: f4547c5d 29/29 missing in purge (2 calicatas),
-- f066cb63 9/9 missing in purge (3 calicatas), 7fb77795 19/19 originals exist.
-- Missing outside domains = 0; all 38 paths are in preview.objects.

select id,created_at,completed_at from private.files_document_purges_v06
where id='5ced58f5-ef83-4ce3-971f-a5a74a472367';
-- 2026-10-12 14:29:52.517135+00 -> 14:30:00.590598+00.

select p.proname,pg_get_functiondef(p.oid) from pg_proc p
join pg_namespace n on n.oid=p.pronamespace where n.nspname='private'
and p.proname in('can_read_calicata_media_v01','files_document_domain_frozen_v06',
  'files_document_purge_object_allowed_v06');

select tablename,policyname,permissive,qual from pg_policies
where schemaname='public' and tablename in('calicatas','calicata_media');

select has_function_privilege('anon',
 'public.get_my_calicata_media_read_state_v01(uuid,uuid)','EXECUTE') as anon_execute,
 has_function_privilege('authenticated',
 'public.get_my_calicata_media_read_state_v01(uuid,uuid)','EXECUTE') as authenticated_execute;
-- Expected: false / true.
