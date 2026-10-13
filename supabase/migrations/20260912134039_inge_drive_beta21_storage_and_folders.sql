-- Beta 2.1: additive configuration; no phone capacity and no invented defaults.
create table private.inge_drive_project_storage_config (
  singleton boolean primary key default true check(singleton),
  capacity_bytes bigint not null check(capacity_bytes>0),
  plan text not null, source_url text not null, verified_at timestamptz not null,
  verification_note text not null
);
alter table private.inge_drive_project_storage_config enable row level security;
revoke all on private.inge_drive_project_storage_config from public,anon,authenticated;
comment on table private.inge_drive_project_storage_config is
  'Administrative project allocation. Set only after verifying the plan; billing quota is not physical disk capacity.';

create function public.inge_drive_storage_usage_v03(p_space_id uuid default null)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
declare bytes bigint; capacity bigint; scoped jsonb;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if not exists(select 1 from public.document_spaces s where
    (p_space_id is null or s.id=p_space_id) and private.can_read_document_space_content_v01(s.id)) then
    return next jsonb_build_object('used',0,'total',null,'remaining',null,'breakdown','[]'::jsonb); return;
  end if;
  -- Whole project physical usage, including retained versions and other buckets,
  -- so remaining space never overstates the server allocation. Only aggregates escape.
  select coalesce(sum(case when metadata->>'size' ~ '^[0-9]{1,18}$'
    then (metadata->>'size')::bigint else 0 end),0)::bigint into bytes from storage.objects;
  select capacity_bytes into capacity from private.inge_drive_project_storage_config where singleton;
  select to_jsonb(r) into scoped from public.inge_drive_storage_usage_v02(p_space_id) r;
  return next jsonb_build_object('used',bytes,'total',capacity,
    'remaining',case when capacity is null then null else greatest(capacity-bytes,0) end,
    'drive_used',scoped->'used','breakdown',scoped->'breakdown','scope','PROJECT_STORAGE',
    'quota_kind','ADMIN_VERIFIED_PLAN_ALLOCATION','measured_at',now());
end $$;
revoke all on function public.inge_drive_storage_usage_v03(uuid) from public,anon;
grant execute on function public.inge_drive_storage_usage_v03(uuid) to authenticated;

-- Preserve the existing authorization/governance implementation. Its CREATE
-- branch now consumes the already-present optional node id; older callers pass NULL.
do $$
declare definition text; revised text;
begin
  select pg_get_functiondef(p.oid) into definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname='apply_document_node_mutation_v01';
  revised:=replace(definition, E'project_id, space_id, parent_id, node_kind, node_type, lifecycle,',
    E'id, project_id, space_id, parent_id, node_kind, node_type, lifecycle,');
  revised:=replace(revised, E'v_space.project_id, v_space.id, p_parent_node_id,',
    E'coalesce(p_node_id,gen_random_uuid()), v_space.project_id, v_space.id, p_parent_node_id,');
  if revised=definition or position('coalesce(p_node_id,gen_random_uuid())' in revised)=0 then
    raise exception 'BASE_FOLDER_IMPLEMENTATION_CHANGED';
  end if;
  execute revised;
end $$;

create function public.inge_drive_mutate_v03(p_operation_id uuid,p_operation text,p_space_id uuid,
 p_node_id uuid default null,p_parent_id uuid default null,p_name text default null,
 p_expected_version bigint default null,p_confirm_nonempty boolean default false)
returns setof jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); req jsonb; saved public.inge_drive_operations; result jsonb;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_operation_id is null then raise exception 'OPERATION_ID_REQUIRED'; end if;
  if not private.can_read_document_space_content_v01(p_space_id) then raise exception 'FORBIDDEN'; end if;
  if p_operation not in ('CREATE_FOLDER','RENAME','MOVE','TRASH','RESTORE','ARCHIVE') then raise exception 'OPERATION_UNSUPPORTED'; end if;
  req:=jsonb_build_object('operation',p_operation,'space',p_space_id,'node',p_node_id,
    'parent',p_parent_id,'name',p_name,'expected',p_expected_version);
  perform pg_advisory_xact_lock(hashtextextended(u::text||p_operation_id::text,0));
  select * into saved from public.inge_drive_operations where user_id=u and operation_id=p_operation_id;
  if found then
    if saved.request<>req then raise exception 'IDEMPOTENCY_MISMATCH'; end if;
    return next saved.result; return;
  end if;
  -- Use the same lock as existing structural operations; children cannot race confirmation.
  perform pg_advisory_xact_lock(hashtextextended(p_space_id::text,1301));
  if p_operation='TRASH' and not coalesce(p_confirm_nonempty,false) and exists(
    select 1 from public.document_nodes where parent_id=p_node_id and space_id=p_space_id and lifecycle::text='ACTIVE') then
    return next jsonb_build_object('success',false,'error_code','NONEMPTY_CONFIRMATION_REQUIRED'); return;
  end if;
  if p_operation='CREATE_FOLDER' then
    select to_jsonb(private.apply_document_node_mutation_v01('CREATE_FOLDER',p_space_id,
      coalesce(p_node_id,p_operation_id),p_parent_id,p_name,null)) into result;
  else
    select to_jsonb(private.apply_generic_document_node_mutation_v01(p_operation,p_space_id,
      p_node_id,p_parent_id,p_name,p_expected_version)) into result;
  end if;
  if result is null then raise exception 'MUTATION_NO_RESULT'; end if;
  insert into public.inge_drive_operations values(u,p_operation_id,req,result,now());
  return next result;
end $$;
revoke all on function public.inge_drive_mutate_v03(uuid,text,uuid,uuid,uuid,text,bigint,boolean) from public,anon;
grant execute on function public.inge_drive_mutate_v03(uuid,text,uuid,uuid,uuid,text,bigint,boolean) to authenticated;
