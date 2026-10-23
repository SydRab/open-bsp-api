-- [crm] P2-05: outbound sender compliance -- opt-in/opt-out consent and
-- per-number send pacing. Both are read/written only by the send path
-- (whatsapp-dispatcher's pre-send gate, _shared/send_policy.ts) and the
-- inbound STOP/unsubscribe handler (_shared/whatsapp_webhook_processing.ts);
-- no member-facing UI exists yet (that's P2-08/P2-09's job), so there is no
-- write policy for either table below -- service-role only.

-- An append-only event log, not a single mutable flag: CLAUDE.md requires
-- "STOP/unsubscribe honored instantly" and "support export and erasure" for
-- PII, both of which need to know WHEN and WHY consent changed, not just
-- its current value. The current status for (organization_id,
-- organization_address, service, address) is its most recent row by
-- created_at -- see crm.get_consent_status.
create table crm.contacts_consent (
  id uuid default gen_random_uuid() not null,
  -- The tiebreaker for "latest event wins" (crm.get_consent_status). Not
  -- created_at: now() is frozen for an entire transaction in Postgres, so
  -- two events recorded in the same transaction -- a real possibility, not
  -- just a test artifact -- would otherwise tie, making "latest" undefined.
  -- A monotonic identity column has no such collision.
  seq bigint generated always as identity,
  organization_id uuid not null,
  organization_address text not null,
  service public.service not null,
  address text not null,
  status text not null,
  source text not null,
  keyword_matched text,
  note text,
  created_at timestamp with time zone default now() not null
);

alter table only crm.contacts_consent
add constraint contacts_consent_pkey primary key (id);

alter table only crm.contacts_consent
add constraint contacts_consent_organization_id_fkey
foreign key (organization_id)
references public.organizations(id)
on delete cascade;

alter table only crm.contacts_consent
add constraint contacts_consent_status_check
check (status in ('opted_in', 'opted_out'));

alter table only crm.contacts_consent
add constraint contacts_consent_source_check
check (source in ('keyword', 'admin', 'signup_default', 'api'));

-- Serves crm.get_consent_status's "latest row" lookup directly off the index
-- (no extra sort step): leads with the identity, trails with seq desc.
create index contacts_consent_lookup_idx
on crm.contacts_consent (organization_id, organization_address, service, address, seq desc);

-- One row per sending number, holding a classic token bucket: capacity and
-- refill_per_second are per-row (not hardcoded) so a future setting could
-- tune them per tenant/number without a schema change, even though nothing
-- writes a non-default value today. Starts full (tokens = capacity) so the
-- first send after a number connects is never held for pacing.
create table crm.send_rate_buckets (
  organization_id uuid not null,
  service public.service not null,
  organization_address text not null,
  tokens numeric not null,
  capacity numeric not null,
  refill_per_second numeric not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.send_rate_buckets
add constraint send_rate_buckets_pkey
primary key (organization_id, service, organization_address);

alter table only crm.send_rate_buckets
add constraint send_rate_buckets_organization_id_fkey
foreign key (organization_id)
references public.organizations(id)
on delete cascade;
