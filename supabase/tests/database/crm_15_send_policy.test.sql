-- P2-05: outbound sender compliance -- crm.contacts_consent (opt-in/opt-out
-- event log), crm.send_rate_buckets (per-number token bucket), and the
-- functions the send gate (_shared/send_policy.ts) calls against both.
begin;
\ir _helpers.psql

select plan(19);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('other.owner@test.local') as other_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');

-- Who can read: contacts_consent ---------------------------------------------------------

select tests.as_service();
select crm.record_consent_event(:'org', 'phone-1', 'whatsapp', '919000000001', 'opted_in', 'admin')
  as consent_noop \gset

select tests.as_user('owner@test.local');
select isnt_empty(
  format($$ select 1 from crm.contacts_consent where organization_id = %L $$, :'org'),
  'a member of the org can read its consent events'
);

select tests.as_user('other.owner@test.local');
select is_empty(
  format($$ select 1 from crm.contacts_consent where organization_id = %L $$, :'org'),
  'another organization cannot'
);

-- Writes are service-role only: contacts_consent ----------------------------------------

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.record_consent_event(%L, 'phone-1', 'whatsapp', '919000000002', 'opted_in', 'admin') $$, :'org'),
  '42501', null, 'a tenant owner cannot call record_consent_event directly (no execute grant)'
);
select throws_ok(
  format($$ insert into crm.contacts_consent (organization_id, organization_address, service, address, status, source)
             values (%L, 'phone-1', 'whatsapp', '919000000002', 'opted_in', 'admin') $$, :'org'),
  '42501', null, 'nor insert a row directly'
);

-- get_consent_status: latest row wins -----------------------------------------------------

select tests.as_service();
select is(
  crm.get_consent_status(:'org', 'phone-1', 'whatsapp', '919000000001'),
  'opted_in',
  'get_consent_status reads the one event recorded so far'
);
select is(
  crm.get_consent_status(:'org', 'phone-1', 'whatsapp', '919000000099'),
  null,
  'a contact with no event has no status -- silence is never consent'
);

select crm.record_consent_event(:'org', 'phone-1', 'whatsapp', '919000000001', 'opted_out', 'keyword', 'STOP');
select is(
  crm.get_consent_status(:'org', 'phone-1', 'whatsapp', '919000000001'),
  'opted_out',
  'a later event (the STOP reply) overrides the earlier opt-in, not replaces it in place'
);
select is(
  (select count(*)::int from crm.contacts_consent where organization_id = :'org' and address = '919000000001'),
  2,
  'both events are still on the log -- append-only, for the audit trail CLAUDE.md requires'
);

-- Check constraints ------------------------------------------------------------------------

select throws_ok(
  format($$ select crm.record_consent_event(%L, 'phone-1', 'whatsapp', '919000000003', 'maybe', 'admin') $$, :'org'),
  '23514', null, 'status must be opted_in or opted_out'
);
select throws_ok(
  format($$ select crm.record_consent_event(%L, 'phone-1', 'whatsapp', '919000000003', 'opted_in', 'because_i_felt_like_it') $$, :'org'),
  '23514', null, 'source must be one of the recognized values'
);

-- Who can read: send_rate_buckets --------------------------------------------------------

select crm.try_consume_send_token(:'org', 'whatsapp', 'phone-1', 5, 1);

select tests.as_user('owner@test.local');
select isnt_empty(
  format($$ select 1 from crm.send_rate_buckets where organization_id = %L $$, :'org'),
  'a member of the org can read its send rate bucket'
);

select tests.as_user('other.owner@test.local');
select is_empty(
  format($$ select 1 from crm.send_rate_buckets where organization_id = %L $$, :'org'),
  'another organization cannot'
);

-- Writes are service-role only: send_rate_buckets ----------------------------------------

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.try_consume_send_token(%L, 'whatsapp', 'phone-1', 5, 1) $$, :'org'),
  '42501', null, 'a tenant owner cannot call try_consume_send_token directly'
);

-- Token bucket: consume, exhaust, refill ---------------------------------------------------

select tests.as_service();
select is(
  crm.try_consume_send_token(:'org', 'whatsapp', 'phone-2', 2, 1),
  true,
  'a fresh bucket (capacity 2) starts full: the first send is never held for pacing'
);
select is(
  crm.try_consume_send_token(:'org', 'whatsapp', 'phone-2', 2, 1),
  true,
  'second token still available'
);
select is(
  crm.try_consume_send_token(:'org', 'whatsapp', 'phone-2', 2, 1),
  false,
  'third call with no elapsed time finds the bucket empty'
);

-- Simulate elapsed time by backdating updated_at, rather than a real sleep.
update crm.send_rate_buckets
set updated_at = now() - interval '10 seconds'
where organization_id = :'org' and service = 'whatsapp' and organization_address = 'phone-2';

select is(
  crm.try_consume_send_token(:'org', 'whatsapp', 'phone-2', 2, 1),
  true,
  'after 10s at 1 token/sec the bucket refilled (capped at capacity 2) and allows a send again'
);

-- count_recent_marketing_sends -------------------------------------------------------------

insert into crm.templates (organization_id, organization_address, meta_id, name, category, language, status, components)
values (:'org', 'phone-1', 'meta-tpl-cap', 'promo_blast', 'MARKETING', 'en', 'APPROVED', '[]'::jsonb);

insert into public.conversations (id, organization_id, organization_address, address, service, name)
values ('00000000-0000-0000-0000-0000000000d1', :'org', 'phone-1', '919000000005', 'whatsapp', 'Cap test');

insert into public.messages (organization_id, conversation_id, service, organization_address, conversation_address, content)
values (
  :'org', '00000000-0000-0000-0000-0000000000d1', 'whatsapp', 'phone-1', '919000000005',
  '{"version":"1","type":"data","kind":"template","data":{"name":"promo_blast","language":{"code":"en","policy":"deterministic"}}}'::jsonb
);

select is(
  crm.count_recent_marketing_sends(:'org', 'phone-1', '919000000005', 7),
  1::bigint,
  'one MARKETING template send to this contact counts toward the cap'
);
select is(
  crm.count_recent_marketing_sends(:'org', 'phone-1', '919000000006', 7),
  0::bigint,
  'a different contact has none'
);

select * from finish();
rollback;
