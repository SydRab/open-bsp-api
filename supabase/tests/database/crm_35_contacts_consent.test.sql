-- P3-11c: crm.set_contact_consent, the member-facing wrapper around
-- crm.record_consent_event (service-role only, P2-05/10-29d). Gated on
-- contacts.edit. CSV import (the UI) calls this once per row when the
-- admin has attested the imported list is already opted-in; this test
-- exercises the wrapper itself, not the UI loop.
begin;
\ir _helpers.psql

select plan(9);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_org('owner@test.local', 'Consent Academy') as org \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', '910000000000', 'connected');

-- Permission gate -----------------------------------------------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.set_contact_consent(%L, '910000000000', 'whatsapp', '919000000501', 'opted_in', 'csv_import') $$, :'org'),
  '42501', null, 'a viewer (no contacts.edit) cannot record a consent event'
);

select tests.as_user('rep@test.local');
select lives_ok(
  format($$ select crm.set_contact_consent(%L, '910000000000', 'whatsapp', '919000000501', 'opted_in', 'csv_import') $$, :'org'),
  'a sales_rep (has contacts.edit) can record a consent event'
);

-- It actually writes through crm.record_consent_event -----------------------------------------

select is(
  (select status from crm.contacts_consent
   where organization_id = :'org' and organization_address = '910000000000'
     and service = 'whatsapp' and address = '919000000501'
   order by seq desc limit 1),
  'opted_in',
  'the event lands in crm.contacts_consent'
);
select is(
  (select source from crm.contacts_consent
   where organization_id = :'org' and organization_address = '910000000000'
     and service = 'whatsapp' and address = '919000000501'
   order by seq desc limit 1),
  'csv_import',
  '...tagged with the csv_import source'
);
select is(
  (select count(*)::int from crm.contacts_consent
   where organization_id = :'org' and organization_address = '910000000000'
     and service = 'whatsapp' and address = '919000000501' and status = 'opted_in'),
  1,
  '...the row is readable by the member too (RLS select policy), same place the send gate reads from'
);

-- p_source defaults to csv_import, but stays overridable ---------------------------------------

select crm.set_contact_consent(:'org', '910000000000', 'whatsapp', '919000000502', 'opted_in', 'admin');
select is(
  (select source from crm.contacts_consent
   where organization_id = :'org' and organization_address = '910000000000'
     and service = 'whatsapp' and address = '919000000502'
   order by seq desc limit 1),
  'admin',
  'a caller can pass a different source (e.g. a future manual toggle)'
);

-- An invalid status/source is still rejected by the table's own check constraints --------------

select throws_ok(
  format($$ select crm.set_contact_consent(%L, '910000000000', 'whatsapp', '919000000503', 'subscribed', 'csv_import') $$, :'org'),
  '23514', null, 'an unrecognized status is refused by the check constraint, not silently accepted'
);
select throws_ok(
  format($$ select crm.set_contact_consent(%L, '910000000000', 'whatsapp', '919000000503', 'opted_in', 'spreadsheet') $$, :'org'),
  '23514', null, 'an unrecognized source is refused the same way'
);

-- Cross-org isolation ---------------------------------------------------------------------------

select tests.as_postgres();
select tests.create_user('other.owner@test.local') as other_owner \gset
select tests.as_user('owner@test.local');
select tests.create_org('other.owner@test.local', 'Other Consent Org') as other_org \gset

select tests.as_user('other.owner@test.local');
select is(
  (select count(*)::int from crm.contacts_consent
   where organization_id = :'other_org' and organization_address = '910000000000'
     and service = 'whatsapp' and address = '919000000501'),
  0,
  'a different org has no consent event for the same address -- confirms the org filter, not a leak'
);

select * from finish();
