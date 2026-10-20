-- P1-08: the audit log. Each audited change writes the right entry with the
-- right actor; only audit.view holders of the same organization read it;
-- nobody can write, edit or delete entries; the purge after the grace period
-- is the one way rows leave.
begin;
\ir _helpers.psql

select plan(42);

select tests.create_user('owner@test.local');
select tests.create_user('admin@test.local');
select tests.create_user('viewer@test.local');
select tests.create_user('other.owner@test.local');

select tests.create_org('owner@test.local', 'Echo Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset
select tests.add_member(:'org', 'admin@test.local', 'admin') as admin_agent \gset
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset
select tests.agent_id(:'org', 'owner@test.local') as owner_agent \gset
select id as sales_manager_role from crm.roles
where organization_id = :'org' and key = 'sales_manager' \gset

-- Organization creation -------------------------------------------------------------

select results_eq(
  format($$
    select action, actor_type, actor_agent_id from crm.audit_log
    where organization_id = %L
      and action in ('organization.created', 'pack.applied', 'member.joined')
      and actor_type = 'user'
    order by id
  $$, :'org'),
  format($$ values
    ('organization.created'::text, 'user'::text, null::uuid),
    ('pack.applied', 'user', null),
    ('member.joined', 'user', %L::uuid)
  $$, :'owner_agent'),
  'creating an organization logs its creation, the pack and the owner joining, as the creator'
);

select is(
  (select details->'after'->>'role' from crm.audit_log
   where organization_id = :'org' and action = 'member.role_changed'
     and target_id = :'owner_agent'),
  'owner',
  'the creator''s Owner role is logged'
);

select is(
  (select count(*)::int from crm.audit_log
   where organization_id = :'org' and action like 'role.%'),
  0,
  'setting up the preset roles is not logged permission by permission'
);

-- Organization profile ---------------------------------------------------------------

select tests.as_user('owner@test.local');
update crm.organization_profiles set timezone = 'Asia/Dubai' where organization_id = :'org';
update public.organizations set name = 'Echo Trading Academy' where id = :'org';

select tests.as_postgres();
select results_eq(
  format($$
    select details, actor_type, actor_user_id, actor_agent_id from crm.audit_log
    where organization_id = %L and action = 'organization.profile_updated'
    order by id
  $$, :'org'),
  format($$ values
    ('{"before": {"timezone": "Asia/Kolkata"}, "after": {"timezone": "Asia/Dubai"}}'::jsonb,
     'user'::text, (select id from auth.users where email = 'owner@test.local'), %1$L::uuid),
    ('{"before": {"name": "Echo Academy"}, "after": {"name": "Echo Trading Academy"}}'::jsonb,
     'user', (select id from auth.users where email = 'owner@test.local'), %1$L::uuid)
  $$, :'owner_agent'),
  'profile edits and renames log the changed fields, before and after, with the member who made them'
);

-- Roles ------------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.set_role_permission(:'sales_manager_role', 'reports.view', false);
select crm.set_role_permission(:'sales_manager_role', 'reports.view', true);

select tests.as_postgres();
select results_eq(
  format($$
    select action, target_type, target_id, details from crm.audit_log
    where organization_id = %L and action like 'role.%%' order by id
  $$, :'org'),
  format($$ values
    ('role.permission_revoked'::text, 'role'::text, %1$L::text,
     '{"permission": "reports.view", "role": "sales_manager"}'::jsonb),
    ('role.permission_granted', 'role', %1$L,
     '{"permission": "reports.view", "role": "sales_manager"}'::jsonb)
  $$, :'sales_manager_role'),
  'turning a role permission off and on logs both, against the role'
);

-- Invitations ------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.invite_member(:'org', 'new.rep@test.local', 'sales_rep') as invitation \gset
-- The entry is written at commit (it waits for the crm role); fire it now.
set constraints all immediate;
set constraints all deferred;
select crm.revoke_invitation(:'invitation');

select tests.as_postgres();
select results_eq(
  format($$
    select action, details from crm.audit_log
    where organization_id = %L and target_type = 'invitation' order by id
  $$, :'org'),
  $$ values
    ('invitation.created'::text,
     '{"email": "new.rep@test.local", "tier": "member", "role": "sales_rep"}'::jsonb),
    ('invitation.revoked', '{"email": "new.rep@test.local"}'::jsonb)
  $$,
  'an invitation logs its email and crm role, and its revocation'
);

-- Members ----------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.set_member_role(:'viewer_agent', 'finance');
select crm.set_member_lead_scope(:'viewer_agent', 'own');
select crm.set_member_permission_override(:'viewer_agent', 'reports.view', true);
select crm.set_member_permission_override(:'viewer_agent', 'reports.view', null);
select crm.deactivate_member(:'viewer_agent');

select tests.as_postgres();
select results_eq(
  format($$
    select action, details from crm.audit_log
    where organization_id = %L and target_id = %L and actor_type = 'user'
    order by id
  $$, :'org', :'viewer_agent'),
  $$ values
    ('member.role_changed'::text,
     '{"before": {"role": "viewer"}, "after": {"role": "finance"}}'::jsonb),
    ('member.lead_scope_changed',
     '{"before": {"lead_scope": null}, "after": {"lead_scope": "own"}}'::jsonb),
    ('member.permission_override_set',
     '{"permission": "reports.view", "granted": true}'::jsonb),
    ('member.permission_override_removed', '{"permission": "reports.view"}'::jsonb),
    ('member.deactivated', '{"name": "viewer"}'::jsonb)
  $$,
  'role, lead scope, override and deactivation changes are logged against the member'
);

select is(
  (select count(*)::int from crm.audit_log
   where organization_id = :'org' and target_id = :'viewer_agent'
     and actor_type = 'user' and actor_agent_id = :'owner_agent'),
  5,
  'each member change names the owner who made it'
);

select is(
  (select actor_type from crm.audit_log
   where organization_id = :'org' and action = 'member.joined'
     and target_id = :'admin_agent'),
  'system',
  'a change with no caller (seed, migration, SQL console) is logged as system'
);

-- Pack items -------------------------------------------------------------------------

select id as item from crm.organization_pack_items
where organization_id = :'org' order by kind, item_key limit 1 \gset

select tests.as_user('owner@test.local');
update crm.organization_pack_items set value = '"Customized"'::jsonb where id = :'item';
select crm.reset_pack_item(:'item');

select tests.as_postgres();
select results_eq(
  format($$
    select action, details->'after' = '"Customized"'::jsonb from crm.audit_log
    where organization_id = %L and target_type = 'pack_item' order by id
  $$, :'org'),
  $$ values ('pack.item_updated'::text, true), ('pack.item_reset', false) $$,
  'a pack item edit and its reset are logged'
);

-- Platform actions -------------------------------------------------------------------

select tests.as_service();
select crm.suspend_organization(:'org', 'unpaid invoice');
select crm.reactivate_organization(:'org');
select crm.write_audit(:'org', 'integration.token_connected', 'integration', 'whatsapp', '{"phone_number_id": "123"}');

select tests.as_postgres();
select results_eq(
  format($$
    select action, actor_type, details from crm.audit_log
    where organization_id = %L and actor_type = 'service' order by id
  $$, :'org'),
  $$ values
    ('organization.suspended'::text, 'service'::text, '{"reason": "unpaid invoice"}'::jsonb),
    ('organization.reactivated', 'service', '{}'::jsonb),
    ('integration.token_connected', 'service', '{"phone_number_id": "123"}'::jsonb)
  $$,
  'suspension, reactivation and edge-function events are logged as the platform'
);

select tests.as_user('owner@test.local');
select crm.request_organization_deletion(:'org');
select crm.cancel_organization_deletion(:'org');

select tests.as_postgres();
select results_eq(
  format($$
    select action from crm.audit_log
    where organization_id = %L and action like 'organization.deletion_%%' order by id
  $$, :'org'),
  $$ values ('organization.deletion_requested'::text), ('organization.deletion_cancelled') $$,
  'a deletion request and its cancellation are logged'
);

-- Who can read -----------------------------------------------------------------------

select tests.as_user('owner@test.local');
select ok(
  (select count(*) from crm.audit_log where organization_id = :'org') > 20,
  'the owner reads the organization''s audit log'
);

select tests.as_user('admin@test.local');
select ok(
  (select count(*) from crm.audit_log where organization_id = :'org') > 20,
  'an admin reads it too (audit.view)'
);

select tests.as_postgres();
select tests.add_member(:'org', 'other.owner@test.local', 'viewer');
select tests.as_user('other.owner@test.local');
select is_empty(
  format('select 1 from crm.audit_log where organization_id = %L', :'org'),
  'a member without audit.view reads nothing'
);
select isnt_empty(
  format('select 1 from crm.audit_log where organization_id = %L', :'other'),
  'while still reading their own organization''s log'
);
select throws_ok(
  format($$ select * from crm.get_audit_log(%L) $$, :'org'),
  '42501',
  'permission audit.view required',
  'get_audit_log refuses a member without audit.view'
);

select tests.as_user('owner@test.local');
select is_empty(
  format('select 1 from crm.audit_log where organization_id = %L', :'other'),
  'tenant A cannot read tenant B''s audit log'
);
select throws_ok(
  format($$ select * from crm.get_audit_log(%L) $$, :'other'),
  '42501',
  'permission audit.view required',
  'get_audit_log refuses another organization'
);

select tests.as_postgres();
insert into public.api_keys (organization_id, role, name, key)
values (:'org', 'owner', 'Integration', 'test-audit-key');
select tests.as_api_key('test-audit-key');
select throws_ok(
  format('select 1 from crm.audit_log where organization_id = %L', :'org'),
  '42501',
  null,
  'API keys cannot read the audit log, even an owner key'
);

-- get_audit_log ----------------------------------------------------------------------

select tests.as_user('owner@test.local');
select is(
  (select array_agg(distinct split_part(action, '.', 1))
   from crm.get_audit_log(:'org', p_area => 'role')),
  array['role'],
  'the area filter returns only that area'
);
select is(
  (select count(*)::int from crm.get_audit_log(:'org', p_limit => 3)),
  3,
  'the page size is honored'
);
select ok(
  (select max(id) from crm.get_audit_log(:'org', p_before_id => (
     select min(id) from crm.get_audit_log(:'org', p_limit => 3)
   ))) < (select min(id) from crm.get_audit_log(:'org', p_limit => 3)),
  'the next page starts below the previous one'
);
select is(
  (select array_agg(distinct actor_name)
   from crm.get_audit_log(:'org', p_actor => :'owner_agent')),
  array['owner'],
  'the actor filter returns that member''s actions, named'
);
select results_eq(
  format($$
    select distinct target_name from crm.get_audit_log(%L, p_area => 'member')
    where action = 'member.role_changed' and target_id = %L
  $$, :'org', :'viewer_agent'),
  $$ values ('viewer'::text) $$,
  'member entries name the member they are about'
);
select results_eq(
  format($$ select distinct target_name from crm.get_audit_log(%L, p_area => 'role') $$, :'org'),
  $$ values ('Sales Manager'::text) $$,
  'role entries name the role'
);
select is(
  (select count(*)::int from crm.get_audit_log(:'org', p_from => now() + interval '1 minute')),
  0,
  'the time window filters entries'
);

-- Nobody writes, edits or deletes ----------------------------------------------------

select tests.as_user('owner@test.local');
select throws_ok(
  format($$
    insert into crm.audit_log (organization_id, actor_type, action)
    values (%L, 'user', 'member.joined')
  $$, :'org'),
  '42501',
  null,
  'a member cannot insert entries'
);
select throws_ok(
  format($$ update crm.audit_log set details = '{}' where organization_id = %L $$, :'org'),
  '42501',
  null,
  'a member cannot edit entries'
);
select throws_ok(
  format($$ delete from crm.audit_log where organization_id = %L $$, :'org'),
  '42501',
  null,
  'a member cannot delete entries'
);
select throws_ok(
  format($$ select crm.write_audit(%L, 'member.joined') $$, :'org'),
  '42501',
  null,
  'a member cannot call the writer (no forged entries)'
);

select tests.as_api_key('test-audit-key');
select throws_ok(
  format($$ select crm.write_audit(%L, 'member.joined') $$, :'org'),
  '42501',
  null,
  'an API key cannot call the writer'
);

select tests.as_service();
select throws_ok(
  format($$ delete from crm.audit_log where organization_id = %L $$, :'org'),
  '42501',
  null,
  'the platform cannot delete entries either'
);
select throws_ok(
  format($$ update crm.audit_log set details = '{}' where organization_id = %L $$, :'org'),
  '42501',
  null,
  'or edit them'
);

select tests.as_postgres();
select throws_ok(
  format($$ update crm.audit_log set details = '{}' where organization_id = %L $$, :'org'),
  '42501',
  'the audit log is append-only',
  'even the table owner cannot edit entries'
);
select throws_ok(
  format($$ delete from crm.audit_log where organization_id = %L $$, :'org'),
  '42501',
  'the audit log is append-only',
  'or delete them'
);
select throws_ok(
  'truncate crm.audit_log',
  '42501',
  'the audit log is append-only',
  'or truncate the table'
);
select throws_ok(
  format($$ delete from public.organizations where id = %L $$, :'org'),
  '42501',
  'the audit log is append-only',
  'an organization cannot be hard-deleted outside the purge (its log would go)'
);

-- The purge is the one way out -------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.request_organization_deletion(:'org');

select tests.as_postgres();
update crm.organization_profiles
set purge_after = now() - interval '1 minute'
where organization_id = :'org';
select count(*) as other_rows from crm.audit_log where organization_id = :'other' \gset

select tests.as_service();
select is(crm.purge_organizations(), 1, 'the purge deletes the organization after its grace period');

select tests.as_postgres();
select is_empty(
  format('select 1 from crm.audit_log where organization_id = %L', :'org'),
  'its audit log goes with it (right to erasure)'
);
select is(
  (select count(*) from crm.audit_log where organization_id = :'other'),
  :'other_rows'::bigint,
  'other organizations'' logs are untouched'
);
select is(
  current_setting('crm.purging', true),
  'off',
  'the purge leaves the append-only guard on'
);

select * from finish();
rollback;
