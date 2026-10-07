-- InGe Core V1: owner-isolated jobs; the PC receives only controlled leases.
create schema if not exists inge_core_private;
revoke all on schema inge_core_private from public, anon, authenticated;
create table public.inge_ai_workers (
 id uuid primary key, label text not null, enabled boolean not null default true,
 heartbeat_at timestamptz, resources jsonb not null default '{}'
);
alter table public.inge_ai_workers enable row level security;
revoke all on public.inge_ai_workers from anon, authenticated;
grant select on public.inge_ai_workers to authenticated;
create policy worker_health on public.inge_ai_workers for select to authenticated using (enabled);
create table inge_core_private.worker_credentials (
 worker_id uuid primary key references public.inge_ai_workers(id), secret_hash text not null
);
alter table inge_core_private.worker_credentials enable row level security;
create table public.inge_ai_jobs (
 id uuid primary key default gen_random_uuid(), request_id text not null,
 user_id uuid not null references auth.users(id), project_id uuid,
 skill text not null check (skill in ('Renditions','Calicatas','Documents','Drive','Performance')),
 operation text not null, priority integer not null default 1 check (priority between 0 and 2),
 payload jsonb not null, status text not null default 'QUEUED'
 check (status in ('QUEUED','LEASED','PROCESSING','SUCCEEDED','FAILED','CANCELLED')),
 attempts integer not null default 0, created_at timestamptz not null default now(),
 started_at timestamptz, completed_at timestamptz, lease_until timestamptz,
 worker_id uuid references public.inge_ai_workers(id), lease_token uuid,
 result jsonb, error_code text, error_message text,
 unique(user_id, request_id), check (length(request_id) between 1 and 150),
 check (octet_length(payload::text) <= 12582912)
);
create index inge_ai_jobs_queue on public.inge_ai_jobs(status, priority desc, created_at);
create index inge_ai_jobs_worker on public.inge_ai_jobs(worker_id);
alter table public.inge_ai_jobs enable row level security;
revoke all on public.inge_ai_jobs from anon, authenticated;
grant select on public.inge_ai_jobs to authenticated;
create policy jobs_owner_read on public.inge_ai_jobs for select to authenticated
 using (user_id = (select auth.uid()));

create function public.inge_ai_submit(p_request_id text, p_skill text, p_operation text,
 p_payload jsonb, p_project_id uuid default null, p_priority integer default 1)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare j public.inge_ai_jobs; u uuid := auth.uid();
begin
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into j from public.inge_ai_jobs where user_id=u and request_id=p_request_id;
 if found then
  if j.skill<>p_skill or j.operation<>p_operation or j.payload<>p_payload or j.project_id is distinct from p_project_id then
   raise exception 'IDEMPOTENCY_MISMATCH';
  end if;
  return to_jsonb(j) - 'payload' - 'lease_token';
 end if;
 if p_operation not in ('smartfill','review','summarize','sum','thickness','hash') then raise exception 'OPERATION_UNSUPPORTED'; end if;
 -- Project ID is descriptive context, never used as an access grant.
 if (select count(*) from public.inge_ai_jobs where user_id=u and status in ('QUEUED','LEASED','PROCESSING')) >= 6 then raise exception 'QUEUE_LIMIT'; end if;
 insert into public.inge_ai_jobs(user_id,request_id,skill,operation,payload,project_id,priority)
 values(u,p_request_id,p_skill,p_operation,p_payload,p_project_id,p_priority)
 on conflict(user_id,request_id) do nothing returning * into j;
 if not found then
  select * into j from public.inge_ai_jobs where user_id=u and request_id=p_request_id;
  if j.payload<>p_payload or j.skill<>p_skill or j.operation<>p_operation or j.project_id is distinct from p_project_id then raise exception 'IDEMPOTENCY_MISMATCH'; end if;
 end if;
 return to_jsonb(j) - 'payload' - 'lease_token';
end $$;
revoke all on function public.inge_ai_submit(text,text,text,jsonb,uuid,integer) from public,anon;
grant execute on function public.inge_ai_submit(text,text,text,jsonb,uuid,integer) to authenticated;

create function public.inge_ai_cancel(p_request_id text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 update public.inge_ai_jobs set status='CANCELLED',completed_at=now(),lease_token=null
 where user_id=auth.uid() and request_id=p_request_id and status in ('QUEUED','LEASED','PROCESSING');
 return found;
end $$;
revoke all on function public.inge_ai_cancel(text) from public,anon;
grant execute on function public.inge_ai_cancel(text) to authenticated;

-- Deliberate narrow SECURITY DEFINER boundary: no dynamic SQL, table access,
-- user impersonation or arbitrary storage downloads are exposed to the worker.
create function public.inge_ai_worker(p_worker_id uuid, p_secret text, p_action text,
 p_job_id uuid default null, p_lease_token uuid default null, p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare j public.inge_ai_jobs;
begin
 if not exists(select 1 from inge_core_private.worker_credentials c
 join public.inge_ai_workers w on w.id=c.worker_id where c.worker_id=p_worker_id and w.enabled
 and c.secret_hash=encode(extensions.digest(p_secret,'sha256'),'hex')) then raise exception 'WORKER_UNAUTHORIZED'; end if;
 if p_action='heartbeat' then
  if octet_length(p_data::text)>8192 then raise exception 'RESOURCE_LIMIT'; end if;
  update public.inge_ai_workers set heartbeat_at=now(),resources=p_data where id=p_worker_id;
  return jsonb_build_object('ok',true);
 elsif p_action='lease' then
  update public.inge_ai_jobs set status='FAILED',error_code='LEASE_EXHAUSTED',completed_at=now()
   where status in ('LEASED','PROCESSING') and lease_until<now() and attempts>=3;
  select * into j from public.inge_ai_jobs
   where (status='QUEUED' or (status in ('LEASED','PROCESSING') and lease_until<now())) and attempts<3
   order by priority desc,created_at for update skip locked limit 1;
  if not found then return null; end if;
  update public.inge_ai_jobs set status='LEASED',worker_id=p_worker_id,attempts=attempts+1,
   started_at=coalesce(started_at,now()),lease_until=now()+interval '90 seconds',lease_token=gen_random_uuid()
   where id=j.id returning * into j;
  return to_jsonb(j);
 elsif p_action='renew' then
  update public.inge_ai_jobs set lease_until=now()+interval '90 seconds',status='PROCESSING'
   where id=p_job_id and worker_id=p_worker_id and lease_token=p_lease_token
    and lease_until>now() and status in ('LEASED','PROCESSING');
  return jsonb_build_object('ok',found);
 elsif p_action='finish' then
  if octet_length(p_data::text)>262144 or p_data->>'status' not in ('SUCCEEDED','FAILED') then raise exception 'RESULT_INVALID'; end if;
  update public.inge_ai_jobs set status=p_data->>'status',result=p_data->'result',
   error_code=left(p_data->>'error_code',100),error_message=left(p_data->>'error_message',500),
   completed_at=now(),lease_until=null,lease_token=null
   where id=p_job_id and worker_id=p_worker_id and lease_token=p_lease_token
    and lease_until>now() and status in ('LEASED','PROCESSING');
  return jsonb_build_object('ok',found);
 end if;
 raise exception 'WORKER_ACTION_INVALID';
end $$;
revoke all on function public.inge_ai_worker(uuid,text,text,uuid,uuid,jsonb) from public;
grant execute on function public.inge_ai_worker(uuid,text,text,uuid,uuid,jsonb) to anon,authenticated;
alter publication supabase_realtime add table public.inge_ai_jobs;
