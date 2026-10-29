-- P3-06: speed-to-lead. The SLA clock on crm.leads (first_response_due_at/
-- first_responded_at), the durable in-app notification sink (crm.
-- notifications, unlike P2-09f's browser-popup-only mechanism), and the
-- escalation sweep (rep -> manager -> auto-reassign), reusing crm.roles.
-- lead_scope ('team'/'all') for "who is a manager" for the first time.
begin;
\ir _helpers.psql

select plan(25);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_user('rep.a@test.local') as rep_a_user \gset
select tests.create_user('rep.b@test.local') as rep_b_user \gset
select tests.create_user('manager.all@test.local') as manager_all_user \gset
select tests.create_user('manager.team@test.local') as manager_team_user \gset
select tests.create_org('owner@test.local', 'Lyra Academy') as org \gset
select tests.as_postgres();
select tests.agent_id(:'org', 'owner@test.local') as owner_agent \gset
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset
select tests.add_member(:'org', 'rep.a@test.local', 'sales_rep') as rep_a \gset
select tests.add_member(:'org', 'rep.b@test.local', 'sales_rep') as rep_b \gset
select tests.add_member(:'org', 'manager.all@test.local', 'sales_manager') as manager_all \gset
select tests.add_member(:'org', 'manager.team@test.local', 'sales_rep') as manager_team \gset

select tests.as_user('owner@test.local');
select crm.create_team(:'org', 'Rep A Team') as rep_a_team \gset
select crm.set_team_member(:'rep_a_team', :'rep_a', true);
select crm.set_team_member(:'rep_a_team', :'manager_team', true);
select crm.create_team(:'org', 'Fallback Team') as fallback_team \gset
select crm.set_team_member(:'fallback_team', :'rep_b', true);
select crm.set_assignment_rule(:'org', :'fallback_team', null, null, null, 1);

select tests.as_postgres();
-- manager_team is on rep_a's team with an individual lead_scope override
-- ('team' instead of their role's default 'own') -- the first real
-- consumer of crm.member_roles.lead_scope anywhere in the codebase.
update crm.member_roles set lead_scope = 'team' where agent_id = :'manager_team';

insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values
  (:'org', 'phone-1', 'whatsapp', '919000000070', '{"name": "Lead One"}'),
  (:'org', 'phone-1', 'whatsapp', '919000000071', '{"name": "Lead Two"}'),
  (:'org', 'phone-1', 'whatsapp', '919000000072', '{"name": "Lead Three"}');

select contact_id as contact_1 from crm.contact_addresses where organization_id = :'org' and address = '919000000070' \gset
select contact_id as contact_2 from crm.contact_addresses where organization_id = :'org' and address = '919000000071' \gset
select contact_id as contact_3 from crm.contact_addresses where organization_id = :'org' and address = '919000000072' \gset

select crm._ensure_lead(:'org', :'contact_1', 'organic') as lead_1 \gset
select crm._ensure_lead(:'org', :'contact_2', 'organic') as lead_2 \gset
select crm._ensure_lead(:'org', :'contact_3', 'organic') as lead_3 \gset

insert into public.conversations (id, organization_id, organization_address, address, service, name)
values
  ('00000000-0000-0000-0000-0000000000e1', :'org', 'phone-1', '919000000070', 'whatsapp', 'Lead One'),
  ('00000000-0000-0000-0000-0000000000e2', :'org', 'phone-1', '919000000071', 'whatsapp', 'Lead Two'),
  ('00000000-0000-0000-0000-0000000000e3', :'org', 'phone-1', '919000000072', 'whatsapp', 'Lead Three');

-- An AI agent (no user_id) to prove its sends never count as "a human responded."
insert into public.agents (id, organization_id, name, role, extra)
values ('00000000-0000-0000-0000-0000000000aa', :'org', 'Bot', 'member', '{"ai": true}'::jsonb);

-- The SLA clock: assignment sets a deadline, reassignment refreshes it ------------------------

update crm.leads set assigned_to = :'rep_a', assigned_at = now() where id = :'lead_1';
select is(
  (select first_response_due_at - assigned_at from crm.leads where id = :'lead_1'),
  interval '15 minutes',
  'assignment sets the deadline 15 minutes out (the default SLA)'
);

update crm.leads set assigned_to = :'rep_b', assigned_at = now() where id = :'lead_1';
select is(
  (select first_response_due_at - assigned_at from crm.leads where id = :'lead_1'),
  interval '15 minutes',
  'reassigning before any response refreshes the deadline off the new assigned_at'
);

-- The first human reply stamps first_responded_at; an automated send never does ---------------

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  agent_id, content, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000e1', 'whatsapp', 'phone-1', '919000000070',
  '00000000-0000-0000-0000-0000000000aa',
  '{"version":"1","type":"text","kind":"text","text":"(automated) thanks for reaching out"}'::jsonb,
  now()
);
select is(
  (select first_responded_at from crm.leads where id = :'lead_1'),
  null,
  'an AI/system send does not count as a human response'
);

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  agent_id, content, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000e1', 'whatsapp', 'phone-1', '919000000070',
  :'rep_b',
  '{"version":"1","type":"text","kind":"text","text":"Hi! How can I help?"}'::jsonb,
  now()
);
select isnt(
  (select first_responded_at from crm.leads where id = :'lead_1'),
  null,
  'the rep''s own reply stamps first_responded_at'
);
select isnt(
  (select details->>'minutes_to_respond' from crm.audit_log
   where organization_id = :'org' and target_id = :'lead_1' and action = 'lead.first_responded'),
  null,
  '...and records the elapsed minutes in the audit trail'
);

update crm.leads set assigned_to = :'rep_a', assigned_at = now() where id = :'lead_1';
select is(
  (select first_responded_at is not null from crm.leads where id = :'lead_1'),
  true,
  'first_responded_at stays set across a later reassignment -- it is about the FIRST response only'
);

-- Escalation sweep: breach -> notify rep -------------------------------------------------------

update crm.leads set assigned_to = :'rep_a', assigned_at = now() where id = :'lead_2';
update crm.leads set first_response_due_at = now() - interval '1 minute' where id = :'lead_2';

select crm.sweep_speed_to_lead_escalation();
select is(
  (select count(*)::int from crm.notifications
   where organization_id = :'org' and agent_id = :'rep_a' and lead_id = :'lead_2'
     and kind = 'lead_sla_breached'),
  1,
  'a breached lead notifies its assignee exactly once'
);
select isnt(
  (select action from crm.audit_log
   where organization_id = :'org' and target_id = :'lead_2' and action = 'lead.sla_breached'),
  null,
  '...and is audited'
);

select crm.sweep_speed_to_lead_escalation();
select is(
  (select count(*)::int from crm.notifications
   where organization_id = :'org' and agent_id = :'rep_a' and lead_id = :'lead_2'
     and kind = 'lead_sla_breached'),
  1,
  'running the sweep again does not duplicate the breach notification'
);

-- Escalation sweep: manager step, 15 minutes past the breach ----------------------------------

update crm.leads set first_response_due_at = now() - interval '16 minutes' where id = :'lead_2';
select crm.sweep_speed_to_lead_escalation();

select is(
  (select count(*)::int from crm.notifications
   where organization_id = :'org' and agent_id = :'manager_all' and lead_id = :'lead_2'
     and kind = 'lead_escalated_to_manager'),
  1,
  'the lead_scope=all manager is notified at the manager escalation step'
);
select is(
  (select count(*)::int from crm.notifications
   where organization_id = :'org' and agent_id = :'manager_team' and lead_id = :'lead_2'
     and kind = 'lead_escalated_to_manager'),
  1,
  '...and so is the lead_scope=team manager who shares a team with the assignee'
);
select is(
  (select count(*)::int from crm.notifications
   where organization_id = :'org' and agent_id = :'rep_b' and lead_id = :'lead_2'),
  0,
  '...but an ordinary lead_scope=own rep on a different team is not'
);

select crm.sweep_speed_to_lead_escalation();
select is(
  (select count(*)::int from crm.notifications
   where organization_id = :'org' and agent_id = :'manager_all' and lead_id = :'lead_2'
     and kind = 'lead_escalated_to_manager'),
  1,
  'running the sweep again does not duplicate the manager escalation either'
);

-- Escalation sweep: auto-reassign, 30 minutes past the manager step ---------------------------

update crm.leads set status = 'qualified' where id = :'lead_2';
update crm.leads set first_response_due_at = now() - interval '46 minutes' where id = :'lead_2';
select crm.sweep_speed_to_lead_escalation();

select is(
  (select assigned_to from crm.leads where id = :'lead_2'),
  :'rep_b'::uuid,
  'past the reassign window, the catch-all rule reassigns the lead to the Fallback Team (rep_b)'
);
select is(
  (select count(*)::int from crm.notifications
   where organization_id = :'org' and agent_id = :'rep_a' and lead_id = :'lead_2'
     and kind = 'lead_auto_reassigned'),
  1,
  'the old assignee is told they were reassigned away from it'
);
select isnt(
  (select action from crm.audit_log
   where organization_id = :'org' and target_id = :'lead_2' and action = 'lead.auto_reassigned_sla'),
  null,
  '...and it is audited'
);

-- crm._lead_escalation_managers: direct unit coverage of the three lead_scope values -----------

select set_eq(
  format($$ select m from crm._lead_escalation_managers(%L, %L) m $$, :'org', :'rep_a'),
  format($$ values (%L::uuid), (%L::uuid), (%L::uuid) $$, :'owner_agent', :'manager_all', :'manager_team'),
  'escalation managers for rep_a are exactly the two lead_scope=all/team managers plus the owner (also lead_scope=all by role default)'
);
select is_empty(
  format($$ select m from crm._lead_escalation_managers(%L, %L) m where m = %L $$,
         :'org', :'rep_a', :'rep_b'),
  'an ordinary own-scope rep on another team is never an escalation manager'
);

-- Marking notifications read (member-facing, own-row only) -------------------------------------

select tests.as_postgres();
select id as manager_all_notification from crm.notifications
where agent_id = :'manager_all' and lead_id = :'lead_2' and kind = 'lead_escalated_to_manager'
limit 1 \gset

select tests.as_user('rep.a@test.local');
select throws_ok(
  format($$ select crm.mark_notification_read(%L) $$, :'manager_all_notification'),
  'P0002',
  null,
  'a rep cannot mark someone else''s notification read'
);

select tests.as_user('manager.all@test.local');
select lives_ok(
  format($$ select crm.mark_notification_read(%L) $$, :'manager_all_notification'),
  'a manager marks their own notification read'
);
select is(
  (select count(*)::int from crm.notifications where agent_id = :'manager_all' and read_at is not null),
  1,
  '...and it sticks'
);

select tests.as_user('rep.a@test.local');
select lives_ok(
  format($$ select crm.mark_all_notifications_read(%L) $$, :'org'),
  'rep_a marks all of their own notifications read in one call'
);
select is_empty(
  format($$ select 1 from crm.notifications where organization_id = %L and agent_id = %L and read_at is null $$,
         :'org', :'rep_a'),
  '...leaving none unread'
);

-- RLS: a member only ever sees their own notifications, never another member's ----------------

select tests.as_user('rep.b@test.local');
select is_empty(
  format($$ select 1 from crm.notifications where organization_id = %L and agent_id = %L $$,
         :'org', :'manager_all'),
  'RLS hides another member''s notifications even when queried directly'
);

-- Cross-org isolation -------------------------------------------------------------------------

select tests.as_postgres();
select tests.create_user('other.owner@test.local') as other_user \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

select tests.as_postgres();
select is_empty(
  format($$ select 1 from crm.notifications where organization_id = %L $$, :'other'),
  'a second org has no notifications of its own'
);

select * from finish();
rollback;
