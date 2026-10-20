-- P1-01: tenant creation, profile, lifecycle and tenant isolation of the
-- crm tables.
begin;
\ir _helpers.psql

select plan(36);

select tests.create_user('owner.a@test.local');
select tests.create_user('admin.a@test.local');
select tests.create_user('owner.b@test.local');

select tests.create_org('owner.a@test.local', 'Alpha Trading Academy') as org_a \gset
select tests.create_org('owner.b@test.local', 'Beta Markets') as org_b \gset
select tests.add_member(:'org_a', 'admin.a@test.local', 'admin');

-- Creation ---------------------------------------------------------------------

select is(
  (select slug from crm.organization_profiles where organization_id = :'org_a'),
  'alpha-trading-academy',
  'a new organization gets a slug from its name'
);

select is(
  (select timezone from crm.organization_profiles where organization_id = :'org_a'),
  'Asia/Kolkata',
  'the default timezone is Asia/Kolkata'
);

select is(
  (select status from crm.organization_profiles where organization_id = :'org_a'),
  'active',
  'a new organization is active'
);

select is(
  (select count(*)::int from crm.roles where organization_id = :'org_a'),
  8,
  'a new organization gets the eight preset roles'
);

select is(
  (select r.key from crm.member_roles mr join crm.roles r on r.id = mr.role_id
   where mr.agent_id = tests.agent_id(:'org_a', 'owner.a@test.local')),
  'owner',
  'the creator holds the Owner role'
);

select is(
  (select count(*)::int from crm.role_permissions rp
   join crm.roles r on r.id = rp.role_id
   where r.organization_id = :'org_a' and r.key = 'owner'),
  (select count(*)::int from crm.permissions),
  'the owner role holds every permission'
);

select is(
  (select pack_key || '@' || version from crm.organization_packs where organization_id = :'org_a'),
  'trading_institute@1',
  'the default pack is applied at creation'
);

select tests.create_org('owner.a@test.local', 'Alpha Trading Academy') as org_a2 \gset

select isnt(
  (select slug from crm.organization_profiles where organization_id = :'org_a2'),
  'alpha-trading-academy',
  'a duplicate name gets a different slug'
);

select tests.create_org('owner.a@test.local', 'शेयर बाज़ार') as org_hi \gset

select is(
  (select left(slug, 3) from crm.organization_profiles where organization_id = :'org_hi'),
  'org',
  'a name with no ASCII letters falls back to an org- slug'
);

-- Profile edits ------------------------------------------------------------------

select tests.as_user('owner.a@test.local');

update crm.organization_profiles
set timezone = 'Europe/London', locale = 'hi', slug = 'alpha'
where organization_id = :'org_a';

select results_eq(
  format('select timezone, locale, slug from crm.organization_profiles where organization_id = %L', :'org_a'),
  $$ values ('Europe/London'::text, 'hi'::text, 'alpha'::text) $$,
  'an owner edits timezone, locale and slug'
);

select throws_ok(
  format($$ update crm.organization_profiles set timezone = 'Mars/Olympus' where organization_id = %L $$, :'org_a'),
  '22023',
  'unknown timezone Mars/Olympus',
  'an unknown timezone is refused'
);

select throws_ok(
  format($$ update crm.organization_profiles set slug = 'Not A Slug!' where organization_id = %L $$, :'org_a'),
  '23514',
  null,
  'a malformed slug is refused'
);

select throws_ok(
  format($$ update crm.organization_profiles set status = 'active' where organization_id = %L $$, :'org_a'),
  '42501',
  null,
  'members cannot write the lifecycle status'
);

-- Isolation ------------------------------------------------------------------------

select tests.as_user('owner.b@test.local');

select is_empty(
  format('select 1 from crm.organization_profiles where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s profile'
);
select is_empty(
  format('select 1 from crm.roles where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s roles'
);
select is_empty(
  format('select 1 from crm.role_permissions where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s role permissions'
);
select is_empty(
  format('select 1 from crm.member_roles where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s member roles'
);
select is_empty(
  format('select 1 from crm.organization_packs where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s pack'
);
select is_empty(
  format('select 1 from crm.organization_pack_items where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s pack items'
);

update crm.organization_profiles set timezone = 'UTC' where organization_id = :'org_a';
update crm.organization_pack_items set value = '"x"' where organization_id = :'org_a';

select tests.as_postgres();
select is(
  (select timezone from crm.organization_profiles where organization_id = :'org_a'),
  'Europe/London',
  'tenant B cannot update tenant A''s profile'
);
select is(
  (select count(*)::int from crm.organization_pack_items where organization_id = :'org_a' and value = '"x"'),
  0,
  'tenant B cannot update tenant A''s pack items'
);

-- Suspension ---------------------------------------------------------------------

select tests.as_user('owner.a@test.local');
select throws_ok(
  format('select crm.suspend_organization(%L)', :'org_a'),
  '42501',
  null,
  'members cannot suspend an organization'
);

select tests.as_service();
select lives_ok(
  format($$ select crm.suspend_organization(%L, 'Payment overdue') $$, :'org_a'),
  'the platform suspends an organization'
);

select tests.as_user('owner.a@test.local');
select is_empty(
  format('select 1 from public.organizations where id = %L', :'org_a'),
  'a suspended organization is invisible to its members'
);
select ok(
  not crm.has_permission(:'org_a', 'conversations.view'),
  'a suspended organization grants no permission'
);
select results_eq(
  'select status, suspended_reason from crm.get_my_organization_statuses()',
  $$ values ('suspended'::text, 'Payment overdue'::text) $$,
  'members can still learn that their organization is suspended'
);

select tests.as_api_key('test-key-alpha');
select tests.as_postgres();
insert into public.api_keys (organization_id, key, role, name)
values (:'org_a', 'test-key-alpha', 'owner', 'test');
select tests.as_api_key('test-key-alpha');
select is_empty(
  format('select 1 from public.organizations where id = %L', :'org_a'),
  'API keys of a suspended organization stop working'
);

select tests.as_service();
select crm.reactivate_organization(:'org_a');
select tests.as_user('owner.a@test.local');
select isnt_empty(
  format('select 1 from public.organizations where id = %L', :'org_a'),
  'reactivation restores access'
);

-- Deletion -------------------------------------------------------------------------

delete from public.organizations where id = :'org_a';
select tests.as_postgres();
select isnt_empty(
  format('select 1 from public.organizations where id = %L', :'org_a'),
  'an owner cannot hard-delete through the API'
);

select tests.as_user('admin.a@test.local');
select throws_ok(
  format('select crm.request_organization_deletion(%L)', :'org_a'),
  '42501',
  'permission organization.delete required',
  'an admin cannot request deletion'
);

select tests.as_user('owner.a@test.local');
select lives_ok(
  format('select crm.request_organization_deletion(%L)', :'org_a'),
  'an owner requests deletion'
);
select is_empty(
  format('select 1 from public.organizations where id = %L', :'org_a'),
  'access stops as soon as deletion is requested'
);

select tests.as_user('admin.a@test.local');
select throws_ok(
  format('select crm.cancel_organization_deletion(%L)', :'org_a'),
  '42501',
  'only an owner can cancel the deletion',
  'an admin cannot cancel the deletion'
);

select tests.as_user('owner.a@test.local');
select lives_ok(
  format('select crm.cancel_organization_deletion(%L)', :'org_a'),
  'an owner cancels the deletion'
);

select crm.request_organization_deletion(:'org_a');
select tests.as_service();
select is(crm.purge_organizations(), 0, 'nothing is purged before the grace period ends');

select tests.as_postgres();
update crm.organization_profiles
set purge_after = now() - interval '1 minute'
where organization_id = :'org_a';

select tests.as_service();
select crm.purge_organizations();
select tests.as_postgres();
select is_empty(
  format('select 1 from public.organizations where id = %L', :'org_a'),
  'the organization is hard-deleted after the grace period'
);

select * from finish();
rollback;
