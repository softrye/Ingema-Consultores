-- Every mutation is in a rolled-back transaction. No production document is changed.
begin;
do $$
declare member record; cap record; chosen uuid; folder uuid:=gen_random_uuid(); op uuid:=gen_random_uuid();
 r jsonb; retry jsonb; child uuid:=gen_random_uuid(); version bigint; stat jsonb; actual_bytes bigint;
begin
 for member in select p.id profile_id,s.id space_id from public.profiles p cross join public.document_spaces s loop
  perform set_config('request.jwt.claim.sub',member.profile_id::text,true);
  begin
   select * into cap from public.get_document_structural_capabilities_v01(member.space_id,null);
   if cap.can_create_folder then chosen:=member.space_id; exit; end if;
  exception when others then null; end;
 end loop;
 if chosen is null then raise exception 'NO_TEST_PROFILE_WITH_FOLDER_CAPABILITY'; end if;
 select x into r from public.inge_drive_mutate_v03(op,'CREATE_FOLDER',chosen,folder,null,'Beta21_test_'||folder::text) x;
 if not (r->>'success')::boolean then raise exception 'CREATE_FAILED %',r; end if;
 if not exists(select 1 from public.document_nodes where id=folder) then raise exception 'STABLE_ID_FAILED'; end if;
 select x into retry from public.inge_drive_mutate_v03(op,'CREATE_FOLDER',chosen,folder,null,'Beta21_test_'||folder::text) x;
 if retry<>r then raise exception 'IDEMPOTENCY_FAILED'; end if;
 select node_version into version from public.document_nodes where id=folder;
 select x into r from public.inge_drive_mutate_v03(gen_random_uuid(),'RENAME',chosen,folder,null,'Beta21_renamed_'||folder::text,version) x;
 if not (r->>'success')::boolean then raise exception 'RENAME_FAILED %',r; end if;
 select x into r from public.inge_drive_mutate_v03(gen_random_uuid(),'RENAME',chosen,folder,null,'Beta21_stale_'||folder::text,version) x;
 if r->>'error_code'<>'STALE_VERSION' then raise exception 'CONFLICT_FAILED %',r; end if;
 select x into r from public.inge_drive_mutate_v03(gen_random_uuid(),'CREATE_FOLDER',chosen,child,folder,'child') x;
 if not (r->>'success')::boolean then raise exception 'CHILD_FAILED %',r; end if;
 select node_version into version from public.document_nodes where id=folder;
 select x into r from public.inge_drive_mutate_v03(gen_random_uuid(),'TRASH',chosen,folder,null,null,version,false) x;
 if r->>'error_code'<>'NONEMPTY_CONFIRMATION_REQUIRED' then raise exception 'NONEMPTY_GUARD_FAILED %',r; end if;
 select x into r from public.inge_drive_mutate_v03(gen_random_uuid(),'TRASH',chosen,folder,null,null,version,true) x;
 if not (r->>'success')::boolean then raise exception 'TRASH_FAILED %',r; end if;
 if not exists(select 1 from public.document_nodes where id=child) then raise exception 'CHILD_DATA_LOST'; end if;
 select x into stat from public.inge_drive_storage_usage_v03(chosen) x;
 select coalesce(sum(case when metadata->>'size' ~ '^[0-9]{1,18}$' then (metadata->>'size')::bigint else 0 end),0)::bigint into actual_bytes from storage.objects;
 if (stat->>'total')::bigint<>1073741824 or (stat->>'used')::bigint<>actual_bytes or
    (stat->>'remaining')::bigint<>greatest(1073741824-actual_bytes,0) then raise exception 'STORAGE_FAILED'; end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 select x into stat from public.inge_drive_storage_usage_v03(null) x;
 if (stat->>'used')::bigint<>0 or stat->>'total' is not null then raise exception 'OUTSIDER_STORAGE_LEAK'; end if;
end $$;
select 'SERVER_RUNTIME_VALIDATED' as status,
 'create stable UUID, idempotent retry, rename, stale conflict, nonempty guard, soft trash, retained child, real storage, outsider scope' as tests;
rollback;
