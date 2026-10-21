-- Privileges for contacts and custom fields (P1-06). Hand-written: `db diff`
-- does not emit column grants or EXECUTE changes. Mirrors
-- schemas/10_crm/10-40_grants.sql.

grant update (custom_fields) on crm.contacts to authenticated;

revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.create_custom_field(uuid, text, text, text, jsonb, jsonb, boolean) to authenticated;
grant execute on function crm.update_custom_field(uuid, jsonb, jsonb, boolean) to authenticated;
grant execute on function crm.archive_custom_field(uuid, boolean) to authenticated;
grant execute on function crm.set_contact_fields(uuid, jsonb) to authenticated;
grant execute on function crm.filter_contacts(uuid, jsonb, int, int) to anon, authenticated;
grant execute on function crm.format_custom_field(uuid, text, text, jsonb, text) to anon, authenticated;
grant execute on function crm.clean_custom_fields(jsonb) to anon, authenticated;
grant execute on function crm.custom_field_matches(jsonb, jsonb) to anon, authenticated;
