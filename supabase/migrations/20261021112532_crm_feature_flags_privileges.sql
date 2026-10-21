-- Function privileges for feature flags (P1-09). Hand-written: `db diff`
-- does not emit EXECUTE changes. Mirrors schemas/10_crm/10-40_grants.sql.

revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.has_feature(uuid, text) to anon, authenticated;
grant execute on function crm.require_feature(uuid, text) to anon, authenticated;
grant execute on function crm.get_features(uuid) to anon, authenticated;
