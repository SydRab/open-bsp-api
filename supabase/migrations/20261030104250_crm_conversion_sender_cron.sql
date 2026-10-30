-- Hand-written: pg_cron schedules are imperative, db diff cannot model
-- them. P3-09: picks up unprocessed, under-the-retry-cap crm.outbox_events
-- rows every minute and fires one async net.http_post per row at
-- crm-conversion-sender -- the exact same pattern
-- process-pending-webhook-events (P2-01) already uses, just outbound.
--
-- Backoff: identical formula to crm.webhook_events' own processor --
-- attempts 0..4 wait 4^attempts minutes since the last attempt (0, 4, 16,
-- 64, 256 minutes); attempts >= 5 are excluded entirely (dead-lettered,
-- visible and retryable via the delivery-log UI's "Retry" button, unlike
-- crm.webhook_events which has no UI for this).
select cron.schedule(
  'process-pending-outbox-events',
  '* * * * *',
  $$
  select
    net.http_post(
      url:=(select decrypted_secret from vault.decrypted_secrets where name = 'edge_functions_url') || '/crm-conversion-sender',
      headers:=jsonb_build_object(
        'content-type', 'application/json',
        'authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'edge_functions_token')
      ),
      body:=jsonb_build_object('id', e.id),
      timeout_milliseconds:=30000
    ) as request_id
  from crm.outbox_events e
  where e.processed_at is null
    and e.attempts < 5
    and (e.last_attempt_at is null or e.last_attempt_at < now() - (power(4, e.attempts) * interval '1 minute'))
  $$
);
