-- Privileges for P3-07b's new functions. db diff never emits grant/revoke
-- statements (see docs/upstream-edits.md / CLAUDE.md). The blanket
-- service_role baseline only covers functions existing when it runs, so
-- it's re-applied here too, same as every phase since P3-02.
--
-- crm._set_lead_stage is internal (called only from set_lead_stage and
-- bulk_set_lead_stage, both already security definer), so it only needs
-- the blanket baseline. set_lead_fields, set_stage_required_fields and
-- bulk_set_lead_stage are all member-callable and need the explicit
-- to authenticated grant too.
revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.set_lead_fields(uuid, jsonb) to authenticated;
grant execute on function crm.set_stage_required_fields(uuid, uuid[]) to authenticated;
grant execute on function crm.bulk_set_lead_stage(uuid[], uuid) to authenticated;
