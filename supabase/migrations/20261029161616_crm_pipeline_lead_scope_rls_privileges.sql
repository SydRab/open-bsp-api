-- Privileges for P3-07a's lead_scope RLS policy on crm.leads (10-30). db
-- diff never emits grant/revoke statements. The blanket service_role
-- baseline only covers functions existing when it runs, so it's
-- re-applied here too, same as every phase since P3-02.
--
-- crm.resolve_lead_scope and crm.caller_agent are both called directly
-- from the policy's own `using` expression, not from inside another
-- SECURITY DEFINER function -- RLS evaluates `using` as the querying
-- role itself, so that role needs its own EXECUTE grant on anything the
-- policy calls (same reasoning as crm.get_permitted_orgs/has_permission).
revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.resolve_lead_scope(uuid) to anon, authenticated;
grant execute on function crm.caller_agent(uuid) to anon, authenticated;
