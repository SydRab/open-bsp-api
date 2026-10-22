-- Webhook hardening (P2-01). Every inbound webhook is logged here BEFORE any
-- processing — signature-checked or not, so even rejected/malformed
-- deliveries stay visible for debugging — then acknowledged immediately.
-- whatsapp-webhook-processor (invoked by pg_cron, same pattern as the
-- existing whatsapp-dispatcher) does the actual work asynchronously, so a
-- slow media download can no longer risk Meta's own delivery timeout on the
-- webhook request itself.
--
-- dedupe_key: Meta sends no per-delivery id, but does resend byte-identical
-- payloads on retry/timeout, so a hash of the raw body is the correct
-- idempotency key — the webhook handler computes it with sha256(raw body).
--
-- No organization_id: a single payload can span several tenants' phone
-- numbers at once (one Meta webhook call batches all of an app's WABAs), so
-- which org(s) it touches is resolved during processing, not at ingest. This
-- is platform infrastructure, not tenant data, like crm.platform_audit_log —
-- RLS is service-role only (10-30), no tenant/anon/authenticated policy.
create table crm.webhook_events (
  id uuid default gen_random_uuid() not null,
  service public.service not null,
  dedupe_key text not null,
  raw_body text not null,
  signature_valid boolean not null,
  received_at timestamp with time zone default now() not null,
  processed_at timestamp with time zone,
  processing_error text,
  attempts int default 0 not null,
  last_attempt_at timestamp with time zone,
  created_at timestamp with time zone default now() not null
);

alter table only crm.webhook_events
add constraint webhook_events_pkey primary key (id);

alter table only crm.webhook_events
add constraint webhook_events_service_dedupe_key_key
unique (service, dedupe_key);

-- What the processor's cron job selects every run: valid, unprocessed,
-- under the retry cap.
create index webhook_events_pending_idx on crm.webhook_events (service, received_at)
where signature_valid and processed_at is null;

-- Short retention: this table exists for dedupe, replay, and debugging a
-- processing failure, not as a second long-lived copy of chat content
-- alongside public.messages. 14 days is a generous debugging window;
-- anything neither processed nor manually replayed by then is gone, success
-- or dead-lettered alike.
create function crm.purge_webhook_events() returns void
language sql
security definer
set search_path to ''
as $$
  delete from crm.webhook_events where received_at < now() - interval '14 days';
$$;

-- Atomic claim for whatsapp-webhook-processor: bumps the retry counter and
-- returns the row in one statement, so two cron ticks racing on the same
-- event can't both process it — the loser's UPDATE matches zero rows once
-- the winner's has committed, both gated on processed_at is null.
create function crm.claim_webhook_event(p_id uuid)
returns table (raw_body text, attempts int)
language sql
security definer
set search_path to ''
as $$
  update crm.webhook_events
  set attempts = webhook_events.attempts + 1, last_attempt_at = now()
  where id = p_id and processed_at is null
  returning webhook_events.raw_body, webhook_events.attempts;
$$;

-- The replay tool: clears a row's processed/attempt state so the next cron
-- tick (within a minute) picks it up through the ordinary claim/process
-- path again, rather than a separate direct-invoke code path. Service-role
-- only — there is no tenant or admin-console UI for this yet, deliberately
-- (P2-01's scope is the mechanism; a console action is a cheap follow-up).
create function crm.replay_webhook_event(p_id uuid) returns void
language sql
security definer
set search_path to ''
as $$
  update crm.webhook_events
  set processed_at = null, attempts = 0, processing_error = null, last_attempt_at = null
  where id = p_id;
$$;
