-- P3-02: lead model -- crm.leads (dedupe by contact_id, status vs stage)
-- and its 3 dynamic catalogs (crm.lead_stages/lead_qualities/
-- lead_drop_reasons), seeded from a platform preset the same way
-- crm.roles is seeded from crm.preset_roles.
begin;
\ir _helpers.psql

select plan(24);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('other.owner@test.local') as other_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset

-- Seeding on org creation ------------------------------------------------------------------

select is(
  (select count(*)::int from crm.lead_stages where organization_id = :'org'),
  6,
  'a new org is seeded with the 6 preset lead stages'
);
select is(
  (select count(*)::int from crm.lead_qualities where organization_id = :'org'),
  4,
  '...and the 4 preset lead qualities'
);
select is(
  (select count(*)::int from crm.lead_drop_reasons where organization_id = :'org'),
  9,
  '...and the 9 preset drop reasons'
);
select isnt_empty(
  format($$ select 1 from crm.lead_stages where organization_id = %L and key = 'enrolled' $$, :'org'),
  'the seeded stages include the expected preset key ("enrolled")'
);

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', 'phone-1', 'whatsapp', '919000000040', '{"name": "Asha"}');
select contact_id as asha from crm.contact_addresses
where organization_id = :'org' and address = '919000000040' \gset

select id as stage_enrolled from crm.lead_stages
where organization_id = :'org' and key = 'enrolled' \gset
select id as quality_high from crm.lead_qualities
where organization_id = :'org' and key = 'high_intent' \gset
select id as reason_pricing from crm.lead_drop_reasons
where organization_id = :'org' and key = 'pricing_issue' \gset

-- Catalog CRUD + permission gate (organization.manage) -------------------------------------

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.create_lead_stage(%L, 'Custom stage') $$, :'org'),
  '42501', null, 'a sales_rep (deals.edit, no organization.manage) cannot create a lead stage'
);

select tests.as_user('owner@test.local');
select crm.create_lead_stage(:'org', 'Nurturing') as stage_custom \gset
select isnt_empty(
  format($$ select 1 from crm.lead_stages where id = %L and is_preset = false $$, :'stage_custom'),
  'an owner can create a custom lead stage, recorded as not preset'
);

select crm.update_lead_stage(:'stage_custom', 'Nurturing (long-term)', 10);
select is(
  (select name from crm.lead_stages where id = :'stage_custom'),
  'Nurturing (long-term)',
  'update_lead_stage renames it'
);

select crm.delete_lead_stage(:'stage_custom');
select is_empty(
  format($$ select 1 from crm.lead_stages where id = %L $$, :'stage_custom'),
  'delete_lead_stage removes it'
);

-- Cross-org isolation on catalog writes -----------------------------------------------------

select tests.as_user('other.owner@test.local');
select throws_ok(
  format($$ select crm.update_lead_stage(%L, 'Stolen', 0) $$, :'stage_enrolled'),
  '42501', null, 'another org cannot rename this org''s lead stage -- checked against the stage''s own org'
);

-- find_or_create_lead: dedupe + reopen rules -------------------------------------------------

select tests.as_user('owner@test.local');
select crm.find_or_create_lead(:'org', :'asha', 'ctwa_ad') as lead_asha \gset
select isnt_empty(
  format($$ select 1 from crm.leads where id = %L and status = 'open' and source = 'ctwa_ad' $$, :'lead_asha'),
  'find_or_create_lead creates an open lead with the given source'
);

select crm.find_or_create_lead(:'org', :'asha', 'organic') as lead_asha_again \gset
select is(
  :'lead_asha_again'::uuid,
  :'lead_asha'::uuid,
  'calling it again for the same contact returns the SAME lead -- the dedupe'
);

-- Move it to dropped, then prove reopening via find_or_create_lead works.
select crm.set_lead_status(:'lead_asha', 'dropped', :'reason_pricing');
select crm.find_or_create_lead(:'org', :'asha', 'organic') as lead_asha_reopened \gset
select is(
  (select status from crm.leads where id = :'lead_asha_reopened'),
  'open',
  'find_or_create_lead reopens a dropped lead back to open'
);

-- set_lead_stage / set_lead_quality --------------------------------------------------------

select crm.set_lead_stage(:'lead_asha', :'stage_enrolled');
select is(
  (select stage_id from crm.leads where id = :'lead_asha'),
  :'stage_enrolled',
  'set_lead_stage moves the lead'
);

select crm.set_lead_quality(:'lead_asha', :'quality_high');
select is(
  (select quality_id from crm.leads where id = :'lead_asha'),
  :'quality_high',
  'set_lead_quality sets it'
);

select throws_ok(
  format($$ select crm.set_lead_stage(%L, '00000000-0000-0000-0000-000000000000') $$, :'lead_asha'),
  '22023', 'stage not found', 'a nonexistent stage id is rejected'
);

-- status rules: dropped requires a reason; converted is terminal ---------------------------

select throws_ok(
  format($$ select crm.set_lead_status(%L, 'dropped') $$, :'lead_asha'),
  '22023', 'a drop reason is required', 'dropping without a reason is rejected'
);

select crm.set_lead_status(:'lead_asha', 'converted');
select throws_ok(
  format($$ select crm.set_lead_status(%L, 'open') $$, :'lead_asha'),
  '22023', 'a converted lead cannot change status', 'a converted lead is terminal -- it cannot be reopened'
);

-- Permission gate on lead-working functions (deals.edit) -----------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.set_lead_quality(%L, %L) $$, :'lead_asha', :'quality_high'),
  '42501', null, 'a viewer (no deals.edit) cannot work a lead'
);

-- Table-level invariant: status='dropped' requires drop_reason_id, enforced
-- even below the function layer.
select tests.as_postgres();
select throws_ok(
  format(
    $$ update crm.leads set status = 'dropped', drop_reason_id = null where id = %L $$,
    :'lead_asha'
  ),
  '23514', null, 'the table''s own check constraint backs up the function-level drop-reason rule'
);

-- Dedupe constraint itself --------------------------------------------------------------------

select throws_ok(
  format(
    $$ insert into crm.leads (organization_id, contact_id, source) values (%L, %L, 'manual') $$,
    :'org', :'asha'
  ),
  '23505', null, 'a second lead row for the same contact is rejected at the constraint level too'
);

-- Audit trail ------------------------------------------------------------------------------

select isnt_empty(
  format($$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.created' $$, :'org'),
  'lead creation is audit-logged'
);
select isnt_empty(
  format($$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.reopened' $$, :'org'),
  'reopening is audit-logged distinctly from creation'
);
select isnt_empty(
  format($$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.status_changed' $$, :'org'),
  'an explicit status change is audit-logged'
);

-- Cross-org isolation on leads themselves ---------------------------------------------------

select tests.as_user('other.owner@test.local');
select is_empty(
  format($$ select 1 from crm.leads where id = %L $$, :'lead_asha'),
  'another org cannot read this org''s lead'
);

select * from finish();
rollback;
