-- Extend the canonical document model; no replacement of nodes, versions or ACLs.
alter table public.document_versions add column if not exists content_hash text
  check (content_hash is null or content_hash ~ '^[0-9a-f]{64}$');
alter table public.document_versions add column if not exists manifest jsonb;

create table public.inge_drive_storage_config (
  space_id uuid primary key references public.document_spaces(id),
  capacity_bytes bigint check (capacity_bytes > 0),
  updated_at timestamptz not null default now()
);
alter table public.inge_drive_storage_config enable row level security;
revoke all on public.inge_drive_storage_config from public,anon,authenticated;
grant select on public.inge_drive_storage_config to authenticated;
revoke all on public.inge_drive_storage_config from anon;
create policy drive_capacity_read on public.inge_drive_storage_config for select to authenticated
  using (private.can_discover_document_space_v02(space_id));

create table public.inge_drive_events (
  id bigint generated always as identity primary key,
  space_id uuid not null references public.document_spaces(id),
  node_id uuid not null references public.document_nodes(id),
  event_type text not null,
  node_version bigint not null,
  created_at timestamptz not null default now()
);
create index drive_events_space_cursor on public.inge_drive_events(space_id,id);
alter table public.inge_drive_events enable row level security;
revoke all on public.inge_drive_events from public,anon,authenticated;
grant select on public.inge_drive_events to authenticated;
revoke all on public.inge_drive_events from anon;
create policy drive_events_read on public.inge_drive_events for select to authenticated
  using (private.can_read_document_space_content_v01(space_id));
create function private.record_drive_event_v02() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.space_id is not null then
    insert into public.inge_drive_events(space_id,node_id,node_version,event_type)
    values(new.space_id,new.id,new.node_version,
      case when TG_OP='INSERT' then 'FILE_CREATED'
           when new.lifecycle::text='TRASHED' then 'FILE_DELETED'
           when new.current_version_id is distinct from old.current_version_id then 'VERSION_CREATED'
           when new.parent_id is distinct from old.parent_id then 'FILE_MOVED'
           else 'FILE_UPDATED' end);
  end if;
  return new;
end $$;
revoke all on function private.record_drive_event_v02() from public,anon,authenticated;
create trigger drive_events_v02 after insert or update on public.document_nodes
for each row execute function private.record_drive_event_v02();

-- Idempotent envelope around the existing, permission-checked mutation engine.
create table public.inge_drive_operations (
  user_id uuid not null references auth.users(id),
  operation_id uuid not null,
  request jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key(user_id,operation_id)
);
alter table public.inge_drive_operations enable row level security;
revoke all on public.inge_drive_operations from public,anon,authenticated;
grant select on public.inge_drive_operations to authenticated;
revoke all on public.inge_drive_operations from anon;
create policy drive_operations_owner on public.inge_drive_operations for select to authenticated
using (user_id=(select auth.uid()));
create function public.inge_drive_mutate_v02(p_operation_id uuid,p_operation text,p_space_id uuid,
  p_node_id uuid default null,p_parent_id uuid default null,p_name text default null,
  p_expected_version bigint default null)
returns setof jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); req jsonb; saved public.inge_drive_operations; result jsonb;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_operation_id is null then raise exception 'OPERATION_ID_REQUIRED'; end if;
  if p_operation not in ('CREATE_FOLDER','RENAME','MOVE','TRASH','RESTORE','ARCHIVE') then
    raise exception 'OPERATION_UNSUPPORTED'; end if;
  req:=jsonb_build_object('operation',p_operation,'space',p_space_id,'node',p_node_id,
    'parent',p_parent_id,'name',p_name,'expected',p_expected_version);
  perform pg_advisory_xact_lock(hashtextextended(u::text||p_operation_id::text,0));
  select * into saved from public.inge_drive_operations where user_id=u and operation_id=p_operation_id;
  if found then
    if saved.request<>req then raise exception 'IDEMPOTENCY_MISMATCH'; end if;
    return next saved.result; return;
  end if;
  if p_operation='CREATE_FOLDER' then
    select to_jsonb(r) into result from public.create_document_folder_v01(p_space_id,p_parent_id,p_name) r;
  else
    select to_jsonb(private.apply_generic_document_node_mutation_v01(
      p_operation,p_space_id,p_node_id,p_parent_id,p_name,p_expected_version)) into result;
  end if;
  if result is null then raise exception 'MUTATION_NO_RESULT'; end if;
  insert into public.inge_drive_operations values(u,p_operation_id,req,result,now());
  return next result;
end $$;
revoke all on function public.inge_drive_mutate_v02(uuid,text,uuid,uuid,uuid,text,bigint) from public,anon;
grant execute on function public.inge_drive_mutate_v02(uuid,text,uuid,uuid,uuid,text,bigint) to authenticated;

create table public.inge_drive_sync_heads (
  user_id uuid not null references auth.users(id),
  device_id uuid not null,
  space_id uuid not null references public.document_spaces(id),
  last_event_id bigint not null default 0 check(last_event_id>=0),
  updated_at timestamptz not null default now(),
  primary key(user_id,device_id,space_id)
);
alter table public.inge_drive_sync_heads enable row level security;
revoke all on public.inge_drive_sync_heads from public,anon,authenticated;
grant select,insert,update on public.inge_drive_sync_heads to authenticated;
create policy drive_heads_owner on public.inge_drive_sync_heads for all to authenticated
using(user_id=(select auth.uid()) and private.can_read_document_space_content_v01(space_id))
with check(user_id=(select auth.uid()) and private.can_read_document_space_content_v01(space_id));

-- User-scoped derived index. A user's extraction cannot poison another user's search.
create table public.inge_drive_index (
  user_id uuid not null references auth.users(id),
  node_id uuid not null references public.document_nodes(id),
  version_id uuid not null references public.document_versions(id),
  normalized_text text not null check(length(normalized_text)<=24000),
  summary text not null default '' check(length(summary)<=1200),
  keywords text[] not null default '{}',
  source_job_id uuid not null references public.inge_ai_jobs(id),
  indexed_at timestamptz not null default now(),
  search_vector tsvector generated always as
    (to_tsvector('spanish'::regconfig,normalized_text||' '||summary)) stored,
  primary key(user_id,node_id,version_id)
);
create index drive_index_search on public.inge_drive_index using gin(search_vector);
create index drive_index_version on public.inge_drive_index(version_id);
create index drive_index_job on public.inge_drive_index(source_job_id);
alter table public.inge_drive_index enable row level security;
revoke all on public.inge_drive_index from public,anon,authenticated;
grant select on public.inge_drive_index to authenticated;
create policy drive_index_owner on public.inge_drive_index for select to authenticated
using(user_id=(select auth.uid()) and exists(select 1 from public.document_nodes n
  where n.id=node_id and n.current_version_id=version_id and n.lifecycle::text<>'TRASHED'));

create function public.inge_drive_publish_index_v02(p_job_id uuid,p_node_id uuid,p_version_id uuid)
returns setof jsonb language plpgsql security definer set search_path='' as $$
declare j public.inge_ai_jobs;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into j from public.inge_ai_jobs where id=p_job_id and user_id=auth.uid()
    and status='SUCCEEDED' and skill='Drive' and operation='summarize';
  if not found or j.payload->'context'->>'entity_id' is distinct from p_node_id::text
    or j.payload->'context'->'entity'->>'version_id' is distinct from p_version_id::text then
    raise exception 'INDEX_JOB_MISMATCH'; end if;
  if not exists(select 1 from public.document_nodes n where n.id=p_node_id
    and n.current_version_id=p_version_id and n.lifecycle::text='ACTIVE'
    and private.document_version_is_readable(p_version_id)) then raise exception 'VERSION_CHANGED_OR_FORBIDDEN'; end if;
  if jsonb_typeof(j.result->'normalized_text')<>'string' then raise exception 'INDEX_RESULT_INVALID'; end if;
  insert into public.inge_drive_index(user_id,node_id,version_id,normalized_text,summary,source_job_id)
  values(auth.uid(),p_node_id,p_version_id,left(j.result->>'normalized_text',24000),
    left(coalesce(j.result->>'summary',''),1200),j.id)
  on conflict(user_id,node_id,version_id) do update set normalized_text=excluded.normalized_text,
    summary=excluded.summary,source_job_id=excluded.source_job_id,indexed_at=now();
  return next jsonb_build_object('success',true);
end $$;
revoke all on function public.inge_drive_publish_index_v02(uuid,uuid,uuid) from public,anon;
grant execute on function public.inge_drive_publish_index_v02(uuid,uuid,uuid) to authenticated;

create function public.inge_drive_search_v02(p_query text,p_space_id uuid default null,p_limit int default 100)
returns table(id uuid,space_id uuid,project_id uuid,name text,node_kind text,size_bytes bigint,
  updated_at timestamptz,node_version bigint,current_version_id uuid,snippet text,rank real)
language sql stable security invoker set search_path='' as $$
  select n.id,n.space_id,n.project_id,n.name,n.node_kind::text,n.size_bytes,n.updated_at,
    n.node_version,n.current_version_id,left(coalesce(i.summary,i.normalized_text,''),240),
    ts_rank(i.search_vector,websearch_to_tsquery('spanish',left(p_query,500)))
  from public.document_nodes n
  left join public.inge_drive_index i on i.node_id=n.id and i.version_id=n.current_version_id and i.user_id=auth.uid()
  where auth.uid() is not null and n.lifecycle::text='ACTIVE'
    and (p_space_id is null or n.space_id=p_space_id)
    and length(trim(p_query))>0
    and (strpos(lower(n.name),lower(left(p_query,500)))>0
      or i.search_vector @@ websearch_to_tsquery('spanish',left(p_query,500)))
  order by 11 desc nulls last,n.updated_at desc,n.id limit greatest(1,least(p_limit,100));
$$;
revoke all on function public.inge_drive_search_v02(text,uuid,int) from public,anon;
grant execute on function public.inge_drive_search_v02(text,uuid,int) to authenticated;

create function public.inge_drive_list_v02(p_space_id uuid default null,p_parent_node_id uuid default null)
returns setof jsonb language sql stable security invoker set search_path='' as $$
  select to_jsonb(item)||jsonb_build_object('node_version',n.node_version,
    'current_version_id',n.current_version_id,'content_version',n.binary_content_version)
  from public.list_my_document_explorer_items_v03(p_space_id,p_parent_node_id) item
  left join public.document_nodes n on item.item_kind<>'SPACE' and n.id=item.id;
$$;
revoke all on function public.inge_drive_list_v02(uuid,uuid) from public,anon;
grant execute on function public.inge_drive_list_v02(uuid,uuid) to authenticated;

-- Physical bytes on the server, including historical versions. Never device StatFs.
create function public.inge_drive_storage_usage_v02(p_space_id uuid default null)
returns table(used bigint,total bigint,breakdown jsonb)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  return query
  with permitted as (
    select s.id,s.name from public.document_spaces s where
      (p_space_id is null or s.id=p_space_id) and private.can_read_document_space_content_v01(s.id)
  ), objects as (
    select distinct o.id,o.metadata,p.id space_id,p.name
    from permitted p join public.document_nodes n on n.space_id=p.id
    join public.document_versions v on v.document_node_id=n.id
    join storage.objects o on o.bucket_id=v.storage_bucket and o.name=v.storage_path
  ), usage as (
    select space_id,name,sum(case when metadata->>'size' ~ '^[0-9]{1,18}$'
      then (metadata->>'size')::bigint else 0 end)::bigint bytes from objects group by space_id,name
  ) select coalesce(sum(bytes),0)::bigint,
    (select c.capacity_bytes from public.inge_drive_storage_config c where c.space_id=p_space_id),
    coalesce(jsonb_agg(jsonb_build_object('space_id',space_id,'name',name,'used',bytes)),'[]'::jsonb)
    from usage;
end $$;
revoke all on function public.inge_drive_storage_usage_v02(uuid) from public,anon;
grant execute on function public.inge_drive_storage_usage_v02(uuid) to authenticated;

do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists
    (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='inge_drive_events') then
    alter publication supabase_realtime add table public.inge_drive_events;
  end if;
end $$;
