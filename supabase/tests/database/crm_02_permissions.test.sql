-- P1-02: permission resolution, enforcement on upstream tables, per-tenant
-- toggles, overrides, number scopes, the 2FA gate and API keys.
begin;
\ir _helpers.psql

select plan(37);

select tests.create_user('owner@test.local');
select tests.create_user('admin@test.local');
select tests.create_user('rep@test.local');
select tests.create_user('viewer@test.local');
select tests.create_user('finance@test.local');
select tests.create_user('outsider@test.local');

select tests.create_org('owner@test.local', 'Gamma Academy') as org \gset
select tests.create_org('outsider@test.local', 'Other Academy') as other \gset
select tests.add_member(:'org', 'admin@test.local', 'admin');
select tests.add_member(:'org', 'rep@test.local', 'sales_rep');
select tests.add_member(:'org', 'viewer@test.local', 'viewer');
select tests.add_member(:'org', 'finance@test.local', 'finance');

-- Two WhatsApp numbers with one conversation each.
insert into public.organizations_addresses (organization_id, service, address, status) values
  (:'org', 'whatsapp', '111', 'connected'),
  (:'org', 'whatsapp', '222', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address) values
  (:'org', '111', 'whatsapp', '919000000001'),
  (:'org', '222', 'whatsapp', '919000000002');
insert into public.conversations (id, organization_id, organization_address, address, service, name) values
  ('00000000-0000-0000-0000-0000000000c1', :'org', '111', '919000000001', 'whatsapp', 'Lead on 111'),
  ('00000000-0000-0000-0000-0000000000c2', :'org', '222', '919000000002', 'whatsapp', 'Lead on 222');

-- Resolution -----------------------------------------------------------------------

select tests.as_user('viewer@test.local');
select ok(crm.has_permission(:'org', 'conversations.view'), 'a viewer can read conversations');
select ok(not crm.has_permission(:'org', 'messages.send'), 'a viewer cannot send');
select ok(not crm.has_permission(:'other', 'conversations.view'), 'no permission in an organization you are not in');

select tests.as_user('rep@test.local');
select ok(crm.has_permission(:'org', 'messages.send'), 'a sales rep can send');
select ok(not crm.has_permission(:'org', 'members.invite'), 'a sales rep cannot invite');

select tests.as_user('owner@test.local');
select is(
  (select count(*)::int from crm.my_permissions(:'org')),
  (select count(*)::int from crm.permissions),
  'my_permissions lists everything for an owner'
);

-- Enforcement on upstream tables --------------------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ insert into public.messages (organization_id, conversation_id, service, organization_address, conversation_address, agent_id, content)
            values (%L, '00000000-0000-0000-0000-0000000000c1', 'whatsapp', '111', '919000000001', %L,
                    '{"version":"1","type":"text","kind":"text","text":"hello"}') $$,
         :'org', tests.agent_id(:'org', 'viewer@test.local')),
  '42501',
  null,
  'a viewer cannot send a WhatsApp message'
);

select tests.as_user('rep@test.local');
select lives_ok(
  format($$ insert into public.messages (organization_id, conversation_id, service, organization_address, conversation_address, agent_id, content, status)
            values (%L, '00000000-0000-0000-0000-0000000000c1', 'whatsapp', '111', '919000000001', %L,
                    '{"version":"1","type":"text","kind":"text","text":"hello"}', '{}') $$,
         :'org', tests.agent_id(:'org', 'rep@test.local')),
  'a sales rep can send a WhatsApp message'
);

select tests.as_user('finance@test.local');
select is_empty(
  'select 1 from public.conversations where service = ''whatsapp''',
  'finance (no conversations.view) sees no conversations'
);
select is_empty(
  'select 1 from public.messages where service = ''whatsapp''',
  'finance sees no messages'
);
select isnt_empty(
  'select 1 from public.contacts_addresses',
  'finance still sees contacts (contacts.view)'
);

select tests.as_user('viewer@test.local');
select is(
  (select count(*)::int from public.conversations where service = 'whatsapp'),
  2,
  'a viewer sees every conversation'
);
select throws_ok(
  format($$ insert into public.contacts_addresses (organization_id, organization_address, service, address) values (%L, '111', 'whatsapp', '919000000009') $$, :'org'),
  '42501',
  null,
  'a viewer cannot add contacts'
);

select tests.as_user('rep@test.local');
select lives_ok(
  format($$ insert into public.contacts_addresses (organization_id, organization_address, service, address) values (%L, '111', 'whatsapp', '919000000009') $$, :'org'),
  'a sales rep can add contacts'
);

select tests.as_user('admin@test.local');
update public.organizations set name = 'Gamma Academy Renamed' where id = :'org';
select tests.as_postgres();
select is(
  (select name from public.organizations where id = :'org'),
  'Gamma Academy Renamed',
  'an admin can rename the organization'
);

-- Number access scope ------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.set_member_address_access(tests.agent_id(:'org', 'rep@test.local'), 'whatsapp', '111', true);

select tests.as_user('rep@test.local');
select results_eq(
  'select name from public.conversations where service = ''whatsapp''',
  $$ values ('Lead on 111'::text) $$,
  'a number-scoped rep sees only their number''s conversations'
);
select results_eq(
  'select address from public.organizations_addresses where service = ''whatsapp''',
  $$ values ('111'::text) $$,
  'a number-scoped rep sees only their number'
);
select is_empty(
  'select 1 from public.contacts_addresses where organization_address = ''222''',
  'a number-scoped rep sees no contacts of other numbers'
);

select tests.as_user('owner@test.local');
select crm.set_member_address_access(tests.agent_id(:'org', 'rep@test.local'), 'whatsapp', '111', false);
select tests.as_user('rep@test.local');
select is(
  (select count(*)::int from public.conversations where service = 'whatsapp'),
  2,
  'removing the last number lifts the restriction'
);

-- Role toggles ------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.set_role_permission(
  (select id from crm.roles where organization_id = :'org' and key = 'sales_rep'),
  'messages.send',
  false
);
select tests.as_user('rep@test.local');
select ok(not crm.has_permission(:'org', 'messages.send'), 'an owner switches messages.send off for sales reps');

select tests.as_user('owner@test.local');
select crm.reset_role_permissions((select id from crm.roles where organization_id = :'org' and key = 'sales_rep'));
select tests.as_user('rep@test.local');
select ok(crm.has_permission(:'org', 'messages.send'), 'reset restores the preset');

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.set_role_permission((select id from crm.roles where organization_id = %L and key = 'owner'), 'messages.send', false) $$, :'org'),
  '42501',
  'the Owner role cannot be changed',
  'the owner role is locked'
);
select throws_ok(
  format($$ select crm.set_role_permission((select id from crm.roles where organization_id = %L and key = 'sales_rep'), 'integrations.manage', true) $$, :'org'),
  '22023',
  'permission integrations.manage needs the admin tier',
  'a permission cannot go below its tier floor'
);

select tests.as_user('admin@test.local');
select throws_ok(
  format($$ select crm.set_role_permission((select id from crm.roles where organization_id = %L and key = 'admin'), 'organization.delete', true) $$, :'org'),
  '42501',
  'cannot change a role at or above your own',
  'an admin cannot widen the admin role'
);
select lives_ok(
  format($$ select crm.set_role_permission((select id from crm.roles where organization_id = %L and key = 'viewer'), 'contacts.export', true) $$, :'org'),
  'an admin toggles a lower role'
);

select tests.as_user('owner@test.local');
select crm.set_role_permission((select id from crm.roles where organization_id = :'org' and key = 'admin'), 'payments.manage', false);
select tests.as_user('admin@test.local');
select throws_ok(
  format($$ select crm.set_role_permission((select id from crm.roles where organization_id = %L and key = 'viewer'), 'payments.manage', true) $$, :'org'),
  '42501',
  'permission payments.manage required',
  'nobody grants a permission they do not hold'
);

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.set_role_permission((select id from crm.roles where organization_id = %L and key = 'viewer'), 'messages.send', true) $$, :'org'),
  '42501',
  'permission roles.manage required',
  'a sales rep cannot change roles'
);

select tests.as_postgres();
select id as viewer_role from crm.roles where organization_id = :'org' and key = 'viewer' \gset
select tests.as_user('outsider@test.local');
select throws_ok(
  format($$ select crm.set_role_permission(%L, 'messages.send', true) $$, :'viewer_role'),
  '42501',
  'permission roles.manage required',
  'another tenant''s owner cannot change our roles'
);

-- Member overrides ---------------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.set_member_permission_override(tests.agent_id(:'org', 'viewer@test.local'), 'messages.send', true);
select crm.set_member_permission_override(tests.agent_id(:'org', 'rep@test.local'), 'conversations.view', false);

select tests.as_user('viewer@test.local');
select ok(crm.has_permission(:'org', 'messages.send'), 'an override grants a permission the role lacks');
select tests.as_user('rep@test.local');
select ok(not crm.has_permission(:'org', 'conversations.view'), 'an override removes a permission the role has');

select tests.as_user('viewer@test.local');
select is_empty(
  format('select 1 from crm.member_permission_overrides where agent_id = %L', tests.agent_id(:'org', 'rep@test.local')),
  'members do not see other members'' overrides'
);

-- 2FA gate -------------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select throws_ok(
  format('select crm.set_require_mfa_for_admins(%L, true)', :'org'),
  '42501',
  'enable two-factor authentication on your own account first',
  'turning on the 2FA gate needs a 2FA session'
);
select tests.as_user('owner@test.local', 'aal2');
select crm.set_require_mfa_for_admins(:'org', true);

select tests.as_user('admin@test.local');
select ok(not crm.has_permission(:'org', 'members.view'), 'an admin without 2FA loses crm permissions');
select tests.as_user('admin@test.local', 'aal2');
select ok(crm.has_permission(:'org', 'members.view'), 'an admin with 2FA keeps them');
select tests.as_user('viewer@test.local');
select ok(crm.has_permission(:'org', 'members.view'), 'member-tier roles are not gated');

-- API keys ------------------------------------------------------------------------------

select tests.as_postgres();
insert into public.api_keys (organization_id, key, role, name) values (:'org', 'member-key', 'member', 'k');
select tests.as_api_key('member-key');
select ok(crm.has_permission(:'org', 'messages.send'), 'a member-tier API key keeps upstream send access');
select ok(not crm.has_permission(:'org', 'organization.manage'), 'a member-tier API key cannot manage the organization');

select * from finish();
rollback;
