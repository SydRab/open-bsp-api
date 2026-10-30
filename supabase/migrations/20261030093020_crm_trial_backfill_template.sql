-- One-time backfill (P3-08): existing organizations created before this
-- migration never ran crm.after_insert_on_organizations' new
-- seed_trial_reminder_template call, so they'd otherwise have no
-- "trial_class_reminder" template to submit -- same documented exception
-- (DML a schema migration can't express) as P3-07d's task-reminder
-- backfill.
select crm.seed_trial_reminder_template(id) from public.organizations;
