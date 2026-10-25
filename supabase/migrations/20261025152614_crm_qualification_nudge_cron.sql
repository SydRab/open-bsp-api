-- Hand-written: pg_cron schedules are imperative, db diff cannot model
-- them. P3-04: every 15 minutes, nudge leads whose pending qualification
-- question has gone unanswered past the org's qualification.question_
-- timeout_hours setting (default 6h) -- crm.sweep_qualification_nudges
-- itself respects each org's qualification.max_nudges budget.
select cron.schedule(
  'crm-sweep-qualification-nudges',
  '*/15 * * * *',
  $$ select crm.sweep_qualification_nudges(); $$
);
