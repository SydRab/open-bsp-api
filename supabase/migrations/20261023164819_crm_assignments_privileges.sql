revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.assign_conversation(uuid, uuid) to authenticated;
grant execute on function crm.unassign_conversation(uuid) to authenticated;
