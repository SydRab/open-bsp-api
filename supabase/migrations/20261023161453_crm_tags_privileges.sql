-- Function privileges for tags (P2-09b). Hand-written: db diff does not
-- emit EXECUTE changes for brand-new functions, blanket or per-function
-- grants alike. Mirrors schemas/10_crm/10-40_grants.sql, including the
-- authenticated grants for the 5 tag functions (they do their own
-- crm.require_permission check, same as crm.create_team & co., so members
-- call them directly rather than through an edge function).

revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.create_tag(uuid, text) to authenticated;
grant execute on function crm.rename_tag(uuid, text) to authenticated;
grant execute on function crm.set_tag_color(uuid, text) to authenticated;
grant execute on function crm.delete_tag(uuid) to authenticated;
grant execute on function crm.set_conversation_tag(uuid, uuid, boolean) to authenticated;
