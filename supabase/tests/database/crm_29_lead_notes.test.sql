-- P3-07e: lead notes -- the last P3-07 sub-phase. CRUD gated on
-- deals.edit + lead_scope visibility (crm._lead_visible_to_caller, same
-- function P3-07d's tasks already use); not author-locked (any member
-- who can work the lead can edit/delete any note on it, the same
-- team-editable model conversation-level internal notes already use);
-- every write audited in crm.audit_log.
begin;
\ir _helpers.psql

select plan(13);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_user('rep.b@test.local') as rep_b_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_user('other.owner@test.local') as other_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep.b@test.local', 'sales_rep') as rep_b_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', 'phone-1', 'whatsapp', '919000000080', '{"name": "Ira"}');
select contact_id as ira from crm.contact_addresses
where organization_id = :'org' and address = '919000000080' \gset

select tests.as_user('owner@test.local');
select crm.find_or_create_lead(:'org', :'ira', 'organic') as lead_ira \gset
select crm.assign_lead(:'lead_ira', :'rep_agent');

-- Permission gate + visibility --------------------------------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.create_lead_note(%L, 'Called, no answer') $$, :'lead_ira'),
  '42501', null, 'a viewer (no deals.edit) cannot create a note'
);

select tests.as_user('rep.b@test.local');
select throws_ok(
  format($$ select crm.create_lead_note(%L, 'Should not work') $$, :'lead_ira'),
  'P0002', 'lead not found', 'own scope: a different rep cannot note a lead they cannot see'
);

-- create / read -------------------------------------------------------------------------------

select tests.as_user('rep@test.local');
select crm.create_lead_note(:'lead_ira', 'Called, interested in the weekend batch') as note_id \gset
select isnt_empty(
  format($$ select 1 from crm.lead_notes where id = %L and body = 'Called, interested in the weekend batch' $$, :'note_id'),
  'the assigned rep creates a note'
);
select is(
  (select author_agent_id from crm.lead_notes where id = :'note_id'),
  :'rep_agent'::uuid,
  '...recorded as its author'
);
select tests.as_postgres();
select isnt_empty(
  format($$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.note_created' $$, :'org'),
  '...and audit-logged'
);

-- Not author-locked: another member with visibility can edit/delete it ------------------------

select tests.as_user('owner@test.local');
select crm.set_member_lead_scope(:'rep_b_agent', 'team');
select crm.create_team(:'org', 'Shared Team') as shared_team \gset
select crm.set_team_member(:'shared_team', :'rep_agent', true);
select crm.set_team_member(:'shared_team', :'rep_b_agent', true);

select tests.as_user('rep.b@test.local');
select lives_ok(
  format($$ select crm.update_lead_note(%L, 'Edited by a teammate') $$, :'note_id'),
  'a teammate with visibility (not the author) can edit the note'
);
select is(
  (select body from crm.lead_notes where id = :'note_id'),
  'Edited by a teammate',
  '...and it sticks'
);
select tests.as_postgres();
select isnt_empty(
  format($$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.note_updated' $$, :'org'),
  '...audit-logged too'
);

select tests.as_user('rep.b@test.local');

-- delete ----------------------------------------------------------------------------------

select lives_ok(
  format($$ select crm.delete_lead_note(%L) $$, :'note_id'),
  'a teammate with visibility can delete the note'
);
select is_empty(
  format($$ select 1 from crm.lead_notes where id = %L $$, :'note_id'),
  '...and it is gone'
);
select tests.as_postgres();
select isnt_empty(
  format($$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.note_deleted' $$, :'org'),
  '...audit-logged too'
);

-- Tenant isolation ----------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.create_lead_note(:'lead_ira', 'A second note') as note_2 \gset

select tests.as_user('other.owner@test.local');
select is_empty(
  format($$ select 1 from crm.lead_notes where id = %L $$, :'note_2'),
  'another org cannot read this org''s lead note'
);
select throws_ok(
  format($$ select crm.delete_lead_note(%L) $$, :'note_2'),
  -- Not a member of this org at all, so the permission check (which runs
  -- before the lead-visibility check) is what actually rejects this --
  -- not "note not found," since it never gets that far.
  '42501', null, '...nor delete it'
);

select * from finish();
