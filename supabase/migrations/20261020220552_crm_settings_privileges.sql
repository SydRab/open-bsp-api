-- Function privileges for settings and teams (P1-04). Hand-written: `db diff`
-- does not emit EXECUTE changes. Mirrors schemas/10_crm/10-40_grants.sql.

revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.get_setting(uuid, text, uuid) to anon, authenticated;
grant execute on function crm.get_settings(uuid) to anon, authenticated;
grant execute on function crm.set_setting(uuid, text, jsonb, text, uuid) to authenticated;
grant execute on function crm.reset_setting(uuid, text, text, uuid) to authenticated;
grant execute on function crm.create_team(uuid, text) to authenticated;
grant execute on function crm.rename_team(uuid, text) to authenticated;
grant execute on function crm.delete_team(uuid) to authenticated;
grant execute on function crm.set_team_member(uuid, uuid, boolean) to authenticated;
