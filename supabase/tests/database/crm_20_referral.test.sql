-- P3-01: Click-to-WhatsApp referral capture. public.conversations.referral
-- is a simple "latest processed" cache (public.update_conversation_referral);
-- crm.contacts.first_touch_*/last_touch_* is the rigorous, out-of-order-safe
-- attribution (crm.touch_contact_referral), correct regardless of the
-- order webhooks are actually delivered in.
begin;
\ir _helpers.psql

select plan(10);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');
insert into public.conversations (id, organization_id, organization_address, address, service, name)
values ('00000000-0000-0000-0000-0000000000f3', :'org', 'phone-1', '919000000030', 'whatsapp', 'Referral test');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values
  (:'org', 'phone-1', 'whatsapp', '919000000030', '{"name": "Asha"}'),
  (:'org', 'phone-1', 'whatsapp', '919000000031', '{"name": "Ravi"}');

select contact_id as asha from crm.contact_addresses
where organization_id = :'org' and address = '919000000030' \gset
select contact_id as ravi from crm.contact_addresses
where organization_id = :'org' and address = '919000000031' \gset

-- First referral: T2 -----------------------------------------------------------------------

select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
)
values (
  :'org', '00000000-0000-0000-0000-0000000000f3', 'whatsapp', 'phone-1', '919000000030',
  '919000000030',
  '{"version":"1","type":"text","kind":"text","text":"hi","referral":{"source_id":"ad-A","source_type":"ad","source_url":"https://fb.me/a","headline":"Ad A","body":"body A"}}'::jsonb,
  'wamid-referral-a', '2026-10-24T10:00:00Z'
);

select is(
  (select referral->>'source_id' from public.conversations where id = '00000000-0000-0000-0000-0000000000f3'),
  'ad-A',
  'the conversation''s referral cache picks up the first referral'
);
select is(
  (select first_touch_referral->>'source_id' from crm.contacts where id = :'asha'),
  'ad-A',
  'first_touch is set from the first referral-carrying message'
);
select is(
  (select last_touch_referral->>'source_id' from crm.contacts where id = :'asha'),
  'ad-A',
  'last_touch starts out equal to first_touch'
);

-- A later referral (T3 > T2): last_touch moves, first_touch does not -----------------------

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
)
values (
  :'org', '00000000-0000-0000-0000-0000000000f3', 'whatsapp', 'phone-1', '919000000030',
  '919000000030',
  '{"version":"1","type":"text","kind":"text","text":"hi again","referral":{"source_id":"ad-B","source_type":"ad","source_url":"https://fb.me/b","headline":"Ad B","body":"body B"}}'::jsonb,
  'wamid-referral-b', '2026-10-24T12:00:00Z'
);

select is(
  (select referral->>'source_id' from public.conversations where id = '00000000-0000-0000-0000-0000000000f3'),
  'ad-B',
  'the conversation cache moves to the latest-processed referral'
);
select is(
  (select last_touch_referral->>'source_id' from crm.contacts where id = :'asha'),
  'ad-B',
  'last_touch moves forward to the newer referral'
);
select is(
  (select first_touch_referral->>'source_id' from crm.contacts where id = :'asha'),
  'ad-A',
  'first_touch is untouched by a later referral'
);

-- An EARLIER referral arriving out of order (T1 < T2): first_touch moves BACKWARDS, ----------
-- last_touch (already at T3) is unaffected.

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
)
values (
  :'org', '00000000-0000-0000-0000-0000000000f3', 'whatsapp', 'phone-1', '919000000030',
  '919000000030',
  '{"version":"1","type":"text","kind":"text","text":"out of order","referral":{"source_id":"ad-C","source_type":"ad","source_url":"https://fb.me/c","headline":"Ad C","body":"body C"}}'::jsonb,
  'wamid-referral-c', '2026-10-24T08:00:00Z'
);

select is(
  (select first_touch_referral->>'source_id' from crm.contacts where id = :'asha'),
  'ad-C',
  'a chronologically earlier referral, even if delivered last, corrects first_touch'
);
select is(
  (select last_touch_referral->>'source_id' from crm.contacts where id = :'asha'),
  'ad-B',
  '...but does not disturb last_touch, which is still the chronologically latest one'
);

-- A message with no referral does not touch anything (the trigger's own WHEN clause) -------

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
)
values (
  :'org', '00000000-0000-0000-0000-0000000000f3', 'whatsapp', 'phone-1', '919000000030',
  '919000000030',
  '{"version":"1","type":"text","kind":"text","text":"plain message"}'::jsonb,
  'wamid-plain', '2026-10-24T13:00:00Z'
);

select is(
  (select referral->>'source_id' from public.conversations where id = '00000000-0000-0000-0000-0000000000f3'),
  'ad-C',
  'a plain message with no referral leaves the conversation cache alone (it was already at ad-C -- that cache has no out-of-order guard, unlike crm.contacts'' touch columns)'
);

-- Isolation: Ravi's own touch data is independent of Asha's --------------------------------

select is_empty(
  format($$ select 1 from crm.contacts where id = %L and first_touch_referral is not null $$, :'ravi'),
  'a contact who never had a referral-carrying message has no touch data at all'
);

select * from finish();
rollback;
