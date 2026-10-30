-- P1-04: the settings engine and teams. Value validation, the layer order
-- (user → team → organization → pack → platform), locked compliance
-- minimums, who may read and change what, tenant isolation, team conflicts,
-- and audit entries.
begin;
\ir _helpers.psql

select plan(64);

select tests.create_user('owner@test.local');
select tests.create_user('admin@test.local');
select tests.create_user('rep@test.local');
select tests.create_user('viewer@test.local');
select tests.create_user('other.owner@test.local');

select tests.create_org('owner@test.local', 'Foxtrot Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset
select tests.add_member(:'org', 'admin@test.local', 'admin') as admin_agent \gset
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep \gset
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer \gset

-- A setting that allows every layer, for testing them (the first catalog
-- has organization-level settings only).
insert into crm.setting_definitions (key, category, label, schema, platform_default, scopes)
values ('test.layered', 'test', 'Layered', '{"type": "integer", "minimum": 1, "maximum": 100}', '5',
        '{tenant,team,user}');

-- Catalog ----------------------------------------------------------------------------

select is(
  (select count(*)::int from crm.setting_definitions where key not like 'test.%'),
  37,
  'the first catalog has 37 settings (incl. the P3-08 trial-booking settings)'
);
select is(
  (select count(*)::int from crm.setting_definitions
   where crm.validate_setting_value(schema, platform_default) is not null),
  0,
  'every platform default passes its own schema'
);
select results_eq(
  $$ select key from crm.setting_definitions where is_locked order by key $$,
  $$ values ('approval.ai_content'::text), ('approval.news_content'), ('marketing.requires_opt_in') $$,
  'the compliance minimums are locked'
);

-- Validation -------------------------------------------------------------------------

select ok(
  crm.validate_setting_value(
    (select schema from crm.setting_definitions where key = 'messaging.quiet_hours'),
    '{"start": "22:00", "end": "07:30"}'
  ) is null,
  'a valid value passes'
);
select is(
  crm.validate_setting_value(
    (select schema from crm.setting_definitions where key = 'messaging.quiet_hours'),
    '{"start": "22:00"}'
  ),
  'value.end is required',
  'a missing field is named'
);
select is(
  crm.validate_setting_value(
    (select schema from crm.setting_definitions where key = 'messaging.quiet_hours'),
    '{"start": "22:00", "end": "25:00"}'
  ),
  'value.end has the wrong format',
  'a pattern is enforced'
);
select is(
  crm.validate_setting_value(
    (select schema from crm.setting_definitions where key = 'messaging.quiet_hours'),
    '{"start": "22:00", "end": "07:00", "extra": 1}'
  ),
  'value.extra is not allowed',
  'unknown fields are refused'
);
select is(
  crm.validate_setting_value(
    (select schema from crm.setting_definitions where key = 'marketing.frequency_cap'),
    '{"max_messages": 2.5, "period_days": 7}'
  ),
  'value.max_messages must be a whole number',
  'integers must be whole'
);
select is(
  crm.validate_setting_value(
    (select schema from crm.setting_definitions where key = 'marketing.frequency_cap'),
    '{"max_messages": 50, "period_days": 7}'
  ),
  'value.max_messages must be at most 20',
  'bounds are enforced'
);
select is(
  crm.validate_setting_value(
    (select schema from crm.setting_definitions where key = 'compliance.opt_out_keywords'),
    '["STOP", "BAS"]'
  ),
  'value must include UNSUBSCRIBE',
  'the mandatory opt-out keywords cannot be removed'
);
select ok(
  crm.validate_setting_value(
    (select schema from crm.setting_definitions where key = 'compliance.opt_out_keywords'),
    '["stop", "Unsubscribe", "BAS"]'
  ) is null,
  'mandatory keywords match in any case, and tenants may add their own'
);
select is(
  crm.validate_setting_value('{"type": "boolean"}', '"yes"'),
  'value must be a boolean',
  'types are enforced'
);

-- Branding (P1-11) ------------------------------------------------------------------

select ok(
  crm.validate_setting_value(
    (select schema from crm.setting_definitions where key = 'branding.logo_url'),
    '"https://example.com/logo.png"'
  ) is null,
  'a valid logo URL passes'
);
select ok(
  crm.validate_setting_value(
    (select schema from crm.setting_definitions where key = 'branding.logo_url'),
    '"not-a-url"'
  ) is not null,
  'a logo value without a scheme is refused'
);
select ok(
  crm.validate_setting_value(
    (select schema from crm.setting_definitions where key = 'branding.logo_url'),
    '""'
  ) is null,
  'an empty logo URL is valid (means unset)'
);
select ok(
  crm.validate_setting_value(
    (select schema from crm.setting_definitions where key = 'branding.primary_color'),
    '"blue"'
  ) is not null,
  'a non-hex color is refused'
);

select tests.as_user('owner@test.local');
select results_eq(
  format($$ select value, source from crm.get_settings(%L) where key = 'branding.primary_color' $$, :'org'),
  $$ values (to_jsonb(''::text), 'platform'::text) $$,
  'branding defaults to unset (platform default), no pack item backs it'
);
select lives_ok(
  format($$ select crm.set_setting(%L, 'branding.primary_color', '"#2563eb"') $$, :'org'),
  'the owner sets a primary color'
);
select results_eq(
  format($$ select value, source from crm.get_settings(%L) where key = 'branding.primary_color' $$, :'org'),
  $$ values ('"#2563eb"'::jsonb, 'tenant'::text) $$,
  'the organization value is read back'
);
select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.set_setting(%L, 'branding.logo_url', '"https://example.com/l.png"') $$, :'org'),
  '42501',
  null,
  'a sales rep cannot change branding (needs organization.manage)'
);

-- Layers: pack and organization -----------------------------------------------------

select tests.as_user('owner@test.local');
select results_eq(
  format($$ select value, source from crm.get_settings(%L) where key = 'messaging.quiet_hours' $$, :'org'),
  $$ values ('{"start": "21:00", "end": "09:00"}'::jsonb, 'pack'::text) $$,
  'quiet hours start from the pack'
);
select results_eq(
  format($$ select value, source from crm.get_settings(%L) where key = 'modules.telegram' $$, :'org'),
  $$ values ('true'::jsonb, 'pack'::text) $$,
  'the pack turns modules on that the platform leaves off'
);
select is(
  crm.get_setting(:'org', 'approval.broadcasts'),
  'true'::jsonb,
  'a value inside a pack item (require_approval.broadcast) is read by path'
);
select results_eq(
  format($$ select value, source from crm.get_settings(%L) where key = 'compliance.extra_banned_phrases' $$, :'org'),
  $$ values ('[]'::jsonb, 'platform'::text) $$,
  'a setting without a pack item starts from the platform default'
);

select lives_ok(
  format($$ select crm.set_setting(%L, 'messaging.quiet_hours', '{"start": "22:00", "end": "08:00"}') $$, :'org'),
  'the owner sets quiet hours'
);
select results_eq(
  format($$ select value, source, tenant_value is not null from crm.get_settings(%L) where key = 'messaging.quiet_hours' $$, :'org'),
  $$ values ('{"start": "22:00", "end": "08:00"}'::jsonb, 'tenant'::text, true) $$,
  'the organization value wins over the pack'
);

-- A new pack version changes the pack layer only.
select tests.as_postgres();
update crm.organization_pack_items
set pack_value = '{"start": "20:00", "end": "10:00"}'
where organization_id = :'org' and kind = 'compliance' and item_key = 'quiet_hours';

select tests.as_user('owner@test.local');
select is(
  crm.get_setting(:'org', 'messaging.quiet_hours'),
  '{"start": "22:00", "end": "08:00"}'::jsonb,
  'a pack change never overwrites the organization''s choice'
);
select crm.reset_setting(:'org', 'messaging.quiet_hours');
select is(
  crm.get_setting(:'org', 'messaging.quiet_hours'),
  '{"start": "20:00", "end": "10:00"}'::jsonb,
  'after a reset the (new) pack value applies'
);

-- A pack value that breaks a platform minimum is ignored.
select tests.as_postgres();
update crm.organization_pack_items
set pack_value = '["STOP"]'
where organization_id = :'org' and kind = 'compliance' and item_key = 'opt_out_keywords';
select tests.as_user('owner@test.local');
select results_eq(
  format($$ select value, source from crm.get_settings(%L) where key = 'compliance.opt_out_keywords' $$, :'org'),
  $$ values ('["STOP", "UNSUBSCRIBE"]'::jsonb, 'platform'::text) $$,
  'an invalid pack value falls back to the platform default'
);

-- Locks and rules --------------------------------------------------------------------

select is(crm.get_setting(:'org', 'marketing.requires_opt_in'), 'true'::jsonb, 'opt-in is required');
select throws_ok(
  format($$ select crm.set_setting(%L, 'marketing.requires_opt_in', 'false') $$, :'org'),
  '42501',
  'this setting is set by the platform and cannot be changed',
  'nobody can turn off the opt-in requirement, not even the owner'
);
select throws_ok(
  format($$ select crm.set_setting(%L, 'approval.ai_content', 'false') $$, :'org'),
  '42501',
  'this setting is set by the platform and cannot be changed',
  'AI content always needs approval'
);
select throws_ok(
  format($$ select crm.set_setting(%L, 'compliance.opt_out_keywords', '["BAS", "UNSUBSCRIBE"]') $$, :'org'),
  '22023',
  'value must include STOP',
  'STOP cannot be removed from the opt-out keywords'
);
select lives_ok(
  format($$ select crm.set_setting(%L, 'compliance.opt_out_keywords', '["STOP", "UNSUBSCRIBE", "रोकें"]') $$, :'org'),
  'tenants can add their own opt-out keywords'
);
select throws_ok(
  format($$ select crm.set_setting(%L, 'messaging.quiet_hours', '{"start": "22:00", "end": "08:00"}', 'user') $$, :'org'),
  '22023',
  'this setting cannot be set per user',
  'a setting is only set at the scopes it allows'
);
select throws_ok(
  format($$ select crm.set_setting(%L, 'no.such_setting', 'true') $$, :'org'),
  '22023',
  'unknown setting no.such_setting',
  'unknown settings are refused'
);
select results_eq(
  format($$ select key, can_edit from crm.get_settings(%L) where key in ('messaging.quiet_hours', 'marketing.requires_opt_in') order by key $$, :'org'),
  $$ values ('marketing.requires_opt_in'::text, false), ('messaging.quiet_hours', true) $$,
  'the screen knows what the owner can change'
);

-- Who may change and read ------------------------------------------------------------

select tests.as_user('admin@test.local');
select lives_ok(
  format($$ select crm.set_setting(%L, 'modules.news_digest', 'true') $$, :'org'),
  'an admin (organization.manage) changes settings'
);

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.set_setting(%L, 'modules.news_digest', 'false') $$, :'org'),
  '42501',
  'permission organization.manage required',
  'a sales rep cannot change organization settings'
);
select is(
  crm.get_setting(:'org', 'modules.news_digest'),
  'true'::jsonb,
  'but every member reads them'
);
select is(
  (select bool_or(can_edit) from crm.get_settings(:'org')),
  false,
  'and the screen shows a sales rep nothing to change'
);
select throws_ok(
  format($$ insert into crm.setting_values (organization_id, setting_key, scope, value) values (%L, 'modules.inbox', 'tenant', 'false') $$, :'org'),
  '42501',
  null,
  'nobody writes setting values directly'
);

select tests.as_user('other.owner@test.local');
select throws_ok(
  format($$ select crm.get_setting(%L, 'modules.inbox') $$, :'org'),
  '42501',
  'organization not found',
  'another tenant cannot read our settings'
);
select throws_ok(
  format($$ select crm.set_setting(%L, 'modules.inbox', 'false') $$, :'org'),
  '42501',
  'organization not found',
  'or change them'
);
select is_empty(
  format('select 1 from crm.setting_values where organization_id = %L', :'org'),
  'or see our setting rows'
);

select tests.as_postgres();
insert into public.api_keys (organization_id, key, role, name) values (:'org', 'settings-key', 'member', 'k');
select tests.as_api_key('settings-key');
select is(
  crm.get_setting(:'org', 'modules.news_digest'),
  'true'::jsonb,
  'an API key reads settings (integrations need them)'
);
select throws_ok(
  format($$ select crm.set_setting(%L, 'modules.inbox', 'false') $$, :'org'),
  '42501',
  null,
  'but cannot change them'
);

-- Teams ------------------------------------------------------------------------------

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.create_team(%L, 'Rogue') $$, :'org'),
  '42501',
  'permission members.manage required',
  'a sales rep cannot create teams'
);

select tests.as_user('owner@test.local');
select crm.create_team(:'org', ' North ') as north \gset
select crm.create_team(:'org', 'South') as south \gset
select crm.set_team_member(:'north', :'rep', true);
select is(
  (select name from crm.teams where id = :'north'),
  'North',
  'the owner creates a team (name trimmed) and adds a member'
);
select throws_ok(
  format($$ select crm.set_team_member(%L, tests.agent_id(%L, 'other.owner@test.local'), true) $$, :'north', :'other'),
  '22023',
  'member not found',
  'only members of the team''s organization can join it'
);

-- Layers: team and user --------------------------------------------------------------

select crm.set_setting(:'org', 'test.layered', '10');
select crm.set_setting(:'org', 'test.layered', '20', 'team', :'north');

select tests.as_user('rep@test.local');
select is(crm.get_setting(:'org', 'test.layered'), '20'::jsonb, 'a team value wins over the organization value');
select lives_ok(
  format($$ select crm.set_setting(%L, 'test.layered', '30', 'user') $$, :'org'),
  'a member sets their own value without any permission'
);
select is(crm.get_setting(:'org', 'test.layered'), '30'::jsonb, 'and their own value wins over the team''s');
select throws_ok(
  format($$ select crm.set_setting(%L, 'test.layered', '1', 'user', %L) $$, :'org', :'viewer'),
  '42501',
  'permission organization.manage required',
  'but cannot set someone else''s'
);
select throws_ok(
  format($$ select crm.get_setting(%L, 'test.layered', %L) $$, :'org', :'viewer'),
  '42501',
  'only the platform can read settings for another member',
  'or read settings as someone else'
);

select tests.as_user('viewer@test.local');
select is_empty(
  format($$ select 1 from crm.setting_values where organization_id = %L and scope = 'user' $$, :'org'),
  'members do not see each other''s own values'
);
select is(crm.get_setting(:'org', 'test.layered'), '10'::jsonb, 'a member outside the team gets the organization value');

select tests.as_service();
select is(
  crm.get_setting(:'org', 'test.layered', :'rep'),
  '30'::jsonb,
  'the platform resolves for a given member (the send path)'
);

-- Conflicting teams: the organization value applies, and the screen flags it.
select tests.as_user('owner@test.local');
select crm.set_setting(:'org', 'test.layered', '40', 'team', :'south');
select crm.set_team_member(:'south', :'rep', true);
select crm.reset_setting(:'org', 'test.layered', 'user', :'rep');

select tests.as_user('rep@test.local');
select results_eq(
  format($$ select value, source, team_conflict from crm.get_settings(%L) where key = 'test.layered' $$, :'org'),
  $$ values ('10'::jsonb, 'tenant'::text, true) $$,
  'two teams with different values: the organization value applies, flagged'
);

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.set_setting(%L, 'test.layered', '1', 'team', %L) $$, :'other',
         (select id from crm.teams where organization_id = :'org' limit 1)),
  '42501',
  'organization not found',
  'teams of one organization cannot carry another''s settings'
);
select crm.delete_team(:'south');
select is(
  (select count(*)::int from crm.setting_values where team_id = :'south'),
  0,
  'deleting a team removes its values'
);

-- Pack items are not a side door -----------------------------------------------------

update crm.organization_pack_items
set value = '{"start": "23:00", "end": "06:00"}'
where organization_id = :'org' and kind = 'compliance' and item_key = 'quiet_hours';
select tests.as_postgres();
select isnt(
  (select value from crm.organization_pack_items
   where organization_id = :'org' and kind = 'compliance' and item_key = 'quiet_hours'),
  '{"start": "23:00", "end": "06:00"}'::jsonb,
  'compliance pack items cannot be edited directly (settings are the way)'
);

-- Audit ------------------------------------------------------------------------------

select results_eq(
  format($$
    select action, details->>'scope', details->'before', details->'after'
    from crm.audit_log
    where organization_id = %L and action like 'setting.%%' and target_id = 'messaging.quiet_hours'
    order by id
  $$, :'org'),
  $$ values
    ('setting.changed'::text, 'tenant'::text, null::jsonb, '{"start": "22:00", "end": "08:00"}'::jsonb),
    ('setting.reset', 'tenant', '{"start": "22:00", "end": "08:00"}'::jsonb, null)
  $$,
  'setting changes and resets are audited with before and after'
);
select results_eq(
  format($$
    select action from crm.audit_log
    where organization_id = %L and action like 'team.%%' order by id
  $$, :'org'),
  $$ values ('team.created'::text), ('team.created'), ('team.member_added'),
            ('team.member_added'), ('team.deleted') $$,
  'team changes are audited'
);

select * from finish();
rollback;
