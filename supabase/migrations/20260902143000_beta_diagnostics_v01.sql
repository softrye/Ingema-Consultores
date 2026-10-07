-- InGe+ internal beta diagnostics V01.
-- Technical telemetry only: no credentials, user content, exact location,
-- request/response bodies, financial values, emails, names or phone numbers.

create schema if not exists private;

create table if not exists private.beta_diagnostic_sessions (
  id uuid primary key,
  actor_id uuid not null references auth.users(id) on delete cascade,
  install_id uuid not null,
  platform text not null check (platform in ('android')),
  app_version text not null check (char_length(app_version) <= 40),
  app_build text not null check (char_length(app_build) <= 40),
  device jsonb not null default '{}'::jsonb
    check (jsonb_typeof(device) = 'object' and pg_column_size(device) <= 32768),
  started_at timestamptz not null default clock_timestamp(),
  last_seen_at timestamptz not null default clock_timestamp(),
  ended_at timestamptz,
  end_reason text check (end_reason in ('LOGOUT', 'NORMAL', 'UNKNOWN'))
);

create table if not exists private.beta_diagnostic_events (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null
    references private.beta_diagnostic_sessions(id) on delete cascade,
  seq bigint not null check (seq > 0),
  captured_at timestamptz not null,
  category text not null check (
    char_length(category) between 1 and 40
    and category ~ '^[A-Z0-9_]+$'
  ),
  severity text not null check (
    severity in ('DEBUG', 'INFO', 'WARNING', 'ERROR', 'FATAL')
  ),
  code text not null check (
    char_length(code) between 1 and 100
    and code ~ '^[A-Z0-9_]+$'
  ),
  message text check (message is null or char_length(message) <= 1000),
  metrics jsonb not null default '{}'::jsonb check (jsonb_typeof(metrics) = 'object'),
  context jsonb not null default '{}'::jsonb check (jsonb_typeof(context) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  unique (session_id, seq)
);

create index if not exists beta_diagnostic_sessions_actor_started_idx
  on private.beta_diagnostic_sessions (actor_id, started_at desc);
create index if not exists beta_diagnostic_events_session_captured_idx
  on private.beta_diagnostic_events (session_id, captured_at);

alter table private.beta_diagnostic_sessions enable row level security;
alter table private.beta_diagnostic_events enable row level security;

revoke all on table private.beta_diagnostic_sessions
  from public, anon, authenticated;
revoke all on table private.beta_diagnostic_events
  from public, anon, authenticated;

comment on table private.beta_diagnostic_sessions is
  'Disclosed internal-beta technical sessions. Not user-content surveillance.';
comment on table private.beta_diagnostic_events is
  'Sanitized structured internal-beta events. Direct client DML is forbidden.';

create or replace function public.begin_beta_diagnostic_session_v01(
  p_session_id uuid,
  p_install_id uuid,
  p_platform text,
  p_app_version text,
  p_app_build text,
  p_device jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_existing_actor uuid;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if p_session_id is null or p_install_id is null
     or p_platform <> 'android'
     or char_length(coalesce(p_app_version, '')) > 40
     or char_length(coalesce(p_app_build, '')) > 40
     or jsonb_typeof(coalesce(p_device, '{}'::jsonb)) <> 'object'
     or pg_column_size(coalesce(p_device, '{}'::jsonb)) > 32768 then
    raise exception using errcode = '22023', message = 'invalid diagnostic session';
  end if;

  select session.actor_id
    into v_existing_actor
    from private.beta_diagnostic_sessions as session
   where session.id = p_session_id;
  if v_existing_actor is not null and v_existing_actor <> v_actor then
    raise exception using errcode = '42501', message = 'session ownership mismatch';
  end if;

  insert into private.beta_diagnostic_sessions (
    id, actor_id, install_id, platform, app_version, app_build, device
  ) values (
    p_session_id, v_actor, p_install_id, p_platform,
    coalesce(p_app_version, ''), coalesce(p_app_build, ''),
    coalesce(p_device, '{}'::jsonb)
  )
  on conflict (id) do update
    set last_seen_at = clock_timestamp()
    where beta_diagnostic_sessions.actor_id = v_actor;

  return p_session_id;
end;
$$;

create or replace function public.append_beta_diagnostic_events_v01(
  p_session_id uuid,
  p_events jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_count integer;
  v_inserted integer;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if p_session_id is null or jsonb_typeof(p_events) <> 'array' then
    raise exception using errcode = '22023', message = 'events must be an array';
  end if;
  v_count := jsonb_array_length(p_events);
  if v_count < 1 or v_count > 200 or pg_column_size(p_events) > 524288 then
    raise exception using errcode = '22023', message = 'invalid diagnostic batch';
  end if;
  if p_events::text ~* '"(password|access_token|refresh_token|authorization|apikey|request_body|response_body)"[[:space:]]*:'
     or p_events::text ~* 'Bearer[[:space:]]+[A-Za-z0-9._~+/=-]+'
     or p_events::text ~ '[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' then
    raise exception using errcode = '22023', message = 'unsafe diagnostic payload';
  end if;
  if not exists (
    select 1 from private.beta_diagnostic_sessions as session
     where session.id = p_session_id and session.actor_id = v_actor
  ) then
    raise exception using errcode = '42501', message = 'diagnostic session unavailable';
  end if;

  insert into private.beta_diagnostic_events (
    id, session_id, seq, captured_at, category, severity, code,
    message, metrics, context
  )
  select
    coalesce(nullif(event->>'id', '')::uuid, gen_random_uuid()),
    p_session_id,
    (event->>'seq')::bigint,
    (event->>'captured_at')::timestamptz,
    left(upper(event->>'category'), 40),
    upper(event->>'severity'),
    left(upper(event->>'code'), 100),
    nullif(left(event->>'message', 1000), ''),
    case when jsonb_typeof(event->'metrics') = 'object'
      then event->'metrics' else '{}'::jsonb end,
    case when jsonb_typeof(event->'context') = 'object'
      then event->'context' else '{}'::jsonb end
  from jsonb_array_elements(p_events) as item(event)
  on conflict (session_id, seq) do nothing;
  get diagnostics v_inserted = row_count;

  update private.beta_diagnostic_sessions
     set last_seen_at = clock_timestamp()
   where id = p_session_id and actor_id = v_actor;
  return v_inserted;
end;
$$;

create or replace function public.finish_beta_diagnostic_session_v01(
  p_session_id uuid,
  p_end_reason text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_updated integer;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;
  if upper(coalesce(p_end_reason, '')) not in ('LOGOUT', 'NORMAL', 'UNKNOWN') then
    raise exception using errcode = '22023', message = 'invalid end reason';
  end if;

  update private.beta_diagnostic_sessions
     set ended_at = coalesce(ended_at, clock_timestamp()),
         last_seen_at = clock_timestamp(),
         end_reason = coalesce(end_reason, upper(p_end_reason))
   where id = p_session_id and actor_id = v_actor;
  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$$;

revoke execute on function public.begin_beta_diagnostic_session_v01(
  uuid, uuid, text, text, text, jsonb
) from public, anon;
revoke execute on function public.append_beta_diagnostic_events_v01(
  uuid, jsonb
) from public, anon;
revoke execute on function public.finish_beta_diagnostic_session_v01(
  uuid, text
) from public, anon;

grant execute on function public.begin_beta_diagnostic_session_v01(
  uuid, uuid, text, text, text, jsonb
) to authenticated;
grant execute on function public.append_beta_diagnostic_events_v01(
  uuid, jsonb
) to authenticated;
grant execute on function public.finish_beta_diagnostic_session_v01(
  uuid, text
) to authenticated;
