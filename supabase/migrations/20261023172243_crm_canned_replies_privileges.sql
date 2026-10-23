revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.create_canned_reply(uuid, text, text) to authenticated;
grant execute on function crm.update_canned_reply(uuid, text, text) to authenticated;
grant execute on function crm.delete_canned_reply(uuid) to authenticated;
