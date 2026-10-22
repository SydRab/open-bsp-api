-- Hand-written: pg_cron schedules are imperative, db diff cannot model them.
-- P2-01: short retention for raw webhook payloads (14 days, crm.purge_
-- webhook_events) — see that function's own comment for why.
select cron.schedule(
  'crm-purge-webhook-events',
  '15 21 * * *', -- 21:15 UTC, ahead of the 21:30 organization purge
  $$ select crm.purge_webhook_events(); $$
);
