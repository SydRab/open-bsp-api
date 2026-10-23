-- [crm] P2-05: functions behind the outbound send gate (_shared/send_policy.ts).
-- Internal to the send path -- callers are whatsapp-dispatcher (the pacing
-- and marketing-cap checks) and whatsapp_webhook_processing (consent writes
-- on an inbound STOP), both service-role edge functions. No execute grant
-- to anon/authenticated: see the blanket revoke/grant in 10-40_grants.sql
-- and the privileges migration that must accompany this file's db diff.

-- The latest consent event decides the current status; null means no event
-- was ever recorded (treated as "not opted in" by the caller -- a WABA
-- cannot infer marketing consent from silence).
create function crm.get_consent_status(
  p_organization_id uuid,
  p_organization_address text,
  p_service public.service,
  p_address text
) returns text
language sql
stable
security definer
set search_path to ''
as $$
  select status
  from crm.contacts_consent
  where organization_id = p_organization_id
    and organization_address = p_organization_address
    and service = p_service
    and address = p_address
  order by seq desc
  limit 1;
$$;

create function crm.record_consent_event(
  p_organization_id uuid,
  p_organization_address text,
  p_service public.service,
  p_address text,
  p_status text,
  p_source text,
  p_keyword_matched text default null,
  p_note text default null
) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into crm.contacts_consent (
    organization_id, organization_address, service, address,
    status, source, keyword_matched, note
  ) values (
    p_organization_id, p_organization_address, p_service, p_address,
    p_status, p_source, p_keyword_matched, p_note
  );
end;
$$;

-- Counts MARKETING-category template sends to one contact in the trailing
-- p_period_days, for the marketing.frequency_cap setting. Counts dispatch
-- ATTEMPTS (status.pending/accepted/sent/delivered/read -- anything that
-- reached or is reaching Meta), not just delivered ones: a cap exists to
-- limit how often a contact is bothered, and a message Meta already tried
-- to deliver bothered them regardless of whether it was read.
create function crm.count_recent_marketing_sends(
  p_organization_id uuid,
  p_organization_address text,
  p_conversation_address text,
  p_period_days int
) returns bigint
language sql
stable
security definer
set search_path to ''
as $$
  select count(*)
  from public.messages m
  join crm.templates t
    on t.organization_id = m.organization_id
   and t.organization_address = m.organization_address
   and t.name = m.content->'data'->>'name'
   and t.language = m.content->'data'->'language'->>'code'
  where m.organization_id = p_organization_id
    and m.organization_address = p_organization_address
    and m.conversation_address = p_conversation_address
    and m.sender_address is null
    and t.category = 'MARKETING'
    and m.status ->> 'failed' is null
    and m.timestamp >= now() - (p_period_days || ' days')::interval;
$$;

-- A token bucket per sending number. Refills for the elapsed time since the
-- last check (capped at capacity), then spends p_cost if there is enough --
-- all under one row lock, so concurrent dispatcher invocations for the same
-- number serialize instead of racing the same tokens. Capacity/refill are
-- passed in (not read off the row) so a code-level constant change takes
-- effect on the next call rather than needing a backfill.
create function crm.try_consume_send_token(
  p_organization_id uuid,
  p_service public.service,
  p_organization_address text,
  p_capacity numeric,
  p_refill_per_second numeric,
  p_cost numeric default 1
) returns boolean
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_tokens numeric;
  v_now timestamp with time zone := now();
begin
  insert into crm.send_rate_buckets (
    organization_id, service, organization_address,
    tokens, capacity, refill_per_second, updated_at
  ) values (
    p_organization_id, p_service, p_organization_address,
    p_capacity, p_capacity, p_refill_per_second, v_now
  )
  on conflict (organization_id, service, organization_address) do nothing;

  select least(
    p_capacity,
    b.tokens + extract(epoch from (v_now - b.updated_at)) * p_refill_per_second
  ) into v_tokens
  from crm.send_rate_buckets b
  where b.organization_id = p_organization_id
    and b.service = p_service
    and b.organization_address = p_organization_address
  for update;

  if v_tokens < p_cost then
    update crm.send_rate_buckets
    set tokens = v_tokens, capacity = p_capacity,
      refill_per_second = p_refill_per_second, updated_at = v_now
    where organization_id = p_organization_id
      and service = p_service
      and organization_address = p_organization_address;
    return false;
  end if;

  update crm.send_rate_buckets
  set tokens = v_tokens - p_cost, capacity = p_capacity,
    refill_per_second = p_refill_per_second, updated_at = v_now
  where organization_id = p_organization_id
    and service = p_service
    and organization_address = p_organization_address;

  return true;
end;
$$;
