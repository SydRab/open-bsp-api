-- P1-03 (and the P1-02 rules that apply to people): invitations with a crm
-- role, acceptance, role changes, tier limits, last-owner protection,
-- deactivation and revival.
begin;
\ir _helpers.psql

select plan(26);

select tests.create_user('owner@test.local');
select tests.create_user('admin@test.local');
select tests.create_user('viewer@test.local');
select tests.create_user('new.rep@test.local');
select tests.create_user('other.owner@test.local');

select tests.create_org('owner@test.local', 'Delta Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset
select tests.add_member(:'org', 'admin@test.local', 'admin');
select tests.add_member(:'org', 'viewer@test.local', 'viewer');

-- Inviting ---------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.invite_member(:'org', ' New.Rep@Test.local ', 'sales_rep') as invitation \gset

select tests.as_postgres();
select results_eq(
  format('select email, role::text, status from public.invitations where id = %L', :'invitation'),
  $$ values ('new.rep@test.local'::text, 'member'::text, 'pending'::text) $$,
  'the invitation carries the normalized email and the role''s tier'
);
select is(
  (select r.key from crm.invitation_roles ir join crm.roles r on r.id = ir.role_id where ir.invitation_id = :'invitation'),
  'sales_rep',
  'the crm role is recorded beside the invitation'
);

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.invite_member(%L, 'new.rep@test.local', 'viewer') $$, :'org'),
  '23505',
  null,
  'a second pending invitation for the same email is refused'
);
select throws_ok(
  format($$ select crm.invite_member(%L, 'viewer@test.local', 'viewer') $$, :'org'),
  '23505',
  'already a member of this organization',
  'an existing member cannot be invited again'
);
select throws_ok(
  format($$ select crm.invite_member(%L, 'not-an-email', 'viewer') $$, :'org'),
  '22023',
  'invalid email address',
  'a malformed email is refused'
);

select tests.as_user('admin@test.local');
select throws_ok(
  format($$ select crm.invite_member(%L, 'boss@test.local', 'owner') $$, :'org'),
  '42501',
  'cannot invite someone to a role above your own',
  'an admin cannot invite an owner'
);
select lives_ok(
  format($$ select crm.invite_member(%L, 'colleague@test.local', 'admin') $$, :'org'),
  'an admin can invite another admin'
);

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.invite_member(%L, 'friend@test.local', 'viewer') $$, :'org'),
  '42501',
  'permission members.invite required',
  'a viewer cannot invite'
);

select tests.as_user('other.owner@test.local');
select throws_ok(
  format($$ select crm.invite_member(%L, 'spy@test.local', 'admin') $$, :'org'),
  '42501',
  'permission members.invite required',
  'another tenant''s owner cannot invite into our organization'
);

-- Accepting -------------------------------------------------------------------------

select tests.as_user('new.rep@test.local');
select isnt_empty(
  format('select 1 from crm.invitation_roles where invitation_id = %L', :'invitation'),
  'the invitee can see the role they are offered'
);
select lives_ok(
  format('select public.accept_invitation(%L)', :'invitation'),
  'the invitee accepts through the upstream function'
);

select tests.as_postgres();
select tests.agent_id(:'org', 'new.rep@test.local') as rep \gset
select is(
  (select r.key from crm.member_roles mr join crm.roles r on r.id = mr.role_id where mr.agent_id = :'rep'),
  'sales_rep',
  'the new member holds the invited crm role'
);

select tests.as_user('new.rep@test.local');
select ok(crm.has_permission(:'org', 'messages.send'), 'and its permissions');

-- Role changes ------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.set_member_role(:'rep', 'admin');
select tests.as_postgres();
select is(
  (select role::text from public.agents where id = :'rep'),
  'admin',
  'a crm role change moves the upstream tier with it'
);

select tests.as_user('admin@test.local');
select throws_ok(
  format($$ select crm.set_member_role(%L, 'viewer') $$, tests.agent_id(:'org', 'owner@test.local')),
  '42501',
  'cannot manage a member above your own role',
  'an admin cannot demote an owner'
);
select throws_ok(
  format($$ select crm.set_member_role(%L, 'owner') $$, tests.agent_id(:'org', 'viewer@test.local')),
  '42501',
  'cannot grant a role above your own',
  'an admin cannot make an owner'
);

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.set_member_role(%L, 'admin') $$, tests.agent_id(:'org', 'owner@test.local')),
  'P0001',
  'Cannot delete the last owner of an organization',
  'the last owner cannot step down'
);

select tests.as_user('other.owner@test.local');
select throws_ok(
  format($$ select crm.set_member_role(%L, 'viewer') $$, :'rep'),
  '42501',
  'permission members.manage required',
  'another tenant cannot change our members'
);

-- The upstream role editor still works, and lands on the tier's preset.
select tests.as_user('owner@test.local');
update public.agents set role = 'member' where id = :'rep';
select tests.as_postgres();
select is(
  (select r.key from crm.member_roles mr join crm.roles r on r.id = mr.role_id where mr.agent_id = :'rep'),
  'viewer',
  'an upstream tier change maps to the least-privilege preset'
);

-- Deactivation and revival -----------------------------------------------------------

select tests.as_user('admin@test.local');
select throws_ok(
  format('select crm.deactivate_member(%L)', tests.agent_id(:'org', 'owner@test.local')),
  '42501',
  'cannot manage a member above your own role',
  'an admin cannot deactivate an owner'
);
select throws_ok(
  format('select crm.deactivate_member(%L)', tests.agent_id(:'org', 'admin@test.local')),
  '22023',
  'use leave organization to remove yourself',
  'deactivating yourself is refused'
);
select lives_ok(
  format('select crm.deactivate_member(%L)', :'rep'),
  'an admin deactivates a member'
);

select tests.as_postgres();
select isnt(
  (select deleted_at from public.agents where id = :'rep'),
  null,
  'deactivation is the upstream soft delete'
);

select tests.as_user('new.rep@test.local');
select ok(not crm.has_permission(:'org', 'conversations.view'), 'a deactivated member has no permissions');

select tests.as_user('owner@test.local');
select crm.invite_member(:'org', 'new.rep@test.local', 'teacher') as invitation2 \gset
select tests.as_user('new.rep@test.local');
select is(
  public.accept_invitation(:'invitation2'),
  :'rep'::uuid,
  'a re-invited member gets their old agent back'
);
select tests.as_postgres();
select is(
  (select r.key from crm.member_roles mr join crm.roles r on r.id = mr.role_id where mr.agent_id = :'rep'),
  'teacher',
  'with the new invitation''s role'
);

select * from finish();
rollback;
