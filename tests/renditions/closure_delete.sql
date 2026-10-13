-- Transactional regression. No changes survive this test.
begin;
do $test$
declare r public.renditions%rowtype; e public.rendition_expenses%rowtype; result record; replay record;
begin
 select d.* into r from public.renditions d join public.profiles p on p.id=d.owner_user_id
 where d.status='BORRADOR' and d.archived_at is null and d.current_version_id is null and p.status='ACTIVO'
 and not exists(select 1 from public.rendition_versions v where v.rendition_id=d.id)
 and exists(select 1 from public.rendition_expenses x where x.rendition_id=d.id and x.archived_at is null and x.review_status='PENDIENTE')
 order by d.id limit 1;
 if r.id is null then raise exception 'TEST_FIXTURE_MISSING'; end if;
 perform set_config('request.jwt.claim.sub',r.owner_user_id::text,true);
 select x.* into e from public.rendition_expenses x where x.rendition_id=r.id and x.archived_at is null and x.review_status='PENDIENTE' limit 1;
 begin
   perform public.delete_my_rendition_expense_v01(r.id,e.id,e.row_version,-1);
   raise exception 'TEST_CAS_NOT_ENFORCED';
 exception when others then if sqlerrm <> 'RENDITION_VERSION_CONFLICT' then raise; end if; end;
 select * into result from public.delete_my_rendition_expense_v01(r.id,e.id,e.row_version,r.row_version);
 select * into replay from public.delete_my_rendition_expense_v01(r.id,e.id,e.row_version,r.row_version);
 if replay.result_code <> 'IDEMPOTENT_REPLAY' or replay.expense_row_version <> result.expense_row_version then raise exception 'TEST_DELETE_REPLAY'; end if;
 if exists(select 1 from public.rendition_expense_attachments a where a.expense_id=e.id and a.archived_at is null) then raise exception 'TEST_ATTACHMENT_CASCADE'; end if;
 select * into result from public.delete_my_rendition_draft_v01(r.id,result.rendition_row_version);
 select * into replay from public.delete_my_rendition_draft_v01(r.id,r.row_version);
 if replay.result_code <> 'IDEMPOTENT_REPLAY' or replay.row_version <> result.row_version then raise exception 'TEST_DRAFT_REPLAY'; end if;
 if exists(select 1 from public.rendition_expenses x where x.rendition_id=r.id and x.archived_at is null) then raise exception 'TEST_CHILDREN_REMAIN'; end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000000',true);
 begin
   perform public.delete_my_rendition_draft_v01(r.id,r.row_version);
   raise exception 'TEST_OWNER_GUARD';
 exception when others then if sqlerrm not in ('PROFILE_NOT_ACTIVE','RENDITION_NOT_FOUND_OR_FORBIDDEN') then raise; end if; end;
end;
$test$;
rollback;
select 'PASS: CAS, expense replay, attachment cascade, draft replay, children, unauthorized caller; rolled back' as result;
