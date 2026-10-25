revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.create_lead_stage(uuid, text) to authenticated;
grant execute on function crm.update_lead_stage(uuid, text, int) to authenticated;
grant execute on function crm.delete_lead_stage(uuid) to authenticated;
grant execute on function crm.create_lead_quality(uuid, text) to authenticated;
grant execute on function crm.update_lead_quality(uuid, text, int) to authenticated;
grant execute on function crm.delete_lead_quality(uuid) to authenticated;
grant execute on function crm.create_lead_drop_reason(uuid, text) to authenticated;
grant execute on function crm.update_lead_drop_reason(uuid, text, int) to authenticated;
grant execute on function crm.delete_lead_drop_reason(uuid) to authenticated;
grant execute on function crm.find_or_create_lead(uuid, uuid, text) to authenticated;
grant execute on function crm.set_lead_stage(uuid, uuid) to authenticated;
grant execute on function crm.set_lead_quality(uuid, uuid) to authenticated;
grant execute on function crm.set_lead_status(uuid, text, uuid) to authenticated;
