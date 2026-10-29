-- P3-07b: deal-entity custom field values on crm.leads
-- (crm.set_lead_fields), required-field-per-stage rules
-- (crm.lead_stage_required_fields / crm.set_stage_required_fields,
-- enforced inside crm._set_lead_stage), and the kanban board's bulk move
-- (crm.bulk_set_lead_stage).
begin;
\ir _helpers.psql

select plan(22);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('other.owner@test.local') as other_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', 'phone-1', 'whatsapp', '919000000050', '{"name": "Deepak"}'),
       (:'org', 'phone-1', 'whatsapp', '919000000051', '{"name": "Esha"}'),
       (:'org', 'phone-1', 'whatsapp', '919000000052', '{"name": "Farhan"}');
select contact_id as deepak from crm.contact_addresses
where organization_id = :'org' and address = '919000000050' \gset
select contact_id as esha from crm.contact_addresses
where organization_id = :'org' and address = '919000000051' \gset
select contact_id as farhan from crm.contact_addresses
where organization_id = :'org' and address = '919000000052' \gset

-- Deal-entity custom field definitions ------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.create_custom_field(:'org', 'deal', 'notes', 'text', '{"en": "Notes"}') as notes_field \gset
select crm.create_custom_field(:'org', 'deal', 'must_have', 'text', '{"en": "Must have"}', '[]'::jsonb, true) as must_have_field \gset
select crm.create_custom_field(:'org', 'deal', 'budget', 'number', '{"en": "Budget"}') as budget_field \gset

select crm.find_or_create_lead(:'org', :'deepak', 'organic') as lead_deepak \gset
select crm.find_or_create_lead(:'org', :'esha', 'organic') as lead_esha \gset
select crm.find_or_create_lead(:'org', :'farhan', 'organic') as lead_farhan \gset

-- set_lead_fields: the global "required" flag, same bar as set_contact_fields ------------

select throws_ok(
  format($$ select crm.set_lead_fields(%L, '{"notes": "hello"}'::jsonb) $$, :'lead_deepak'),
  '22023', null, 'saving without the globally-required field is rejected'
);

select lives_ok(
  format(
    $$ select crm.set_lead_fields(%L, '{"notes": "hello", "must_have": "yes"}'::jsonb) $$,
    :'lead_deepak'
  ),
  'saving with the required field present succeeds'
);
select is(
  (select custom_fields->>'notes' from crm.leads where id = :'lead_deepak'),
  'hello',
  '...and the value sticks'
);

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.set_lead_fields(%L, '{}'::jsonb) $$, :'lead_deepak'),
  '42501', null, 'a viewer (no deals.edit) cannot set a lead''s fields'
);

-- set_stage_required_fields: admin-editable per-stage rule --------------------------------

select tests.as_user('owner@test.local');
select crm.create_lead_stage(:'org', 'Budget review') as stage_budget \gset
select crm.create_lead_stage(:'org', 'No requirements') as stage_free \gset

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.set_stage_required_fields(%L, array[%L]::uuid[]) $$, :'stage_budget', :'budget_field'),
  '42501', null, 'a sales_rep (no organization.manage) cannot set a stage''s required fields'
);

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.set_stage_required_fields(%L, array[%L]::uuid[]) $$,
    :'stage_budget', '00000000-0000-0000-0000-000000000000'),
  '22023', 'one or more fields were not found', 'a nonexistent field id is rejected'
);

select lives_ok(
  format($$ select crm.set_stage_required_fields(%L, array[%L]::uuid[]) $$, :'stage_budget', :'budget_field'),
  'the owner marks "budget" required for the "Budget review" stage'
);
select is(
  (select count(*)::int from crm.lead_stage_required_fields where stage_id = :'stage_budget'),
  1,
  '...recorded as one row'
);

-- set_lead_stage / bulk_set_lead_stage: the rule actually blocks the move -----------------

select throws_ok(
  format($$ select crm.set_lead_stage(%L, %L) $$, :'lead_deepak', :'stage_budget'),
  '22023', null, 'moving into the stage without the required field set is rejected'
);

select crm.set_lead_fields(:'lead_deepak', '{"budget": 5000}'::jsonb);
select lives_ok(
  format($$ select crm.set_lead_stage(%L, %L) $$, :'lead_deepak', :'stage_budget'),
  'filling the required field first lets the move through'
);
select is(
  (select stage_id from crm.leads where id = :'lead_deepak'),
  :'stage_budget',
  '...and it sticks'
);

-- Replacing the rule set clears the old one (not additive) --------------------------------

select crm.set_stage_required_fields(:'stage_budget', '{}'::uuid[]);
select is(
  (select count(*)::int from crm.lead_stage_required_fields where stage_id = :'stage_budget'),
  0,
  'set_stage_required_fields replaces, not appends -- an empty array clears the rule'
);

-- bulk_set_lead_stage: success, atomicity on partial failure, permission gate ------------

select lives_ok(
  format(
    $$ select crm.bulk_set_lead_stage(array[%L, %L]::uuid[], %L) $$,
    :'lead_esha', :'lead_farhan', :'stage_free'
  ),
  'bulk move succeeds for a stage with no required fields'
);
select results_eq(
  format($$ select stage_id from crm.leads where id in (%L, %L) order by id $$, :'lead_esha', :'lead_farhan'),
  format($$ values (%L::uuid), (%L::uuid) $$, :'stage_free', :'stage_free'),
  '...both leads moved'
);

select crm.set_stage_required_fields(:'stage_budget', array[:'budget_field']::uuid[]);
select throws_ok(
  format(
    $$ select crm.bulk_set_lead_stage(array[%L, %L]::uuid[], %L) $$,
    :'lead_esha', :'lead_farhan', :'stage_budget'
  ),
  '22023', null, 'bulk move rejects the whole batch when any one lead is missing a required field'
);
select is(
  (select stage_id from crm.leads where id = :'lead_esha'),
  :'stage_free',
  '...and the failure rolled back -- the other lead in the batch was not silently moved either'
);

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.bulk_set_lead_stage(array[%L]::uuid[], %L) $$, :'lead_esha', :'stage_free'),
  '42501', null, 'a viewer (no deals.edit) cannot bulk-move leads'
);

select tests.as_user('owner@test.local');
select throws_ok(
  $$ select crm.bulk_set_lead_stage(array[]::uuid[], null) $$,
  '22023', 'no leads given', 'an empty id array is rejected'
);
select throws_ok(
  format($$ select crm.bulk_set_lead_stage(array[%L, '00000000-0000-0000-0000-000000000000']::uuid[], %L) $$,
    :'lead_esha', :'stage_free'),
  '22023', 'one or more leads were not found in this organization',
  'a nonexistent lead id in the batch is rejected'
);

-- Audit trail -------------------------------------------------------------------------------

select isnt_empty(
  format($$ select 1 from crm.audit_log where organization_id = %L and action = 'lead_stage.required_fields_changed' $$, :'org'),
  'changing a stage''s required fields is audit-logged'
);

-- RLS on the new table ----------------------------------------------------------------------

select tests.as_user('rep@test.local');
select isnt_empty(
  format($$ select 1 from crm.lead_stage_required_fields where stage_id = %L $$, :'stage_budget'),
  'any org member can read the required-fields rule'
);

select tests.as_user('other.owner@test.local');
select is_empty(
  format($$ select 1 from crm.lead_stage_required_fields where stage_id = %L $$, :'stage_budget'),
  'another org cannot read this org''s required-fields rule'
);

select * from finish();
