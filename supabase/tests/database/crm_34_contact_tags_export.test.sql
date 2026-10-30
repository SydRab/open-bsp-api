-- P3-11b: contact tags (crm.set_contact_tag, gated contacts.edit -- a
-- different bar than crm.set_conversation_tag's conversations.view,
-- deliberately, since this touches a contact's own metadata) and CSV
-- export (crm.export_contacts, gated contacts.export -- another
-- permission that sat unused in the catalog since P1-02, same discovery
-- as P3-10a's reports.view). The two permissions are deliberately
-- asymmetric: sales_rep can tag but not export.
begin;
\ir _helpers.psql

select plan(17);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_user('manager@test.local') as manager_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_org('owner@test.local', 'Tags Academy') as org \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'manager@test.local', 'sales_manager') as manager_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', '910000000000', 'connected');
insert into public.conversations (id, organization_id, organization_address, address, service, name)
values ('00000000-0000-0000-0000-00000000e001', :'org', '910000000000', '919000000401', 'whatsapp', 'Tagged');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values
  (:'org', '910000000000', 'whatsapp', '919000000401', '{"name": "Tagged"}'),
  (:'org', '910000000000', 'whatsapp', '919000000402', '{"name": "Untagged"}');
select contact_id as c_tagged from crm.contact_addresses where organization_id = :'org' and address = '919000000401' \gset
select contact_id as c_untagged from crm.contact_addresses where organization_id = :'org' and address = '919000000402' \gset

select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-00000000e001', 'whatsapp', '910000000000', '919000000401',
  '919000000401', '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb,
  'ext-tag-1', now()
);

select tests.as_user('owner@test.local');
select id as stage_id from crm.lead_stages where organization_id = :'org' limit 1 \gset
select id as lead_tagged from crm.leads where contact_id = :'c_tagged' \gset
select crm.set_lead_stage(:'lead_tagged', :'stage_id');
select crm.set_lead_deal_value(:'lead_tagged', 5000);

select tests.as_postgres();
select crm.record_consent_event(:'org', '910000000000', 'whatsapp', '919000000401', 'opted_in', 'admin');

select tests.as_user('owner@test.local');
select crm.create_tag(:'org', 'VIP') as tag_vip \gset

-- set_contact_tag: permission gate ----------------------------------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.set_contact_tag(%L, %L, true) $$, :'c_tagged', :'tag_vip'),
  '42501', null, 'a viewer (no contacts.edit) cannot tag a contact'
);

select tests.as_user('rep@test.local');
select lives_ok(
  format($$ select crm.set_contact_tag(%L, %L, true) $$, :'c_tagged', :'tag_vip'),
  'a sales_rep (has contacts.edit) can tag a contact'
);
select isnt_empty(
  format($$ select 1 from crm.contact_tags where contact_id = %L and tag_id = %L $$, :'c_tagged', :'tag_vip'),
  '...and the row exists'
);

select lives_ok(
  format($$ select crm.set_contact_tag(%L, %L, true) $$, :'c_tagged', :'tag_vip'),
  're-tagging the same contact with the same tag is idempotent, not an error'
);
select is(
  (select count(*)::int from crm.contact_tags where contact_id = :'c_tagged' and tag_id = :'tag_vip'),
  1,
  '...still exactly one row'
);

select throws_ok(
  format($$ select crm.set_contact_tag(%L, %L, true) $$, :'c_tagged', '00000000-0000-0000-0000-000000000000'),
  '22023', 'tag not found', 'tagging with an unknown tag id is refused'
);

select crm.set_contact_tag(:'c_tagged', :'tag_vip', false);
select is_empty(
  format($$ select 1 from crm.contact_tags where contact_id = %L and tag_id = %L $$, :'c_tagged', :'tag_vip'),
  'untagging removes the row'
);
select lives_ok(
  format($$ select crm.set_contact_tag(%L, %L, false) $$, :'c_tagged', :'tag_vip'),
  'untagging an already-untagged contact is idempotent, not an error'
);

-- Re-apply for the export test below --------------------------------------------------------------
select crm.set_contact_tag(:'c_tagged', :'tag_vip', true);

-- export_contacts: permission gate -----------------------------------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.export_contacts(%L) $$, :'org'),
  '42501', null, 'a viewer (no contacts.export) cannot export'
);

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.export_contacts(%L) $$, :'org'),
  '42501', null, 'a sales_rep (has contacts.edit but not contacts.export) cannot export either -- the two are deliberately asymmetric'
);

-- export_contacts: content ------------------------------------------------------------------------

select tests.as_user('manager@test.local');
select is(
  (select consent_status from crm.export_contacts(:'org') where contact_id = :'c_tagged'),
  'opted_in',
  'the tagged contact''s recorded consent event shows up in the export'
);
select is(
  (select tags from crm.export_contacts(:'org') where contact_id = :'c_tagged'),
  'VIP',
  '...and its tag name'
);
select is(
  (select lead_status from crm.export_contacts(:'org') where contact_id = :'c_tagged'),
  'open',
  '...and its lead''s status (set_lead_stage does not touch status, P3-02)'
);
select is(
  (select deal_value from crm.export_contacts(:'org') where contact_id = :'c_tagged'),
  5000::numeric,
  '...and its lead''s deal value'
);
select is(
  (select consent_status from crm.export_contacts(:'org') where contact_id = :'c_untagged'),
  null,
  'a contact with no recorded consent event, no lead, and no tag exports with every one of those columns null'
);
select is(
  (select lead_status from crm.export_contacts(:'org') where contact_id = :'c_untagged'),
  null,
  '...lead_status null'
);

-- Cross-org isolation -----------------------------------------------------------------------------

select tests.as_postgres();
select tests.create_user('other.owner@test.local') as other_owner \gset
select tests.as_user('owner@test.local');
select tests.create_org('other.owner@test.local', 'Other Tags Org') as other_org \gset

select tests.as_user('other.owner@test.local');
select is(
  (select count(*)::int from crm.export_contacts(:'other_org')),
  0,
  'a different (empty) org exports zero rows -- confirms the org filter, not a leak'
);

select * from finish();
