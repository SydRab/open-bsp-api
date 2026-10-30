-- P3-10b: reports, sub-phase 2 (response times, rep leaderboard). Same
-- `reports.view` gate as P3-10a. Both report functions read
-- crm.leads' own first_responded_at/assigned_at/first_response_due_at
-- directly -- not crm.audit_log's 'lead.first_responded' entry, whose
-- actor_agent_id is never the responding rep (that audit write happens
-- from the dispatcher's own service-role trigger context, no auth.uid()).
begin;
\ir _helpers.psql

select plan(14);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_user('rep.b@test.local') as rep_b_user \gset
select tests.create_org('owner@test.local', 'Leaderboard Academy') as org \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep.b@test.local', 'sales_rep') as rep_b_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', '910000000000', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values
  (:'org', '910000000000', 'whatsapp', '919000000301', '{"name": "On time"}'),
  (:'org', '910000000000', 'whatsapp', '919000000302', '{"name": "Late"}'),
  (:'org', '910000000000', 'whatsapp', '919000000303', '{"name": "Never responded, overdue"}'),
  (:'org', '910000000000', 'whatsapp', '919000000304', '{"name": "Rep B lead"}');
select contact_id as c_on_time from crm.contact_addresses where organization_id = :'org' and address = '919000000301' \gset
select contact_id as c_late from crm.contact_addresses where organization_id = :'org' and address = '919000000302' \gset
select contact_id as c_overdue from crm.contact_addresses where organization_id = :'org' and address = '919000000303' \gset
select contact_id as c_rep_b from crm.contact_addresses where organization_id = :'org' and address = '919000000304' \gset

select tests.as_user('owner@test.local');
select crm.find_or_create_lead(:'org', :'c_on_time', 'organic') as lead_on_time \gset
select crm.assign_lead(:'lead_on_time', :'rep_agent');
select crm.set_lead_status(:'lead_on_time', 'qualified');
select crm.set_lead_status(:'lead_on_time', 'converted');
select crm.set_lead_deal_value(:'lead_on_time', 10000);

select crm.find_or_create_lead(:'org', :'c_late', 'organic') as lead_late \gset
select crm.assign_lead(:'lead_late', :'rep_agent');

select crm.find_or_create_lead(:'org', :'c_overdue', 'organic') as lead_overdue \gset
select crm.assign_lead(:'lead_overdue', :'rep_agent');

select crm.find_or_create_lead(:'org', :'c_rep_b', 'organic') as lead_rep_b \gset
select crm.assign_lead(:'lead_rep_b', :'rep_b_agent');

-- Backdate assignment/response timestamps directly -- the SLA clock's own
-- trigger (crm.z_set_response_deadline, P3-06) already set first_response_
-- due_at from assigned_at + the default 15-minute SLA at assign time; push
-- everything an hour into the past so "on time"/"late"/"overdue" are
-- deterministic regardless of real wall-clock timing (the
-- crm_24_assignment lesson, again).
select tests.as_postgres();
update crm.leads
set assigned_at = now() - interval '1 hour',
    first_response_due_at = now() - interval '45 minutes'
where id in (:'lead_on_time', :'lead_late', :'lead_overdue', :'lead_rep_b');

update crm.leads set first_responded_at = now() - interval '50 minutes' where id = :'lead_on_time';
update crm.leads set first_responded_at = now() - interval '10 minutes' where id = :'lead_late';
update crm.leads set first_responded_at = now() - interval '55 minutes' where id = :'lead_rep_b';
-- lead_overdue: never responded, due_at already in the past -- stays overdue.

-- Permission gate --------------------------------------------------------------------------------

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.report_response_times(%L) $$, :'org'),
  '42501', null, 'a sales_rep (no reports.view by default) cannot read the response-time report'
);
select throws_ok(
  format($$ select crm.report_rep_leaderboard(%L) $$, :'org'),
  '42501', null, '...nor the rep leaderboard'
);

-- Response times -----------------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select is(
  (select assigned_count from crm.report_response_times(:'org')),
  4::bigint,
  'all 4 assigned leads counted'
);
select is(
  (select responded_count from crm.report_response_times(:'org')),
  3::bigint,
  '3 of them have responded (on_time, late, rep_b)'
);
select is(
  (select breached_count from crm.report_response_times(:'org')),
  2::bigint,
  '2 are breached: "late" (responded after due_at) and "overdue" (never responded, past due_at) -- "on_time" and "rep_b" are not'
);

-- Rep leaderboard -------------------------------------------------------------------------------

select is(
  (select leads_assigned from crm.report_rep_leaderboard(:'org') where agent_id = :'rep_agent'),
  3::bigint,
  'rep has 3 assigned leads (on_time, late, overdue)'
);
select is(
  (select leads_converted from crm.report_rep_leaderboard(:'org') where agent_id = :'rep_agent'),
  1::bigint,
  '...1 converted'
);
select is(
  (select deal_value_won from crm.report_rep_leaderboard(:'org') where agent_id = :'rep_agent'),
  10000::numeric,
  '...deal_value_won only counts the converted lead''s value'
);
select is(
  (select breached_count from crm.report_rep_leaderboard(:'org') where agent_id = :'rep_agent'),
  2::bigint,
  '...2 of rep''s 3 leads are breached'
);
select is(
  (select leads_assigned from crm.report_rep_leaderboard(:'org') where agent_id = :'rep_b_agent'),
  1::bigint,
  'rep.b has exactly 1 assigned lead, not mixed with rep''s own'
);
select is(
  (select breached_count from crm.report_rep_leaderboard(:'org') where agent_id = :'rep_b_agent'),
  0::bigint,
  '...and it is not breached (responded before due_at)'
);

-- A from-date filter on assigned_at excludes everything (all backdated 1 hour) ------------------

select is(
  (select count(*)::int from crm.report_rep_leaderboard(:'org', now() - interval '10 minutes', null)),
  0,
  'a from-date filter tighter than the backdated assigned_at excludes every row'
);

-- Cross-org isolation ---------------------------------------------------------------------------

select tests.as_postgres();
select tests.create_user('other.owner@test.local') as other_owner \gset
select tests.as_user('owner@test.local');
select tests.create_org('other.owner@test.local', 'Other Leaderboard Org') as other_org \gset

select tests.as_user('other.owner@test.local');
select is(
  (select count(*)::int from crm.report_rep_leaderboard(:'other_org')),
  0,
  'a different (empty) org sees zero leaderboard rows -- confirms the org filter, not a leak'
);
select is(
  (select assigned_count from crm.report_response_times(:'other_org')),
  0::bigint,
  '...and zero in the response-time report too'
);

select * from finish();
