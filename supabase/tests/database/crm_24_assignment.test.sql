-- P3-05: assignment engine. Rule matching routes a qualified lead to a
-- crm.teams team; crm._pick_assignee distributes within that team by
-- weighted round robin, respecting a capacity cap and (team-scoped)
-- working hours; manual override and a timeout-driven cron reassign both
-- share the same engine internals.
begin;
\ir _helpers.psql

select plan(29);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_user('rep.a@test.local') as rep_a_user \gset
select tests.create_user('rep.b@test.local') as rep_b_user \gset
select tests.create_org('owner@test.local', 'Vega Academy') as org \gset
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset
select tests.add_member(:'org', 'rep.a@test.local', 'sales_rep') as rep_a \gset
select tests.add_member(:'org', 'rep.b@test.local', 'sales_rep') as rep_b \gset

select tests.as_user('owner@test.local');
select crm.create_team(:'org', 'Hindi Sales') as hindi_team \gset
select crm.create_team(:'org', 'English Sales') as english_team \gset
select crm.set_team_member(:'hindi_team', :'rep_a', true);
select crm.set_team_member(:'english_team', :'rep_a', true);
select crm.set_team_member(:'english_team', :'rep_b', true);

-- Rule CRUD permission gate (organization.manage) ------------------------------------------

select lives_ok(
  format($$ select crm.set_assignment_rule(%L, %L, 'hi', null, null, 1) $$, :'org', :'hindi_team'),
  'the owner adds a Hindi-language rule'
);
select lives_ok(
  format($$ select crm.set_assignment_rule(%L, %L, null, null, null, 2) $$, :'org', :'english_team'),
  'the owner adds a catch-all default rule'
);

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.set_assignment_rule(%L, %L, 'en', null, null, 3) $$, :'org', :'english_team'),
  '42501',
  null,
  'a viewer cannot add an assignment rule'
);

-- Rule matching: language wins over the catch-all when it applies -------------------------

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values
  (:'org', 'phone-1', 'whatsapp', '919000000060', '{"name": "Hindi Lead"}'),
  (:'org', 'phone-1', 'whatsapp', '919000000061', '{"name": "English Lead"}'),
  (:'org', 'phone-1', 'whatsapp', '919000000062', '{"name": "Capacity Lead"}'),
  (:'org', 'phone-1', 'whatsapp', '919000000063', '{"name": "Second Capacity Lead"}'),
  (:'org', 'phone-1', 'whatsapp', '919000000064', '{"name": "Hours Lead"}'),
  (:'org', 'phone-1', 'whatsapp', '919000000065', '{"name": "Timeout Lead"}');

select contact_id as hi_contact from crm.contact_addresses where organization_id = :'org' and address = '919000000060' \gset
select contact_id as en_contact from crm.contact_addresses where organization_id = :'org' and address = '919000000061' \gset
select contact_id as cap1_contact from crm.contact_addresses where organization_id = :'org' and address = '919000000062' \gset
select contact_id as cap2_contact from crm.contact_addresses where organization_id = :'org' and address = '919000000063' \gset
select contact_id as hours_contact from crm.contact_addresses where organization_id = :'org' and address = '919000000064' \gset
select contact_id as timeout_contact from crm.contact_addresses where organization_id = :'org' and address = '919000000065' \gset

update crm.contacts set locale = 'hi' where id = :'hi_contact';

select crm._ensure_lead(:'org', :'hi_contact', 'organic') as hi_lead \gset
select is(
  crm._match_assignment_rule(:'org', :'hi_lead'),
  :'hindi_team'::uuid,
  'a Hindi-locale lead matches the language-specific rule, not the catch-all'
);

select crm._ensure_lead(:'org', :'en_contact', 'organic') as en_lead \gset
select is(
  crm._match_assignment_rule(:'org', :'en_lead'),
  :'english_team'::uuid,
  'an English-locale lead falls through to the catch-all rule'
);

-- Weighted round robin: within English Sales (rep_a weight 1, rep_b weight 2) --------------

select tests.as_user('owner@test.local');
select lives_ok(
  format($$ select crm.set_team_member_weight(%L, %L, 2) $$, :'english_team', :'rep_b'),
  'the owner sets rep_b''s weight to 2'
);
select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.set_team_member_weight(%L, %L, 3) $$, :'english_team', :'rep_a'),
  '42501',
  null,
  'a viewer cannot change a team member''s weight'
);

select tests.as_postgres();
update crm.leads set status = 'qualified' where id = :'en_lead';

-- rep_a (weight 1, 0 open leads -> ratio 0) vs rep_b (weight 2, 0 open leads -> ratio 0):
-- a tie goes to whichever `order by` picks first (stable but unspecified) -- the real
-- weighting test is below, once rep_a already holds a lead.
select isnt(
  crm._pick_assignee(:'org', :'english_team'),
  null,
  'someone in English Sales is pickable with no load on anyone yet'
);

-- Give rep_a one open lead so the ratios differ: rep_a = 1/1 = 1, rep_b = 0/2 = 0 -> rep_b wins.
update crm.leads set assigned_to = :'rep_a', status = 'qualified' where id = :'hi_lead';
select is(
  crm._pick_assignee(:'org', :'english_team'),
  :'rep_b'::uuid,
  'rep_b (weight 2, unloaded) beats rep_a (weight 1, already holding a lead)'
);
update crm.leads set assigned_to = null, status = 'open' where id = :'hi_lead';

-- Capacity cap: both English Sales members at a cap of 1 -> nobody pickable -----------------

select tests.as_user('owner@test.local');
select lives_ok(
  format($$ select crm.set_setting(%L, 'assignment.capacity_cap', '1'::jsonb) $$, :'org'),
  'the owner lowers the capacity cap to 1'
);

select tests.as_postgres();
select crm._ensure_lead(:'org', :'cap1_contact', 'organic') as cap1_lead \gset
select crm._ensure_lead(:'org', :'cap2_contact', 'organic') as cap2_lead \gset
update crm.leads set assigned_to = :'rep_a', status = 'qualified' where id = :'cap1_lead';
update crm.leads set assigned_to = :'rep_b', status = 'qualified' where id = :'cap2_lead';

select is(
  crm._pick_assignee(:'org', :'english_team'),
  null,
  'both English Sales members are at the capacity cap -- nobody is pickable'
);

select tests.as_user('owner@test.local');
select lives_ok(
  format($$ select crm.set_setting(%L, 'assignment.capacity_cap', '20'::jsonb) $$, :'org'),
  'the owner raises the cap back up for the rest of the tests'
);

-- Working hours (team-scoped) ----------------------------------------------------------------

select lower(to_char(now() at time zone 'Asia/Kolkata', 'dy')) as today \gset
select to_char(now() at time zone 'Asia/Kolkata' - interval '1 hour', 'HH24:MI') as in_start \gset
select to_char(now() at time zone 'Asia/Kolkata' + interval '1 hour', 'HH24:MI') as in_end \gset
select to_char(now() at time zone 'Asia/Kolkata' + interval '2 hour', 'HH24:MI') as out_start \gset
select to_char(now() at time zone 'Asia/Kolkata' + interval '3 hour', 'HH24:MI') as out_end \gset

select lives_ok(
  format(
    $$ select crm.set_setting(%L, 'assignment.working_hours',
         '{"days": ["%s"], "start": "%s", "end": "%s"}'::jsonb, 'team', %L) $$,
    :'org', :'today', :'out_start', :'out_end', :'hindi_team'
  ),
  'the owner sets Hindi Sales'' working hours to a window that excludes right now'
);

select tests.as_postgres();
select is(
  crm._pick_assignee(:'org', :'hindi_team'),
  null,
  'outside configured working hours, nobody in the team is pickable'
);

select tests.as_user('owner@test.local');
select lives_ok(
  format(
    $$ select crm.set_setting(%L, 'assignment.working_hours',
         '{"days": ["%s"], "start": "%s", "end": "%s"}'::jsonb, 'team', %L) $$,
    :'org', :'today', :'in_start', :'in_end', :'hindi_team'
  ),
  '...and back to a window that includes right now'
);

select tests.as_postgres();
select isnt(
  crm._pick_assignee(:'org', :'hindi_team'),
  null,
  'inside configured working hours, rep_a is pickable again'
);

-- Manual assign/unassign (deals.edit) + audit trail ------------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.assign_lead(%L, %L) $$, :'hi_lead', :'rep_a'),
  '42501',
  null,
  'a viewer cannot manually assign a lead'
);

select tests.as_user('owner@test.local');
select lives_ok(
  format($$ select crm.assign_lead(%L, %L) $$, :'hi_lead', :'rep_a'),
  'the owner manually assigns a lead'
);
select is(
  (select assigned_to from crm.leads where id = :'hi_lead'),
  :'rep_a'::uuid,
  '...and it sticks'
);
select lives_ok(
  format($$ select crm.assign_lead(%L, %L) $$, :'hi_lead', :'rep_b'),
  'the owner reassigns it to someone else'
);
select results_eq(
  format($$ select action from crm.audit_log where organization_id = %L
            and target_id = %L and action like 'lead.%%assign%%' order by id $$,
         :'org', :'hi_lead'),
  $$ values ('lead.assigned'::text), ('lead.reassigned') $$,
  'the audit trail records the first assign and the reassign'
);
select lives_ok(
  format($$ select crm.unassign_lead(%L) $$, :'hi_lead'),
  'the owner unassigns it'
);
select is(
  (select assigned_to from crm.leads where id = :'hi_lead'),
  null,
  '...and it is cleared'
);

-- Auto-assign on qualification (opt-in, confirmed off by default) --------------------------

select tests.as_postgres();
select is(
  (select assigned_to from crm.leads where id = :'en_lead'),
  null,
  'auto_assign is off by default -- becoming qualified earlier did not assign en_lead'
);

select tests.as_user('owner@test.local');
select lives_ok(
  format($$ select crm.set_setting(%L, 'assignment.auto_assign', 'true'::jsonb) $$, :'org'),
  'the owner turns auto-assign on'
);

select tests.as_postgres();
update crm.leads set status = 'open' where id = :'en_lead';
update crm.leads set status = 'qualified' where id = :'en_lead';
select isnt(
  (select assigned_to from crm.leads where id = :'en_lead'),
  null,
  'the status transition to qualified auto-assigns en_lead once the setting is on'
);

-- Cron sweep: reassign on timeout, but only without activity --------------------------------

select crm._ensure_lead(:'org', :'timeout_contact', 'organic') as timeout_lead \gset
update crm.leads set status = 'qualified', assigned_to = :'rep_a',
  assigned_at = now() - interval '48 hours'
where id = :'timeout_lead';

select crm.sweep_lead_reassignment();
select isnt(
  (select action from crm.audit_log
   where organization_id = :'org' and target_id = :'timeout_lead' and action = 'lead.reassigned'
   order by created_at desc limit 1),
  null,
  'a stalled lead past the timeout with no activity gets reassigned by the cron sweep'
);

update crm.leads set assigned_to = :'rep_a', assigned_at = now() - interval '48 hours'
where id = :'timeout_lead';
select crm.write_audit(:'org', 'lead.stage_changed', 'lead', :'timeout_lead', '{}'::jsonb);
select crm.sweep_lead_reassignment();
select is(
  (select assigned_to from crm.leads where id = :'timeout_lead'),
  :'rep_a'::uuid,
  'a recent lead.* activity entry (the rep took action) blocks the reassign'
);

-- Cross-org isolation on assignment rules ----------------------------------------------------

select tests.create_user('other.owner@test.local') as other_user \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

select is_empty(
  format($$ select 1 from crm.assignment_rules where organization_id = %L $$, :'other'),
  'a second org has no assignment rules of its own'
);

select * from finish();
rollback;
