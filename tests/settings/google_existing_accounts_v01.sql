-- Read-only behavioral tests; no Auth users or sessions are created.
do $test$
begin
  assert public.hook_google_existing_accounts_v01('{"user":{"app_metadata":{"provider":"google","providers":["google"]}}}') #>> '{error,http_code}' = '403';
  assert public.hook_google_existing_accounts_v01('{"user":{"app_metadata":{"provider":"google"}}}') #>> '{error,message}' = 'GOOGLE_ACCOUNT_NOT_REGISTERED';
  assert public.hook_google_existing_accounts_v01('{"user":{"app_metadata":{"provider":"email","providers":["email","google"]}}}') #>> '{error,http_code}' = '403';
  assert public.hook_google_existing_accounts_v01('{"user":{"app_metadata":{"provider":"email"},"user_metadata":{"provider":"google"}}}') = '{}'::jsonb;
  assert public.hook_google_existing_accounts_v01('{"user":{"app_metadata":{"provider":"github"}}}') = '{}'::jsonb;
  assert public.hook_google_existing_accounts_v01('{}') #>> '{error,http_code}' = '400';
  assert not pg_catalog.has_function_privilege('anon','public.hook_google_existing_accounts_v01(jsonb)','execute');
  assert not pg_catalog.has_function_privilege('authenticated','public.hook_google_existing_accounts_v01(jsonb)','execute');
  assert pg_catalog.has_function_privilege('supabase_auth_admin','public.hook_google_existing_accounts_v01(jsonb)','execute');
end
$test$;
select 'PASS: 9 Google signup hook and privilege checks' as result;
