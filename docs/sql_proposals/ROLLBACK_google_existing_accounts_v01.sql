-- First disable the Before User Created hook in InGePlus-Dev Auth Hooks.
-- Then run this rollback. No users, profiles or local data are changed.
drop function if exists public.hook_google_existing_accounts_v01(jsonb);
