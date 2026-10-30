-- P3-11d: crm.merge_contacts, gated contacts.edit (same bar as contact
-- tags/fields). Addresses/tags move to the primary, fields merge with
-- the primary winning on conflict, (first|last)_touch stay paired with
-- their own timestamp. A lead on both sides refuses the merge; a lead on
-- one side follows it to the primary.
begin;
\ir _helpers.psql

select plan(12);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_org('owner@test.local', 'Merge Academy') as org \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', '910000000000', 'connected');

insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values
  (:'org', '910000000000', 'whatsapp', '919000000601', '{"name": "Primary"}'),
  (:'org', '910000000000', 'whatsapp', '919000000602', null);
select contact_id as c_primary from crm.contact_addresses where organization_id = :'org' and address = '919000000601' \gset
select contact_id as c_secondary from crm.contact_addresses where organization_id = :'org' and address = '919000000602' \gset

select tests.as_user('owner@test.local');
select crm.create_tag(:'org', 'VIP') as tag_vip \gset
select crm.set_contact_tag(:'c_secondary', :'tag_vip', true);
select crm.create_custom_field(:'org', 'contact', 'nickname', 'text', '{"en": "Nickname"}') as nickname_field \gset
select crm.set_contact_fields(:'c_secondary', '{"nickname": "Sec"}'::jsonb);

-- Permission gate ----------------------------------------------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.merge_contacts(%L, %L) $$, :'c_primary', :'c_secondary'),
  '42501', null, 'a viewer (no contacts.edit) cannot merge contacts'
);

-- Guard clauses --------------------------------------------------------------------------------

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.merge_contacts(%L, %L) $$, :'c_primary', :'c_primary'),
  '22023', 'cannot merge a contact with itself', 'merging a contact with itself is refused'
);
select throws_ok(
  format($$ select crm.merge_contacts(%L, '00000000-0000-0000-0000-000000000000') $$, :'c_primary'),
  'P0002', null, 'merging with an unknown contact is refused'
);

-- The actual merge ------------------------------------------------------------------------------

select lives_ok(
  format($$ select crm.merge_contacts(%L, %L) $$, :'c_primary', :'c_secondary'),
  'a sales_rep (has contacts.edit) can merge two contacts with no lead conflict'
);
select is(
  (select count(*)::int from crm.contacts where id = :'c_secondary'),
  0,
  'the secondary contact row is gone'
);
select is(
  (select count(*)::int from crm.contact_addresses where organization_id = :'org' and contact_id = :'c_primary'),
  2,
  'both addresses now point at the primary'
);
select is(
  (select count(*)::int from crm.contact_tags where contact_id = :'c_primary' and tag_id = :'tag_vip'),
  1,
  'the secondary''s tag moved to the primary'
);
select is(
  (select custom_fields->>'nickname' from crm.contacts where id = :'c_primary'),
  'Sec',
  'the secondary''s field value filled a gap the primary did not have'
);
select is(
  (select display_name from crm.contacts where id = :'c_primary'),
  'Primary',
  'the primary''s own display_name is kept, not overwritten by the (absent) secondary one'
);

-- Both sides having a lead refuses the merge ----------------------------------------------------

select tests.as_postgres();
insert into public.contacts_addresses (organization_id, organization_address, service, address)
values
  (:'org', '910000000000', 'whatsapp', '919000000603'),
  (:'org', '910000000000', 'whatsapp', '919000000604');
select contact_id as c_lead_a from crm.contact_addresses where organization_id = :'org' and address = '919000000603' \gset
select contact_id as c_lead_b from crm.contact_addresses where organization_id = :'org' and address = '919000000604' \gset

select tests.as_user('owner@test.local');
select crm.find_or_create_lead(:'org', :'c_lead_a', 'organic');
select crm.find_or_create_lead(:'org', :'c_lead_b', 'organic');

select throws_ok(
  format($$ select crm.merge_contacts(%L, %L) $$, :'c_lead_a', :'c_lead_b'),
  '55000', null,
  'both contacts already having their own lead refuses the merge'
);

-- A lead on only one side follows it to the primary ----------------------------------------------

select tests.as_postgres();
insert into public.contacts_addresses (organization_id, organization_address, service, address)
values (:'org', '910000000000', 'whatsapp', '919000000605');
select contact_id as c_no_lead from crm.contact_addresses where organization_id = :'org' and address = '919000000605' \gset

select tests.as_user('owner@test.local');
select crm.merge_contacts(:'c_no_lead', :'c_lead_a');
select is(
  (select contact_id from crm.leads where contact_id = :'c_no_lead'),
  :'c_no_lead',
  'the one existing lead followed its contact to the primary'
);

-- Cross-org isolation -----------------------------------------------------------------------------

select tests.as_postgres();
select tests.create_user('other.owner@test.local') as other_owner \gset
select tests.as_user('owner@test.local');
select tests.create_org('other.owner@test.local', 'Other Merge Org') as other_org \gset
select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'other_org', 'whatsapp', '920000000000', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address)
values (:'other_org', '920000000000', 'whatsapp', '929000000001');
select contact_id as c_other from crm.contact_addresses where organization_id = :'other_org' and address = '929000000001' \gset

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.merge_contacts(%L, %L) $$, :'c_no_lead', :'c_other'),
  '22023', 'contacts belong to different organizations',
  'merging across organizations is refused'
);

select * from finish();
