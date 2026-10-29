-- Hand-written: pg_cron schedules are imperative, db diff cannot model
-- them. P3-06: every 5 minutes -- tighter than P3-04/P3-05's 15-minute
-- sweeps, since this task's own windows are measured in single-digit/
-- low-double-digit minutes -- check for leads past their first-response
-- SLA and escalate (notify the rep, then managers, then auto-reassign).
select cron.schedule(
  'crm-sweep-speed-to-lead-escalation',
  '*/5 * * * *',
  $$ select crm.sweep_speed_to_lead_escalation(); $$
);
