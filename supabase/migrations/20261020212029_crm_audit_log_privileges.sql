-- Function privileges for the audit log (P1-08). Hand-written: `db diff` does
-- not emit EXECUTE changes. Mirrors schemas/10_crm/10-40_grants.sql.
--
-- New functions get EXECUTE for PUBLIC by default; take it back so none of
-- them is reachable through /rest/v1/rpc except get_audit_log (which checks
-- audit.view). write_audit stays service_role only: members and API keys
-- could otherwise forge entries.

revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.get_audit_log(uuid, bigint, int, text, uuid, timestamp with time zone, timestamp with time zone) to authenticated;

-- The table: read-only for every API role (the generated migration grants
-- select; this makes sure nothing else is held).
revoke insert, update, delete, truncate, references, trigger on crm.audit_log from anon, authenticated, service_role;
revoke select on crm.audit_log from anon;
