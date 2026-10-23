-- WhatsApp number quality (P2-10). No webhook exists for quality_rating --
-- this polls Meta's phone number GET endpoint daily (see
-- whatsapp-management/number_health.ts). 03:40 UTC, just after the token
-- health check at 03:30.
select
  cron.schedule(
    'check-whatsapp-number-quality',
    '40 3 * * *',
    $$
    select
      net.http_post(
        url:=(select decrypted_secret from vault.decrypted_secrets where name = 'edge_functions_url') || '/whatsapp-management/check-number-quality',
        headers:=jsonb_build_object(
          'content-type', 'application/json',
          'authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'edge_functions_token')
        ),
        body:='{}'::jsonb,
        timeout_milliseconds:=10000
      ) as request_id
  $$
  );
