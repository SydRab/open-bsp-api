-- WhatsApp token health (P2-03). No refresh endpoint exists for Embedded
-- Signup's Business Integration System User tokens -- this only checks and
-- flags, it never rotates anything (see
-- whatsapp-management/token_health.ts). 03:30 UTC, just after the Instagram
-- token refresh at 03:00.
select
  cron.schedule(
    'check-whatsapp-token-health',
    '30 3 * * *',
    $$
    select
      net.http_post(
        url:=(select decrypted_secret from vault.decrypted_secrets where name = 'edge_functions_url') || '/whatsapp-management/check-token-health',
        headers:=jsonb_build_object(
          'content-type', 'application/json',
          'authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'edge_functions_token')
        ),
        body:='{}'::jsonb,
        timeout_milliseconds:=10000
      ) as request_id
  $$
  );
