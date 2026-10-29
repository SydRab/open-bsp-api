-- Hand-written: pg_cron schedules are imperative, db diff cannot model
-- them. P3-07d: every 15 minutes -- task due times are set by a human in
-- whole-minute increments, not the single-digit-minute urgency P3-06's
-- SLA sweep needs, so P3-04/P3-05's cadence fits better here.
select cron.schedule(
  'crm-sweep-task-reminders',
  '*/15 * * * *',
  $$ select crm.sweep_task_reminders(); $$
);
