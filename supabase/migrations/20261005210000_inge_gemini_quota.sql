-- A durable, atomic quota shared by all Edge Function instances.
create table if not exists public.inge_gemini_quota (
  user_id uuid not null references auth.users(id) on delete cascade,
  operation text not null check (operation in ('chat', 'live-token')),
  bucket timestamptz not null,
  used integer not null check (used > 0),
  primary key (user_id, operation, bucket)
);
alter table public.inge_gemini_quota enable row level security;
revoke all on public.inge_gemini_quota from anon, authenticated;
create or replace function public.consume_inge_gemini_quota(p_operation text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_count integer; v_limit integer;
begin
  if v_user is null or p_operation not in ('chat', 'live-token') then
    raise exception 'Unauthenticated or invalid operation';
  end if;
  v_limit := case when p_operation = 'live-token' then 3 else 20 end;
  delete from public.inge_gemini_quota where user_id = v_user and bucket < now() - interval '1 day';
  insert into public.inge_gemini_quota(user_id, operation, bucket, used)
    values (v_user, p_operation, date_trunc('minute', now()), 1)
  on conflict (user_id, operation, bucket) do update
    set used = public.inge_gemini_quota.used + 1
    where public.inge_gemini_quota.used < v_limit
  returning used into v_count;
  return v_count is not null;
end;
$$;
revoke all on function public.consume_inge_gemini_quota(text) from public, anon;
grant execute on function public.consume_inge_gemini_quota(text) to authenticated;
