-- Function privileges for webhook hardening (P2-01). Hand-written: `db diff`
-- does not emit EXECUTE changes. Mirrors schemas/10_crm/10-40_grants.sql.
--
-- Without this, crm.claim_webhook_event/replay_webhook_event/
-- purge_webhook_events would keep Postgres's default PUBLIC execute grant —
-- letting any anon/authenticated caller read raw webhook bodies (PII) by
-- guessing a row id, since the functions are SECURITY DEFINER and the
-- table's RLS has no policies for those roles to fall back on.

revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;
