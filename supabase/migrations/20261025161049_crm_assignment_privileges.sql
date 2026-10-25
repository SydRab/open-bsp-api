-- Privileges for P3-05's new functions. db diff never emits grant/revoke
-- statements (see docs/upstream-edits.md / CLAUDE.md). The engine itself
-- (crm.z_assign_on_qualified, crm.sweep_lead_reassignment and the
-- internal functions they call) is trigger/system-only, never called via
-- RPC, so it only needs the blanket service_role baseline re-applied --
-- that statement only covers functions that exist when it runs, not
-- future ones (the established gotcha, re-confirmed every phase since
-- P3-02). Rule CRUD and manual assign/unassign are member-callable.
revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.set_assignment_rule(uuid, uuid, text, text, text, int) to authenticated;
grant execute on function crm.update_assignment_rule(uuid, uuid, text, text, text, int, boolean) to authenticated;
grant execute on function crm.delete_assignment_rule(uuid) to authenticated;
grant execute on function crm.assign_lead(uuid, uuid) to authenticated;
grant execute on function crm.unassign_lead(uuid) to authenticated;
