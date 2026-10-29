-- Privileges for P3-07d's new functions. db diff never emits grant/revoke
-- statements. The blanket service_role baseline only covers functions
-- existing when it runs, so it's re-applied here too, same as every
-- phase since P3-02.
--
-- crm._lead_visible_to_caller is called directly from crm.tasks' own RLS
-- policy, not from inside another SECURITY DEFINER function, so it needs
-- its own grant, same reasoning as crm.resolve_lead_scope/caller_agent
-- (P3-07a). seed_task_reminder_template and sweep_task_reminders are
-- system/trigger/cron-only, never called by a member -- the blanket
-- baseline is enough for them.
revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.create_task(uuid, text, timestamp with time zone, uuid) to authenticated;
grant execute on function crm.update_task(uuid, text, timestamp with time zone, uuid) to authenticated;
grant execute on function crm.complete_task(uuid, boolean) to authenticated;
grant execute on function crm.delete_task(uuid) to authenticated;
grant execute on function crm.set_my_whatsapp_address(uuid, text) to authenticated;
grant execute on function crm._lead_visible_to_caller(uuid) to anon, authenticated;
