-- One-time backfill (P3-09): existing organizations created before this
-- migration never ran crm.after_insert_on_organizations' new
-- seed_default_event_mapping call, so they'd otherwise have no default
-- "qualified -> Lead" mapping -- same documented exception (DML a schema
-- migration can't express) as P3-07d's task-reminder-template backfill
-- and P3-08's trial-reminder-template backfill.
select crm.seed_default_event_mapping(id) from public.organizations;
