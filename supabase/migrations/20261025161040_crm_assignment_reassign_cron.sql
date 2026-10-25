-- Hand-written: pg_cron schedules are imperative, db diff cannot model
-- them. P3-05: every 15 minutes, reassign qualified leads whose owner
-- hasn't acted within the org's assignment.reassign_timeout_hours setting
-- (default 24h) -- crm.sweep_lead_reassignment reads that per-org via
-- crm.resolve_setting (not crm.get_setting -- pg_cron carries no
-- request-scoped auth GUC, see crm._pick_assignee's own header note).
select cron.schedule(
  'crm-sweep-lead-reassignment',
  '*/15 * * * *',
  $$ select crm.sweep_lead_reassignment(); $$
);
