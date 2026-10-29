-- Privileges for P3-06's new functions. db diff never emits grant/revoke
-- statements (see docs/upstream-edits.md / CLAUDE.md). The engine itself
-- (crm.z_set_response_deadline, crm.z_record_first_response, crm.
-- sweep_speed_to_lead_escalation and the internal functions they call)
-- is trigger/system-only, never called via RPC, so it only needs the
-- blanket service_role baseline re-applied -- that statement only covers
-- functions that exist when it runs, not future ones (the established
-- gotcha, re-confirmed every phase since P3-02). Only marking a
-- notification read is member-callable.
revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.mark_notification_read(uuid) to authenticated;
grant execute on function crm.mark_all_notifications_read(uuid) to authenticated;
