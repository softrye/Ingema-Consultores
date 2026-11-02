-- Manual rollback only. No historical/local/business rows are modified.
begin;
drop policy if exists calicata_media_completed_purge_read_guard_v01 on public.calicata_media;
drop policy if exists calicatas_completed_purge_read_guard_v01 on public.calicatas;
drop function if exists public.get_my_calicata_media_read_state_v01(uuid,uuid);
drop function if exists private.calicata_domain_purged_v01(uuid);
commit;
