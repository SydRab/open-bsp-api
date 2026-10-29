-- Privileges for P3-07c's crm.get_lead_history. db diff never emits
-- grant/revoke statements. The blanket service_role baseline only covers
-- functions existing when it runs, so it's re-applied here too, same as
-- every phase since P3-02. Member-callable, so it also needs the
-- explicit to authenticated grant.
revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.get_lead_history(uuid) to authenticated;
