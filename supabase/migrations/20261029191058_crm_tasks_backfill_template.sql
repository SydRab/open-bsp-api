-- One-time backfill (P3-07d): existing organizations created before this
-- migration never ran crm.after_insert_on_organizations' new
-- seed_task_reminder_template call, so they'd otherwise have no
-- "internal_task_reminder" template to submit -- same documented
-- exception (DML a schema migration can't express) as P3-02's lead
-- catalog seed and P3-04's qualification scoring seed.
select crm.seed_task_reminder_template(id) from public.organizations;
