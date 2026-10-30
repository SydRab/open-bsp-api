-- Hand-written: pg_cron schedules are imperative, db diff cannot model
-- them. P3-08: every 15 minutes, same cadence (and same reasoning) as
-- crm.sweep_task_reminders -- trial slot times are set in whole-minute
-- increments, not single-digit-minute urgency.
select cron.schedule(
  'crm-sweep-trial-reminders',
  '*/15 * * * *',
  $$ select crm.sweep_trial_reminders(); $$
);
