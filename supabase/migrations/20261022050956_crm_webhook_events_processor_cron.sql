-- Hand-written: pg_cron schedules are imperative, db diff cannot model them.
-- P2-01: picks up unprocessed, signature-valid crm.webhook_events rows every
-- minute and fires one async net.http_post per row at whatsapp-webhook-
-- processor — the exact pattern the existing "dispatch-outgoing-pending-
-- messages" job already uses for outbound sends, just inbound.
--
-- Backoff: attempts 0..4 wait 4^attempts minutes since the last attempt
-- (0, 4, 16, 64, 256 minutes) before being retried again; attempts >= 5 are
-- excluded from this query entirely — dead-lettered, visible via
-- `select * from crm.webhook_events where attempts >= 5 and processed_at is
-- null`, until crm.purge_webhook_events eventually clears them out (14 days).
select cron.schedule(
  'process-pending-webhook-events',
  '* * * * *',
  $$
  select
    net.http_post(
      url:=(select decrypted_secret from vault.decrypted_secrets where name = 'edge_functions_url') || '/whatsapp-webhook-processor',
      headers:=jsonb_build_object(
        'content-type', 'application/json',
        'authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'edge_functions_token')
      ),
      body:=jsonb_build_object('id', e.id),
      timeout_milliseconds:=30000
    ) as request_id
  from crm.webhook_events e
  where e.signature_valid
    and e.processed_at is null
    and e.attempts < 5
    and e.received_at >= now() - interval '7 days'
    and (e.last_attempt_at is null or e.last_attempt_at < now() - (power(4, e.attempts) * interval '1 minute'))
  $$
);
