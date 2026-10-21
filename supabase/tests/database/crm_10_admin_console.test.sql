-- P1-10: the super-admin console skeleton. Platform admins are a separate
-- axis from tenant roles; bootstrapping, granting/revoking, the last-admin
-- guard; tenant list; tier changes; pack upgrades; time-limited support
-- access (bounds, expiry, revocation, what it does and does not unlock);
-- who can read what; append-only; both audit logs.
begin;
\ir _helpers.psql

select plan(55);

select tests.create_user('admin1@test.local') as admin1 \gset
select tests.create_user('admin2@test.local') as admin2 \gset
select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('other.owner@test.local') as other_user \gset

select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

-- Bootstrapping ------------------------------------------------------------------------

select tests.as_user('owner@test.local');
-- Not granted to authenticated at all (only the crm-admin edge function's
-- service client may call it), so this is Postgres's own grant denial, not
-- crm.require_platform_admin's message.
select throws_ok(
  format($$ select crm.grant_platform_admin('admin2@test.local', %L) $$, :'admin1'),
  '42501', null, 'nobody can self-promote; there is no admin yet'
);

-- The one manual step: a human runs this by hand once (documented), not a
-- migration and not a UI action.
select tests.as_postgres();
insert into crm.platform_admins (user_id) values (:'admin1');

select tests.as_user('owner@test.local');
select ok(not crm.is_platform_admin(:'owner_user'::uuid), 'a tenant owner is not a platform admin by default');
select throws_ok(
  format($$ select crm.is_platform_admin(%L) $$, :'admin1'),
  '42501', 'can only check your own admin status', 'and cannot check someone else''s status'
);

select tests.as_service();
select ok(crm.is_platform_admin(:'admin1'), 'the bootstrapped admin is recognized, checked as service_role');

-- Granting and revoking -----------------------------------------------------------------

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.grant_platform_admin('admin2@test.local', %L) $$, :'owner_user'),
  '42501', null, 'a tenant owner cannot grant platform admin'
);

select tests.as_service();
select throws_ok(
  format($$ select crm.revoke_platform_admin(%L, %L) $$, :'admin1', :'admin1'),
  '22023', 'cannot remove the last platform admin', 'the only admin cannot revoke themselves'
);

select lives_ok(
  format($$ select crm.grant_platform_admin('admin2@test.local', %L) $$, :'admin1'),
  'an admin grants another admin, by email'
);
select throws_ok(
  format($$ select crm.grant_platform_admin('nobody@test.local', %L) $$, :'admin1'),
  'P0002', 'no user with that email', 'granting an unknown email is refused'
);
select lives_ok(
  format($$ select crm.grant_platform_admin('Admin2@Test.Local', %L) $$, :'admin1'),
  'granting the same person again (any case) is a no-op, not an error'
);
select is(
  (select count(*)::int from crm.platform_admins),
  2,
  'still exactly two admins after the repeat grant'
);
select results_eq(
  'select email from crm.list_platform_admins() order by email',
  $$ values ('admin1@test.local'::text), ('admin2@test.local') $$,
  'the admin list shows both'
);

select lives_ok(
  format($$ select crm.revoke_platform_admin(%L, %L) $$, :'admin2', :'admin1'),
  'revoking the second admin, while two exist, is fine'
);
select throws_ok(
  format($$ select crm.revoke_platform_admin(%L, %L) $$, :'admin1', :'admin1'),
  '22023', 'cannot remove the last platform admin', 'now admin1 really is the last one again'
);
-- Re-grant admin2 for the rest of this test.
select crm.grant_platform_admin('admin2@test.local', :'admin1');

-- Who can see the admin tables directly ---------------------------------------------

select tests.as_user('owner@test.local');
select is_empty(
  'select 1 from crm.platform_admins',
  'a tenant owner cannot see who the platform admins are (no RLS policy at all, not even 0 rows of their own)'
);
select is_empty(
  'select 1 from crm.platform_audit_log',
  'nor the platform audit log'
);

-- Tenants ------------------------------------------------------------------------------

select tests.as_postgres();
update billing.subscriptions set tier_id = 'starter' where organization_id = :'org';

select tests.as_user('owner@test.local');
select throws_ok(
  'select * from crm.list_tenants()',
  '42501', null, 'a tenant owner cannot list tenants'
);

select tests.as_service();
select isnt_empty(
  format($$ select 1 from crm.list_tenants('Jupiter') $$),
  'the admin lists tenants, searchable by name'
);
select is(
  (select tier_id from crm.list_tenants('Jupiter') limit 1),
  'starter',
  'with the tier it resolves to'
);
select is_empty(
  format($$ select 1 from crm.list_tenants('no-such-academy-xyz') $$),
  'a search with no match returns nothing'
);

-- Tier changes ---------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.set_organization_tier(%L, 'pro', %L) $$, :'org', :'admin1'),
  '42501', null, 'a tenant owner cannot change their own tier'
);

select tests.as_service();
select throws_ok(
  format($$ select crm.set_organization_tier(%L, 'no-such-tier', %L) $$, :'org', :'admin1'),
  '22023', 'unknown or inactive tier no-such-tier', 'an unknown tier is refused'
);
select lives_ok(
  format($$ select crm.set_organization_tier(%L, 'pro', %L) $$, :'org', :'admin1'),
  'the admin moves the organization to Pro'
);
select is(
  (select tier_id from billing.subscriptions where organization_id = :'org'),
  'pro',
  'the subscription reflects it'
);
select results_eq(
  format($$ select details->>'before', details->>'after' from crm.platform_audit_log where action = 'organization.tier_changed' and target_id = %L $$, :'org'),
  $$ values ('starter'::text, 'pro'::text) $$,
  'the platform audit log records who changed it and the before/after'
);
select isnt_empty(
  format($$ select 1 from crm.audit_log where organization_id = %L and action = 'organization.tier_changed' $$, :'org'),
  'the organization''s own audit log shows it too'
);

-- Pack upgrade ---------------------------------------------------------------------------

select tests.as_postgres();
select pack_key, version as v1 from crm.organization_packs where organization_id = :'org' \gset
select definition as v1_def from crm.pack_versions where pack_key = :'pack_key' and version = :v1 \gset
insert into crm.pack_versions (pack_key, version, definition, checksum)
values (:'pack_key', :v1 + 1, :'v1_def', 'test-checksum-p1-10');

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.admin_upgrade_organization_pack(%L, null, %L) $$, :'org', :'admin1'),
  '42501', null, 'a tenant owner cannot use the admin upgrade path'
);

select tests.as_service();
select is(
  crm.admin_upgrade_organization_pack(:'org', null, :'admin1'),
  :v1 + 1,
  'the admin upgrades the pack to the latest version'
);
select is(
  (select version from crm.organization_packs where organization_id = :'org'),
  :v1 + 1,
  'the organization''s pack row reflects it'
);
select isnt_empty(
  format($$ select 1 from crm.audit_log where organization_id = %L and action = 'pack.upgraded' $$, :'org'),
  'the normal pack-upgrade audit trigger still fires'
);
select isnt_empty(
  format($$ select 1 from crm.platform_audit_log where action = 'organization.pack_upgraded' and target_id = %L $$, :'org'),
  'and the platform log records which admin did it'
);

-- Support access -------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.grant_support_access(%L, %L, 'debugging a ticket') $$, :'org', :'admin1'),
  '42501', null, 'a tenant owner cannot grant themselves support access'
);

select tests.as_service();
select throws_ok(
  format($$ select crm.grant_support_access(%L, %L, 'x') $$, :'org', :'admin1'),
  '22023', 'a reason is required', 'too short a reason is refused'
);
select throws_ok(
  format($$ select crm.grant_support_access(%L, %L, 'a fine reason', 0) $$, :'org', :'admin1'),
  '22023', 'hours must be between 1 and 168 (one week)', 'zero hours is refused'
);
select throws_ok(
  format($$ select crm.grant_support_access(%L, %L, 'a fine reason', 169) $$, :'org', :'admin1'),
  '22023', 'hours must be between 1 and 168 (one week)', 'more than a week is refused'
);
select crm.grant_support_access(:'org', :'admin1', 'debugging ticket #42', 1) as grant_id \gset
select ok(
  crm.has_active_support_access(:'org', :'admin1'),
  'the grant is active right away'
);
select ok(
  not crm.has_active_support_access(:'org', :'admin2'),
  'but only for the admin it was granted to'
);
select ok(
  not crm.has_active_support_access(:'other', :'admin1'),
  'and only for the organization it names'
);

select tests.as_user('owner@test.local');
select isnt_empty(
  format($$ select 1 from crm.support_access_grants where organization_id = %L $$, :'org'),
  'the organization itself can see the grant made against it'
);
select tests.as_user('other.owner@test.local');
select is_empty(
  format($$ select 1 from crm.support_access_grants where organization_id = %L $$, :'org'),
  'another organization cannot'
);

select tests.as_service();
select throws_ok(
  format($$ select crm.admin_get_tenant_config(%L, %L) $$, :'org', :'admin2'),
  '42501', 'no active support-access grant for this organization', 'without a grant, config is refused'
);
select is(
  (crm.admin_get_tenant_config(:'org', :'admin1'))->'profile'->>'slug',
  (select slug from crm.organization_profiles where organization_id = :'org'),
  'with an active grant, the admin reads the organization''s configuration'
);
select ok(
  jsonb_typeof((crm.admin_get_tenant_config(:'org', :'admin1'))->'settings') = 'array',
  'including the resolved settings'
);
select throws_ok(
  format($$ select * from crm.admin_get_audit_log(%L, %L) $$, :'org', :'admin2'),
  '42501', 'no active support-access grant for this organization', 'and the audit log needs the same grant'
);
select isnt_empty(
  format($$ select 1 from crm.admin_get_audit_log(%L, %L) $$, :'org', :'admin1'),
  'with it, the admin reads the organization''s own audit log'
);

-- Revoking, and expiry -------------------------------------------------------------------

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.revoke_support_access(%L, %L) $$, :'grant_id', :'owner_user'),
  '42501', null, 'a tenant owner cannot revoke a support-access grant'
);

select tests.as_service();
select lives_ok(
  format($$ select crm.revoke_support_access(%L, %L) $$, :'grant_id', :'admin2'),
  'any admin (not only the one it was granted to) can revoke a grant'
);
select ok(
  not crm.has_active_support_access(:'org', :'admin1'),
  'the grant is no longer active'
);
select throws_ok(
  format($$ select crm.admin_get_tenant_config(%L, %L) $$, :'org', :'admin1'),
  '42501', 'no active support-access grant for this organization', 'so config reads stop working'
);
select throws_ok(
  format($$ select crm.revoke_support_access(%L, %L) $$, :'grant_id', :'admin1'),
  'P0002', 'grant not found or already revoked', 'revoking twice is refused'
);

-- A grant past its expiry behaves the same as a revoked one.
select tests.as_postgres();
select crm.grant_support_access(:'org', :'admin1', 'short window', 1) as grant2 \gset
update crm.support_access_grants set expires_at = now() - interval '1 minute' where id = :'grant2';
select tests.as_service();
select ok(
  not crm.has_active_support_access(:'org', :'admin1'),
  'an expired grant is no longer active, without being revoked'
);

-- Audit --------------------------------------------------------------------------------

select tests.as_postgres();
select results_eq(
  format($$
    select action from crm.audit_log
    where organization_id = %L and action like 'support_access.%%' order by id
  $$, :'org'),
  $$ values ('support_access.granted'::text), ('support_access.revoked'), ('support_access.granted') $$,
  'the organization''s own audit log shows both grants and the revocation'
);
select is(
  (select count(*)::int from crm.get_platform_audit_log()),
  (select count(*)::int from crm.platform_audit_log),
  'the platform audit log is readable in full by an admin, paged the same way as the tenant one'
);

select throws_ok(
  format($$ update crm.platform_audit_log set details = '{}' where action = 'organization.tier_changed' and target_id = %L $$, :'org'),
  '42501', 'the platform audit log is append-only', 'nobody can edit platform audit entries, not even the table owner'
);
select throws_ok(
  'delete from crm.platform_audit_log',
  '42501', 'the platform audit log is append-only', 'or delete them'
);
select throws_ok(
  'truncate crm.platform_audit_log',
  '42501', 'the platform audit log is append-only', 'or truncate the table'
);

select * from finish();
rollback;
