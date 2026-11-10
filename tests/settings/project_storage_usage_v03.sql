-- Run through Supabase execute_sql on InGePlus-Dev only. No persistent writes.
-- A scoped response, duplicated objects, leaked identifiers, or anon EXECUTE
-- must fail these checks. The caller is an existing active, non-admin LECTOR.
begin;
create temp table storage_expected on commit drop as
select coalesce(sum((metadata->>'size')::bigint),0)::bigint as used,
       (select capacity_bytes from private.inge_drive_project_storage_config where singleton) as total
from storage.objects;
grant select on storage_expected to authenticated;
do $$
declare reader uuid;
begin
  select id into strict reader from public.profiles
  where role::text='LECTOR' and global_role is null and status::text='ACTIVO'
  order by id limit 1;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',reader,'role','authenticated')::text,true);
end $$;
set local role authenticated;
do $$
declare payload jsonb; other jsonb; expected record; item jsonb;
begin
  select * into strict expected from storage_expected;
  select r into strict payload from public.inge_drive_storage_usage_v03(null) r;
  if payload->>'scope' is distinct from 'project' then raise exception 'FAIL_PROJECT_SCOPE'; end if;
  if (payload->>'used')::bigint is distinct from expected.used then raise exception 'FAIL_ALL_BUCKET_BYTES'; end if;
  if (payload->>'total')::bigint is distinct from expected.total then raise exception 'FAIL_CONFIGURED_QUOTA'; end if;
  if (payload->>'remaining')::bigint is distinct from expected.total-expected.used then raise exception 'FAIL_REMAINING'; end if;
  if jsonb_typeof(payload->'breakdown') is distinct from 'array'
     or jsonb_array_length(payload->'breakdown')<>5 then raise exception 'FAIL_FIVE_CATEGORIES'; end if;
  if (select jsonb_agg(x->>'label' order by ord) from jsonb_array_elements(payload->'breakdown') with ordinality a(x,ord))
     is distinct from '["Documentos","Fotos","Rendiciones","Calicatas","Otros"]'::jsonb then raise exception 'FAIL_SPANISH_LABELS'; end if;
  if (select sum((x->>'bytes')::bigint) from jsonb_array_elements(payload->'breakdown') x)
     is distinct from expected.used then raise exception 'FAIL_CATEGORY_SUM'; end if;
  for item in select * from jsonb_array_elements(payload->'breakdown') loop
    if (select count(*) from jsonb_object_keys(item))<>3 or not item ?& array['key','label','bytes']
       or (item->>'bytes')::bigint<0 then raise exception 'FAIL_AGGREGATES_ONLY'; end if;
  end loop;
  if payload->>'quota_kind' is null or (payload->>'measured_at')::timestamptz is null then raise exception 'FAIL_PROVENANCE'; end if;
  select r into strict other from public.inge_drive_storage_usage_v03('00000000-0000-0000-0000-000000000000') r;
  if payload is distinct from other then raise exception 'FAIL_SPACE_INDEPENDENCE'; end if;
end $$;
select r as ordinary_reader_result from public.inge_drive_storage_usage_v03(null) r;
reset role;
do $$
begin
  if has_function_privilege('anon','public.inge_drive_storage_usage_v03(uuid)','EXECUTE')
     or has_function_privilege('service_role','public.inge_drive_storage_usage_v03(uuid)','EXECUTE')
     or not has_function_privilege('authenticated','public.inge_drive_storage_usage_v03(uuid)','EXECUTE') then raise exception 'FAIL_EXECUTE_ACL'; end if;
  if not exists(select 1 from pg_proc where oid='public.inge_drive_storage_usage_v03(uuid)'::regprocedure
      and prosecdef and proconfig @> array['search_path=""']) then raise exception 'FAIL_SECURITY_DEFINER_PATH'; end if;
  perform set_config('request.jwt.claims','{}',true);
  begin
    perform public.inge_drive_storage_usage_v03(null);
    raise exception 'FAIL_AUTH_REQUIRED';
  exception when others then
    if sqlerrm<>'AUTH_REQUIRED' then raise; end if;
  end;
end $$;
-- An absent budget must be an explicit error. This update is rolled back and
-- remains invisible to other sessions throughout the transaction.
do $$
declare reader uuid; payload jsonb; measured bigint;
begin
  select id into strict reader from public.profiles
  where role::text='LECTOR' and global_role is null and status::text='ACTIVO'
  order by id limit 1;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',reader,'role','authenticated')::text,true);
  begin
    delete from private.inge_drive_project_storage_config where singleton;
    begin
      perform public.inge_drive_storage_usage_v03(null);
      raise exception 'FAIL_MISSING_QUOTA_NOT_REJECTED';
    exception when others then
      if sqlerrm<>'STORAGE_QUOTA_NOT_CONFIGURED' then raise; end if;
    end;
    -- Roll back this subtransaction, including the temporary deletion.
    raise exception sqlstate 'Z0001' using message='TEST_ROLLBACK_QUOTA_ABSENCE';
  exception when sqlstate 'Z0001' then null;
  end;
  update private.inge_drive_project_storage_config set capacity_bytes=1 where singleton;
  select r into strict payload from public.inge_drive_storage_usage_v03(null) r;
  select used into measured from storage_expected;
  if (payload->>'remaining')::bigint is distinct from 1-measured then raise exception 'FAIL_OVER_QUOTA_SUBTRACTION'; end if;
end $$;
rollback;
