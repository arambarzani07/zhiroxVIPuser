-- Read-only security release checks; run as an authorized database administrator.
-- No financial records, customer details or secret values returned.
BEGIN TRANSACTION READ ONLY;
SELECT 'public_tables_all_rls' AS gate, NOT EXISTS (
 SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relkind IN ('r','p') AND NOT c.relrowsecurity
) AS passed
UNION ALL SELECT 'private_tables_no_client_read', NOT EXISTS (
 SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='private' AND c.relkind IN ('r','p','v','m')
 AND (has_table_privilege('anon',c.oid,'SELECT') OR has_table_privilege('authenticated',c.oid,'SELECT'))
)
UNION ALL SELECT 'vault_no_client_read',
 NOT has_table_privilege('anon','vault.decrypted_secrets','SELECT')
 AND NOT has_table_privilege('authenticated','vault.decrypted_secrets','SELECT')
UNION ALL SELECT 'no_anonymous_public_security_definer', NOT EXISTS (
 SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('anon',p.oid,'EXECUTE')
)
UNION ALL SELECT 'anonymous_market_directory_no_sensitive_columns',
 NOT has_column_privilege('anon','public.profiles','phone','SELECT')
 AND NOT has_column_privilege('anon','public.profiles','telegram_chat_id','SELECT')
 AND NOT has_column_privilege('anon','public.profiles','password_reset_required','SELECT');
-- A failing directory gate requires compatible registration UI and a restricted
-- public directory before revoking broad profile SELECT. Do not blindly revoke.
-- Separately review authenticated SECURITY DEFINER authorization and password policy.
ROLLBACK;
