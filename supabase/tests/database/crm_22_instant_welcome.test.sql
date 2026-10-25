-- P3-03: instant welcome -- on a contact's first-ever inbound message,
-- crm.z_welcome_and_create_lead ensures a lead exists (crm._ensure_lead,
-- P3-02) and, only if the org has opted in (messaging.instant_welcome, off
-- by default), sends a language-choice buttons message exactly once.
-- crm.z_apply_language_choice records the contact's reply on
-- crm.contacts.locale and sends a short confirmation.
begin;
\ir _helpers.psql

select plan(15);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_org('owner@test.local', 'Kepler Academy') as org \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');
insert into public.conversations (id, organization_id, organization_address, address, service, name)
values
  ('00000000-0000-0000-0000-0000000000f4', :'org', 'phone-1', '919000000040', 'whatsapp', 'Asha'),
  ('00000000-0000-0000-0000-0000000000f5', :'org', 'phone-1', '919000000041', 'whatsapp', 'Ravi');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values
  (:'org', 'phone-1', 'whatsapp', '919000000040', '{"name": "Asha"}'),
  (:'org', 'phone-1', 'whatsapp', '919000000041', '{"name": "Ravi"}');

select contact_id as asha from crm.contact_addresses
where organization_id = :'org' and address = '919000000040' \gset
select contact_id as ravi from crm.contact_addresses
where organization_id = :'org' and address = '919000000041' \gset

-- Setting is off by default: a lead is created, but no welcome is sent ---------------------

select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
)
values (
  :'org', '00000000-0000-0000-0000-0000000000f4', 'whatsapp', 'phone-1', '919000000040',
  '919000000040',
  '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb,
  'wamid-welcome-asha-1', '2026-10-25T10:00:00Z'
);

select is(
  (select source from crm.leads where organization_id = :'org' and contact_id = :'asha'),
  'organic',
  'a first inbound message creates a lead regardless of the welcome setting'
);
select is(
  (select status from crm.leads where organization_id = :'org' and contact_id = :'asha'),
  'open',
  '...with status open'
);
select is_empty(
  $$ select 1 from public.messages
     where conversation_id = '00000000-0000-0000-0000-0000000000f4'
       and content->>'kind' = 'interactive_buttons' $$,
  'no welcome is sent while messaging.instant_welcome is off (the default)'
);
select is(
  (select welcome_sent_at from crm.contacts where id = :'asha'),
  null,
  'welcome_sent_at stays null when no welcome was sent'
);

-- Turn the setting on for the org -----------------------------------------------------------

select tests.as_user('owner@test.local');
select lives_ok(
  format($$ select crm.set_setting(%L, 'messaging.instant_welcome', 'true'::jsonb) $$, :'org'),
  'the owner turns instant welcome on'
);

-- Ravi's first inbound message: lead created AND the welcome is sent -----------------------

select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
)
values (
  :'org', '00000000-0000-0000-0000-0000000000f5', 'whatsapp', 'phone-1', '919000000041',
  '919000000041',
  '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb,
  'wamid-welcome-ravi-1', '2026-10-25T11:00:00Z'
);

select is(
  (select status from crm.leads where organization_id = :'org' and contact_id = :'ravi'),
  'open',
  'a lead is also created for ravi once the setting is on'
);
select is(
  (select count(*)::int from public.messages
   where conversation_id = '00000000-0000-0000-0000-0000000000f5'
     and content->>'kind' = 'interactive_buttons'),
  1,
  'exactly one welcome buttons message is sent'
);
select results_eq(
  $$ select content->'data'->'buttons'->0->>'id', content->'data'->'buttons'->1->>'id'
     from public.messages
     where conversation_id = '00000000-0000-0000-0000-0000000000f5'
       and content->>'kind' = 'interactive_buttons' $$,
  $$ values ('lang_en'::text, 'lang_hi'::text) $$,
  'the welcome offers the English and Hindi buttons'
);
select is(
  (select welcome_sent_at is not null from crm.contacts where id = :'ravi'),
  true,
  'welcome_sent_at is stamped once the welcome is sent'
);

-- A second inbound message from ravi does not re-send the welcome --------------------------

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
)
values (
  :'org', '00000000-0000-0000-0000-0000000000f5', 'whatsapp', 'phone-1', '919000000041',
  '919000000041',
  '{"version":"1","type":"text","kind":"text","text":"still waiting"}'::jsonb,
  'wamid-welcome-ravi-2', '2026-10-25T11:05:00Z'
);

select is(
  (select count(*)::int from public.messages
   where conversation_id = '00000000-0000-0000-0000-0000000000f5'
     and content->>'kind' = 'interactive_buttons'),
  1,
  'a second inbound message from the same contact does not re-send the welcome'
);

-- Ravi answers the language choice (lang_hi) -----------------------------------------------

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
)
values (
  :'org', '00000000-0000-0000-0000-0000000000f5', 'whatsapp', 'phone-1', '919000000041',
  '919000000041',
  '{"version":"1","type":"data","kind":"interactive","data":{"type":"button_reply","button_reply":{"id":"lang_hi","title":"हिंदी"}}}'::jsonb,
  'wamid-welcome-ravi-3', '2026-10-25T11:10:00Z'
);

select is(
  (select locale from crm.contacts where id = :'ravi'),
  'hi',
  'choosing the Hindi button sets crm.contacts.locale'
);
select is(
  (select count(*)::int from public.messages
   where conversation_id = '00000000-0000-0000-0000-0000000000f5'
     and content->>'kind' = 'text' and sender_address is null),
  1,
  'a confirmation message is sent back'
);

-- A message that is not a recognized language button changes nothing -----------------------

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
)
values (
  :'org', '00000000-0000-0000-0000-0000000000f5', 'whatsapp', 'phone-1', '919000000041',
  '919000000041',
  '{"version":"1","type":"data","kind":"interactive","data":{"type":"button_reply","button_reply":{"id":"some_other_button","title":"Other"}}}'::jsonb,
  'wamid-welcome-ravi-4', '2026-10-25T11:15:00Z'
);

select is(
  (select locale from crm.contacts where id = :'ravi'),
  'hi',
  'an unrelated button reply does not change the already-recorded locale'
);
select is(
  (select count(*)::int from public.messages
   where conversation_id = '00000000-0000-0000-0000-0000000000f5'
     and content->>'kind' = 'text' and sender_address is null),
  1,
  '...nor does it send another confirmation'
);

-- Asha (setting was off when her lead was made) is unaffected by ravi's org-wide setting -----
-- being turned on afterwards -- the welcome only fires on a contact's FIRST inbound message.

select is_empty(
  $$ select 1 from public.messages
     where conversation_id = '00000000-0000-0000-0000-0000000000f4'
       and content->>'kind' = 'interactive_buttons' $$,
  'asha never receives a welcome retroactively once the setting is turned on later'
);

select * from finish();
rollback;
