-- Function privileges for the super-admin console (P1-10). Hand-written:
-- `db diff` does not emit EXECUTE changes. Mirrors
-- schemas/10_crm/10-40_grants.sql.

revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.is_platform_admin(uuid) to anon, authenticated;
