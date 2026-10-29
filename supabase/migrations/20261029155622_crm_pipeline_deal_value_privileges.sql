-- Privileges for P3-07a's new crm.set_lead_deal_value. db diff never emits
-- grant/revoke statements (see docs/upstream-edits.md / CLAUDE.md). The
-- blanket service_role baseline only covers functions existing when it
-- runs, so it's re-applied here too, same as every phase since P3-02.
-- set_lead_deal_value is member-callable (same deals.edit gate as
-- set_lead_stage/set_lead_quality/set_lead_status), so it also needs the
-- explicit to authenticated grant.
revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.set_lead_deal_value(uuid, numeric) to authenticated;
