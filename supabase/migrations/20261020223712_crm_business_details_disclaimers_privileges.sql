-- Privileges for business details and disclaimers (P1-07). Hand-written:
-- `db diff` does not emit column grants or EXECUTE changes. Mirrors
-- schemas/10_crm/10-40_grants.sql.

-- Business details are edited like the rest of the profile (the update
-- policy requires organization.manage).
grant update (
  legal_name, address, support_email, support_phone, website, registrations
) on crm.organization_profiles to authenticated;

revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.get_disclaimers(uuid) to anon, authenticated;
grant execute on function crm.set_disclaimer(uuid, text, text, text) to authenticated;
grant execute on function crm.render_with_disclaimer(uuid, text, text, text) to anon, authenticated;
