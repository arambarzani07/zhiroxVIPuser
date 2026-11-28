-- Mirrors the migration already applied to VIP production at version 20261128045515.
-- Requires the established VIP database baseline. Fail closed on unknown revisions.
-- Permanent links (expires_at IS NULL) are intentionally preserved.
-- Does not update customer data, token rows, or existing function privileges.
DO $patch$
DECLARE
  old_definition text;
  new_definition text;
  needle constant text := E'      and link.revoked_at is null\n    limit 1;';
  replacement constant text := E'      and link.revoked_at is null\n      and (link.expires_at is null or link.expires_at > now())\n    limit 1;';
  target_oid constant regprocedure := 'public.read_customer_push_portal_service(text,text,text,integer)'::regprocedure;
BEGIN
  SELECT pg_get_functiondef(target_oid) INTO STRICT old_definition;
  IF md5(old_definition) <> '8c7b92de0f03e2ee9eddcf80ecdbd829' THEN
    RAISE EXCEPTION 'Unexpected portal function revision; patch aborted';
  END IF;
  IF (length(old_definition)-length(replace(old_definition,needle,'')))/length(needle) <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one token condition; patch aborted';
  END IF;
  new_definition := replace(old_definition,needle,replacement);
  EXECUTE new_definition;
  IF pg_get_functiondef(target_oid) <> new_definition THEN
    RAISE EXCEPTION 'Definition verification failed; patch aborted';
  END IF;
  IF has_function_privilege('anon',target_oid,'EXECUTE') OR has_function_privilege('authenticated',target_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'Unexpected public execute privilege; patch aborted';
  END IF;
END
$patch$;
