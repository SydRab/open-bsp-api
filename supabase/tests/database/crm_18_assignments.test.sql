-- P2-09c: assign/transfer -- crm.conversation_assignments, one row per
-- conversation (not many-to-many like tags/teams): a second
-- crm.assign_conversation call transfers it instead of adding a row.
-- Gated on 'messages.send', not 'conversations.view' like tags -- a viewer
-- (has conversations.view, not messages.send) must be rejected; a sales_rep
-- (has both) must be allowed.
begin;
\ir _helpers.psql

select plan(12);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('other.owner@test.local') as other_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_user('ghost@test.local') as ghost_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset
select tests.add_member(:'org', 'ghost@test.local', 'viewer') as ghost_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');
insert into public.conversations (id, organization_id, organization_address, address, service, name)
values ('00000000-0000-0000-0000-0000000000f2', :'org', 'phone-1', '919000000021', 'whatsapp', 'Assignment test');
select tests.agent_id(:'org', 'owner@test.local') as owner_agent \gset

-- Claim, transfer, unassign ---------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.assign_conversation('00000000-0000-0000-0000-0000000000f2', :'owner_agent');
select isnt_empty(
  format(
    $$ select 1 from crm.conversation_assignments where conversation_id = '00000000-0000-0000-0000-0000000000f2' and agent_id = %L $$,
    :'owner_agent'
  ),
  'a member with messages.send can claim a conversation for themselves'
);

select crm.assign_conversation('00000000-0000-0000-0000-0000000000f2', :'rep_agent');
select is(
  (select count(*)::int from crm.conversation_assignments where conversation_id = '00000000-0000-0000-0000-0000000000f2'),
  1,
  'reassigning does not add a second row -- it is a transfer, not a membership'
);
select is(
  (select agent_id from crm.conversation_assignments where conversation_id = '00000000-0000-0000-0000-0000000000f2'),
  :'rep_agent',
  'the transfer moved the assignment to the new agent'
);

select crm.unassign_conversation('00000000-0000-0000-0000-0000000000f2');
select is_empty(
  format(
    $$ select 1 from crm.conversation_assignments where conversation_id = '00000000-0000-0000-0000-0000000000f2' $$
  ),
  'unassigning removes the row'
);
select lives_ok(
  $$ select crm.unassign_conversation('00000000-0000-0000-0000-0000000000f2') $$,
  'unassigning an already-unassigned conversation is a no-op, not an error'
);

-- Target agent validation ------------------------------------------------------------------

select throws_ok(
  format(
    $$ select crm.assign_conversation('00000000-0000-0000-0000-0000000000f2', %L) $$,
    '00000000-0000-0000-0000-000000000000'
  ),
  '22023', 'agent not found', 'assigning a nonexistent agent is rejected'
);

select tests.as_postgres();
update public.agents set deleted_at = now() where id = :'ghost_agent';
select tests.as_user('owner@test.local');
select throws_ok(
  format(
    $$ select crm.assign_conversation('00000000-0000-0000-0000-0000000000f2', %L) $$,
    :'ghost_agent'
  ),
  '22023', 'agent not found', 'assigning a deleted agent is rejected, same as a nonexistent one'
);

-- Isolation ---------------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.assign_conversation('00000000-0000-0000-0000-0000000000f2', :'owner_agent');

select tests.as_user('other.owner@test.local');
select is_empty(
  $$ select 1 from crm.conversation_assignments where conversation_id = '00000000-0000-0000-0000-0000000000f2' $$,
  'another org cannot read this org''s assignment row'
);
select throws_ok(
  format(
    $$ select crm.assign_conversation('00000000-0000-0000-0000-0000000000f2', %L) $$,
    :'owner_agent'
  ),
  '42501', null, 'nor assign it -- require_permission checks against the CONVERSATION''s own org'
);
select throws_ok(
  $$ select crm.unassign_conversation('00000000-0000-0000-0000-0000000000f2') $$,
  '42501', null, 'nor unassign it'
);

-- Permission gate: messages.send, not conversations.view ------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format(
    $$ select crm.assign_conversation('00000000-0000-0000-0000-0000000000f2', %L) $$,
    :'rep_agent'
  ),
  '42501', null, 'a viewer (conversations.view but not messages.send) cannot assign'
);

select tests.as_user('rep@test.local');
select lives_ok(
  format(
    $$ select crm.assign_conversation('00000000-0000-0000-0000-0000000000f2', %L) $$,
    :'rep_agent'
  ),
  'a sales_rep (has messages.send) can claim a conversation'
);

select * from finish();
rollback;
