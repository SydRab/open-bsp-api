-- Privileges for P3-07e's new functions. db diff never emits grant/revoke
-- statements. The blanket service_role baseline only covers functions
-- existing when it runs, so it's re-applied here too, same as every
-- phase since P3-02.
revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.create_lead_note(uuid, text) to authenticated;
grant execute on function crm.update_lead_note(uuid, text) to authenticated;
grant execute on function crm.delete_lead_note(uuid) to authenticated;
