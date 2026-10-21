-- P1-09: feature flags and plan entitlements. Tier resolution, overrides,
-- expiry, the kill switch, who may read and write what, module gating on
-- settings, member seat limits, isolation, and audit.
--
-- tests.create_org puts every org on Pro (unlimited) so the rest of the
-- suite never trips a cap by coincidence; tests here explicitly move an org
-- to the tier under test.
begin;
\ir _helpers.psql

select plan(48);

select tests.create_user('owner@test.local');
select tests.create_user('admin@test.local');
select tests.create_user('rep@test.local');
select tests.create_user('other.owner@test.local');
select tests.create_user('fourth@test.local');
select tests.create_user('fifth@test.local');
select tests.create_user('sixth@test.local');

select tests.create_org('owner@test.local', 'India Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset
select tests.add_member(:'org', 'admin@test.local', 'admin') as admin_agent \gset
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep \gset

-- Catalog ----------------------------------------------------------------------------

select is((select count(*)::int from crm.features), 11, 'the catalog has the eleven modules');
select is(
  (select label from crm.features where key = 'ai_agents'),
  'AI agents',
  'labels match the settings catalog'
);

-- Tier resolution ----------------------------------------------------------------------

select tests.as_postgres();
insert into billing.subscriptions (organization_id, tier_id) values (:'org', 'free')
  on conflict (organization_id) do update set tier_id = excluded.tier_id;

select tests.as_user('owner@test.local');
select ok(crm.has_feature(:'org', 'inbox'), 'Free includes inbox');
select ok(not crm.has_feature(:'org', 'broadcasts'), 'Free does not include broadcasts');
select ok(not crm.has_feature(:'org', 'ai_agents'), 'Free does not include AI agents');

select tests.as_postgres();
insert into billing.subscriptions (organization_id, tier_id) values (:'org', 'starter')
  on conflict (organization_id) do update set tier_id = excluded.tier_id;

select tests.as_user('owner@test.local');
select ok(crm.has_feature(:'org', 'broadcasts'), 'Starter includes broadcasts');
select ok(crm.has_feature(:'org', 'telegram'), 'Starter includes telegram');
select ok(not crm.has_feature(:'org', 'ai_agents'), 'Starter does not include AI agents');

select tests.as_postgres();
insert into billing.subscriptions (organization_id, tier_id) values (:'org', 'pro')
  on conflict (organization_id) do update set tier_id = excluded.tier_id;

select tests.as_user('owner@test.local');
select ok(crm.has_feature(:'org', 'ai_agents'), 'Pro includes AI agents');
select ok(crm.has_feature(:'org', 'news_digest'), 'Pro includes news digest');

-- No subscription at all: no billing, so unrestricted.
select tests.as_postgres();
delete from billing.subscriptions where organization_id = :'org';
select tests.as_user('owner@test.local');
select ok(crm.has_feature(:'org', 'ai_agents'), 'with no subscription at all, every feature is available');
select tests.as_postgres();
insert into billing.subscriptions (organization_id, tier_id) values (:'org', 'free')
  on conflict (organization_id) do update set tier_id = excluded.tier_id;

-- Overrides ----------------------------------------------------------------------------

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.set_organization_feature(%L, 'ai_agents', true) $$, :'org'),
  '42501', 'permission denied for function set_organization_feature', 'a member cannot even call the platform-only function'
);

select tests.as_service();
select lives_ok(
  format($$ select crm.set_organization_feature(%L, 'ai_agents', true, 'pilot beta') $$, :'org'),
  'the platform grants a beta override'
);
select tests.as_user('owner@test.local');
select ok(crm.has_feature(:'org', 'ai_agents'), 'the override beats the Free tier');

select tests.as_service();
select lives_ok(
  format($$ select crm.set_organization_feature(%L, 'inbox', false, 'collections hold') $$, :'org'),
  'the platform can also block a feature the tier includes'
);
select tests.as_user('owner@test.local');
select ok(not crm.has_feature(:'org', 'inbox'), 'the block beats the tier too');

-- Expiry.
select tests.as_service();
select crm.set_organization_feature(:'org', 'telegram', true, 'trial', now() - interval '1 minute');
select tests.as_user('owner@test.local');
select ok(not crm.has_feature(:'org', 'telegram'), 'an expired override no longer applies');

select tests.as_service();
select crm.clear_organization_feature(:'org', 'inbox');
select tests.as_user('owner@test.local');
select ok(crm.has_feature(:'org', 'inbox'), 'clearing an override returns to the tier default');

-- Kill switch --------------------------------------------------------------------------

select tests.as_user('rep@test.local');
select throws_ok(
  $$ select crm.set_feature_kill_switch('ai_agents', true) $$,
  '42501', 'permission denied for function set_feature_kill_switch', 'a member cannot even call the kill switch'
);

select tests.as_service();
select crm.set_feature_kill_switch('ai_agents', true);
select tests.as_user('owner@test.local');
select ok(
  not crm.has_feature(:'org', 'ai_agents'),
  'the kill switch beats even an explicit override that grants it'
);

select tests.as_service();
select crm.set_feature_kill_switch('ai_agents', false);
select throws_ok(
  $$ select crm.set_feature_kill_switch('no_such_feature', true) $$,
  '22023', 'unknown feature no_such_feature', 'the kill switch refuses an unknown key too'
);

-- require_feature and unknown keys ------------------------------------------------------

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.require_feature(%L, 'broadcasts') $$, :'org'),
  '42501', 'your plan does not include Broadcasts', 'require_feature names the feature in its error'
);
select lives_ok(
  format($$ select crm.require_feature(%L, 'inbox') $$, :'org'),
  'require_feature passes silently when the plan includes it'
);
select throws_ok(
  format($$ select crm.has_feature(%L, 'no_such_feature') $$, :'org'),
  '22023', 'unknown feature no_such_feature', 'has_feature refuses an unknown key'
);

-- get_features ---------------------------------------------------------------------------

select results_eq(
  format($$ select enabled, source from crm.get_features(%L) where key = 'inbox' $$, :'org'),
  $$ values (true::boolean, 'tier'::text) $$,
  'get_features reports the tier as the source for an ordinary included feature'
);
select tests.as_service();
select crm.set_organization_feature(:'org', 'webinars', true, 'pilot');
select tests.as_user('owner@test.local');
select results_eq(
  format($$ select enabled, source, override_reason from crm.get_features(%L) where key = 'webinars' $$, :'org'),
  $$ values (true::boolean, 'override'::text, 'pilot'::text) $$,
  'and an override, with its reason'
);
select is(
  (select unlocks_at_tier from crm.get_features(:'org') where key = 'broadcasts'),
  'starter',
  'a feature not in the current plan says which tier would include it'
);
select is(
  (select unlocks_at_tier from crm.get_features(:'org') where key = 'inbox'),
  'free',
  'and the lowest tier, for one every tier includes'
);

-- Who may read and write ----------------------------------------------------------------

select tests.as_user('other.owner@test.local');
select is_empty(
  format('select 1 from crm.organization_features where organization_id = %L', :'org'),
  'another tenant cannot read our overrides'
);
select throws_ok(
  format($$ select crm.has_feature(%L, 'inbox') $$, :'org'),
  '42501', 'organization not found', 'or resolve our features at all'
);
select throws_ok(
  format($$ select crm.set_organization_feature(%L, 'inbox', false) $$, :'org'),
  '42501', 'permission denied for function set_organization_feature', 'and cannot grant themselves an override into our organization either'
);

select tests.as_postgres();
insert into public.api_keys (organization_id, key, role, name) values (:'org', 'feature-key', 'member', 'k');
select tests.as_api_key('feature-key');
select ok(crm.has_feature(:'org', 'inbox'), 'an API key integration can resolve features for its own org');

-- Module gating on settings (crm.set_setting, P1-04) ------------------------------------

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.set_setting(%L, 'modules.broadcasts', 'true') $$, :'org'),
  '42501', 'your plan does not include this module', 'Free cannot turn on a module outside its plan'
);
select lives_ok(
  format($$ select crm.set_setting(%L, 'modules.inbox', 'false') $$, :'org'),
  'but turning one off never needs an entitlement'
);
select lives_ok(
  format($$ select crm.reset_setting(%L, 'modules.inbox') $$, :'org'),
  'and resetting is unaffected too'
);

select tests.as_service();
select crm.set_organization_feature(:'org', 'broadcasts', true, 'pilot');
select tests.as_user('owner@test.local');
select lives_ok(
  format($$ select crm.set_setting(%L, 'modules.broadcasts', 'true') $$, :'org'),
  'once the plan (here, via an override) includes it, the switch turns on'
);

-- Member seat limits ---------------------------------------------------------------------

select tests.as_postgres();
insert into billing.subscriptions (organization_id, tier_id) values (:'org', 'free')
  on conflict (organization_id) do update set tier_id = excluded.tier_id;
-- Usage already reflects the owner + admin + rep created above (3 of 3).
select is(
  (select quantity from billing.usage
   where organization_id = :'org' and product_id = 'members' and interval = 'lifetime'),
  3::numeric,
  'usage already counts the three active members'
);

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.invite_member(%L, 'fourth@test.local', 'viewer') $$, :'org'),
  'PT402', 'Usage limit reached for members', 'inviting past the seat cap is refused at invite time already'
);

-- Deactivating frees a seat; a direct insert at the cap (seed/migration-style,
-- bypassing invite_member's early check) is still stopped by the trigger.
select lives_ok(format('select crm.deactivate_member(%L)', :'rep'), 'the owner deactivates the sales rep');

select tests.as_postgres();
select lives_ok(
  format($$
    insert into public.agents (organization_id, user_id, name, role)
    select %L, id, 'Fourth', 'member' from auth.users where email = 'fourth@test.local'
  $$, :'org'),
  'with a seat free, a new active member is accepted'
);
select is(
  (select quantity from billing.usage
   where organization_id = :'org' and product_id = 'members' and interval = 'lifetime'),
  3::numeric,
  'usage reflects the deactivation and the new member: still three'
);

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.invite_member(%L, 'fifth@test.local', 'viewer') $$, :'org'),
  'PT402', 'Usage limit reached for members', 'full again: a fifth invite is refused'
);
select tests.as_postgres();
select throws_ok(
  format($$
    insert into public.agents (organization_id, user_id, name, role)
    select %L, id, 'Fifth', 'member' from auth.users where email = 'fifth@test.local'
  $$, :'org'),
  'PT402', 'Usage limit reached for members', 'and the trigger itself refuses a direct insert too'
);

-- Revival re-checks the cap: re-inviting the deactivated rep while full fails;
-- freeing a seat lets it through.
select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.invite_member(%L, 'rep@test.local', 'viewer') $$, :'org'),
  'PT402', 'Usage limit reached for members', 'reinviting a deactivated member while full is refused too'
);
select crm.deactivate_member(
  (select id from public.agents where organization_id = :'org' and name = 'Fourth')
);
select crm.invite_member(:'org', 'rep@test.local', 'viewer') as revive_invitation \gset
select tests.as_user('rep@test.local');
select lives_ok(
  format('select public.accept_invitation(%L)', :'revive_invitation'),
  'with a seat free, the revival is accepted and re-checked, not waved through'
);

-- Pro is unlimited: no tiers_products row for 'members' at all.
select tests.as_postgres();
insert into billing.subscriptions (organization_id, tier_id) values (:'org', 'pro')
  on conflict (organization_id) do update set tier_id = excluded.tier_id;
select tests.as_user('owner@test.local');
select lives_ok(
  format($$ select crm.invite_member(%L, 'sixth@test.local', 'viewer') $$, :'org'),
  'Pro has no seat cap'
);

-- Isolation: another organization's seats are unaffected.
select tests.as_postgres();
insert into billing.subscriptions (organization_id, tier_id) values (:'other', 'free')
  on conflict (organization_id) do update set tier_id = excluded.tier_id;
select tests.as_user('other.owner@test.local');
select is(
  (select quantity from billing.usage
   where organization_id = :'other' and product_id = 'members' and interval = 'lifetime'),
  1::numeric,
  'a different organization''s seat usage is its own (just its owner)'
);

-- Audit ------------------------------------------------------------------------------

select tests.as_postgres();
select results_eq(
  format($$
    select action, target_id, details->>'reason' from crm.audit_log
    where organization_id = %L and action like 'feature.%%' order by id
  $$, :'org'),
  $$ values
    ('feature.override_set'::text, 'ai_agents'::text, 'pilot beta'::text),
    ('feature.override_set', 'inbox', 'collections hold'),
    ('feature.override_set', 'telegram', 'trial'),
    ('feature.override_cleared', 'inbox', null::text),
    ('feature.override_set', 'webinars', 'pilot'),
    ('feature.override_set', 'broadcasts', 'pilot')
  $$,
  'every override grant and clear is audited; the kill switch (platform-wide, no single org) is not'
);

select * from finish();
rollback;
