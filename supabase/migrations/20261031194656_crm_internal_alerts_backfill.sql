-- One-time backfill (P3-12): existing organizations created before this
-- migration never ran crm.after_insert_on_organizations' new
-- seed_internal_lead_alert_template call, so they'd otherwise have no
-- "internal_lead_alert" template to submit -- same documented exception
-- (DML a schema migration can't express) as P3-07d's task reminder
-- template backfill.
select crm.seed_internal_lead_alert_template(id) from public.organizations;
