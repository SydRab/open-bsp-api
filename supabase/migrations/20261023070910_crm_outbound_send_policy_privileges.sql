-- Function privileges for the outbound send policy (P2-05). Hand-written:
-- db diff does not emit EXECUTE changes. Mirrors schemas/10_crm/10-40_grants.sql.

revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;
