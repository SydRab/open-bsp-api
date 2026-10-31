-- P4-01: crm.record_import_attestation, a durable record of the CSV
-- import wizard's attestation checkbox (P3-11c), which was previously
-- pure client-side state and never persisted. One audit entry per
-- import run, not per row.
begin;
\ir _helpers.psql

select plan(5);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_org('owner@test.local', 'Attestation Academy') as org \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset

-- Permission gate -----------------------------------------------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.record_import_attestation(%L, 50, 12) $$, :'org'),
  '42501', null, 'a viewer (no contacts.edit) cannot record an import attestation'
);

select tests.as_user('owner@test.local');
select lives_ok(
  format($$ select crm.record_import_attestation(%L, 50, 12) $$, :'org'),
  'an owner (has contacts.edit) can record one'
);

-- It writes exactly one audit entry with the row counts, not one per row -----------------------

select is(
  (select count(*)::int from crm.audit_log
   where organization_id = :'org' and action = 'contacts.import_attested'),
  1,
  'exactly one audit entry for the whole import run'
);
select is(
  (select (details->>'row_count')::int from crm.audit_log
   where organization_id = :'org' and action = 'contacts.import_attested'),
  50,
  '...carrying the row count'
);
select is(
  (select (details->>'marked_opted_in_count')::int from crm.audit_log
   where organization_id = :'org' and action = 'contacts.import_attested'),
  12,
  '...and how many of those rows were marked opted-in'
);

select * from finish();
