-- Completed purge domains, not purge_entities (those identify document nodes).
-- Keep historical rows; expose their lifecycle without attempting Storage reads.
begin;

create function private.calicata_domain_purged_v01(p_calicata_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select p_calicata_id is not null
    and private.files_document_domain_frozen_v06(p_calicata_id)
    and exists (
      select 1 from private.files_document_purges_v06 p
      where p.completed_at is not null
        and p.preview->'domains' @> jsonb_build_array(
          jsonb_build_object('kind','CALICATA','id',p_calicata_id::text))
    );
$$;
revoke all on function private.calicata_domain_purged_v01(uuid) from public, anon;
grant execute on function private.calicata_domain_purged_v01(uuid) to authenticated;

-- Media already denies frozen domains. Calicatas still admits the surviving
-- historical rows; make completed lifecycle exclusion explicit on both tables.
create policy calicatas_completed_purge_read_guard_v01 on public.calicatas
as restrictive for select to authenticated
using (not private.calicata_domain_purged_v01(id));
create policy calicata_media_completed_purge_read_guard_v01 on public.calicata_media
as restrictive for select to authenticated
using (not private.calicata_domain_purged_v01(calicata_id));

-- This narrow definer reads private purge metadata and Storage existence only.
-- Authorization is checked before returning any document/media identifier.
create function public.get_my_calicata_media_read_state_v01(
  p_project_id uuid, p_calicata_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null or not private.is_active_profile() or p_project_id is null then
    raise exception using errcode='42501',message='No autorizado para consultar Calicatas.';
  end if;
  if p_calicata_id is null then
    if not private.can_read_project(p_project_id) then
      raise exception using errcode='42501',message='No autorizado para consultar Calicatas.';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'calicata_id',c.id,
      'state',case when private.calicata_domain_purged_v01(c.id) then 'PURGED' else 'ACTIVE' end
    ) order by c.id),'[]'::jsonb) into result
    from public.calicatas c where c.project_id=p_project_id
      and private.can_read_calicata_media_v01_before_purge_v06(p_project_id,c.id);
    return jsonb_build_object('calicatas',result);
  end if;
  if not private.can_read_calicata_media_v01_before_purge_v06(p_project_id,p_calicata_id) then
    raise exception using errcode='42501',message='No autorizado para consultar Calicatas.';
  end if;
  if private.calicata_domain_purged_v01(p_calicata_id) then
    return jsonb_build_object('calicata_id',p_calicata_id,'state','PURGED','media','[]'::jsonb);
  end if;
  -- A pending purge is not a completed one and must not be represented as empty.
  if private.files_document_domain_frozen_v06(p_calicata_id) then
    return jsonb_build_object('calicata_id',p_calicata_id,'state','FROZEN','media','[]'::jsonb);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'media_id',m.media_id,'version_id',m.active_version_id,
    'original_state',case when exists(select 1 from storage.objects o
      where o.bucket_id=m.original_bucket and o.name=m.original_storage_path)
      then 'READY' else 'MISSING' end,
    'derivative_state',case when v.derivative_storage_path is null then 'NONE'
      when exists(select 1 from storage.objects o
        where o.bucket_id=v.derivative_bucket and o.name=v.derivative_storage_path)
      then 'READY' else 'MISSING' end
  ) order by m.media_id),'[]'::jsonb) into result
  from public.calicata_media m left join public.calicata_media_versions v
    on v.version_id=m.active_version_id and v.media_id=m.media_id
  where m.project_id=p_project_id and m.calicata_id=p_calicata_id
    and m.sync_state='UPLOADED' and m.discarded_at is null;
  return jsonb_build_object('calicata_id',p_calicata_id,'state','ACTIVE','media',result);
end;
$$;
revoke all on function public.get_my_calicata_media_read_state_v01(uuid,uuid) from public, anon;
grant execute on function public.get_my_calicata_media_read_state_v01(uuid,uuid) to authenticated;
comment on function public.get_my_calicata_media_read_state_v01(uuid,uuid) is
  'Authorized read-only Calicata lifecycle and media existence. PURGED never returns Storage paths or URLs.';
commit;
