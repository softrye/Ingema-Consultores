-- Existing Auth users are resolved/linked by GoTrue before the creation hook.
-- Reject Google only when GoTrue is about to INSERT a new user; email signup remains available.
create or replace function public.hook_google_existing_accounts_v01(event jsonb)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = ''
as $function$
declare
    provider text := pg_catalog.lower(event #>> '{user,app_metadata,provider}');
    providers jsonb := event #> '{user,app_metadata,providers}';
begin
    if provider = 'google' or coalesce(providers, '[]'::jsonb) ? 'google' then
        return pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
            'http_code', 403, 'message', 'GOOGLE_ACCOUNT_NOT_REGISTERED'));
    end if;
    if coalesce(provider, '') = '' then
        return pg_catalog.jsonb_build_object('error', pg_catalog.jsonb_build_object(
            'http_code', 400, 'message', 'AUTH_SIGNUP_PROVIDER_MISSING'));
    end if;
    return '{}'::jsonb;
end;
$function$;
revoke all on function public.hook_google_existing_accounts_v01(jsonb) from public, anon, authenticated;
grant execute on function public.hook_google_existing_accounts_v01(jsonb) to supabase_auth_admin;
comment on function public.hook_google_existing_accounts_v01(jsonb) is
'Before User Created hook: Google can authenticate existing Auth users but cannot create new ones. Enable in Auth Hooks. No email lookup or user_metadata authorization.';
