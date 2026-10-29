-- P3-07c: crm.get_lead_history -- gated on deals.edit (not audit.view,
-- which sales_rep/sales_manager don't hold), re-checking the same
-- lead_scope visibility crm.leads' own RLS policy (P3-07a) uses so a rep
-- can't read another rep's lead history by id.
begin;
\ir _helpers.psql

select plan(8);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('rep.a@test.local') as rep_a_user \gset
select tests.create_user('rep.b@test.local') as rep_b_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset

select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep.a@test.local', 'sales_rep') as rep_a \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep.b@test.local', 'sales_rep') as rep_b \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', 'phone-1', 'whatsapp', '919000000060', '{"name": "Gopal"}');
select contact_id as gopal from crm.contact_addresses
where organization_id = :'org' and address = '919000000060' \gset

select tests.as_user('owner@test.local');
select crm.find_or_create_lead(:'org', :'gopal', 'organic') as lead_gopal \gset
select crm.assign_lead(:'lead_gopal', :'rep_a');

-- Not found / bogus id --------------------------------------------------------------------

select throws_ok(
  $$ select * from crm.get_lead_history('00000000-0000-0000-0000-000000000000') $$,
  'P0002', 'lead not found', 'a nonexistent lead id is rejected'
);

-- Permission gate (deals.edit, not audit.view) ---------------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select * from crm.get_lead_history(%L) $$, :'lead_gopal'),
  '42501', null, 'a viewer (no deals.edit) cannot read lead history'
);

-- own scope: the assigned rep sees it, including real entries ------------------------------

select tests.as_user('rep.a@test.local');
select isnt_empty(
  format($$ select 1 from crm.get_lead_history(%L) where action = 'lead.created' $$, :'lead_gopal'),
  'own scope: the assigned rep sees the lead.created entry'
);
select isnt_empty(
  format($$ select 1 from crm.get_lead_history(%L) where action = 'lead.assigned' $$, :'lead_gopal'),
  '...and the lead.assigned entry'
);

-- own scope: a DIFFERENT rep cannot read it -- "not found," not "forbidden" ----------------

select tests.as_user('rep.b@test.local');
select throws_ok(
  format($$ select * from crm.get_lead_history(%L) $$, :'lead_gopal'),
  'P0002', 'lead not found', 'own scope: a different rep gets "not found," not a 42501 that would confirm the lead exists'
);

-- team scope: now sees a teammate's lead's history -----------------------------------------

select tests.as_user('owner@test.local');
select crm.set_member_lead_scope(:'rep_b', 'team');
select crm.create_team(:'org', 'Shared Team') as shared_team \gset
select crm.set_team_member(:'shared_team', :'rep_a', true);
select crm.set_team_member(:'shared_team', :'rep_b', true);

select tests.as_user('rep.b@test.local');
select isnt_empty(
  format($$ select 1 from crm.get_lead_history(%L) $$, :'lead_gopal'),
  'team scope: now sees the teammate''s lead history'
);

-- all scope: the owner sees everything regardless ------------------------------------------

select tests.as_user('owner@test.local');
select isnt_empty(
  format($$ select 1 from crm.get_lead_history(%L) $$, :'lead_gopal'),
  'all scope: the owner sees it too'
);

-- Newest first ------------------------------------------------------------------------------

select ok(
  (
    select bool_and(ids[i] > ids[i + 1])
    from (
      select array_agg(id) as ids from crm.get_lead_history(:'lead_gopal')
    ) a, generate_series(1, array_length(a.ids, 1) - 1) i
  ),
  'entries come back newest first'
);

select * from finish();
