-- P1-05: the Trading Institute pack is applied at creation, tenants can edit
-- items, and upgrades never overwrite tenant edits.
begin;
\ir _helpers.psql

select plan(20);

select tests.create_user('owner@test.local');
select tests.create_user('viewer@test.local');
select tests.create_org('owner@test.local', 'Epsilon Academy') as org \gset
select tests.add_member(:'org', 'viewer@test.local', 'viewer');

-- v1 at creation ------------------------------------------------------------------

select results_eq(
  format($$ select item_key from crm.organization_pack_items where organization_id = %L and kind = 'pipeline_stage' order by sort_order $$, :'org'),
  $$ values ('lead_inquiring'::text), ('trial_booked'::text), ('paid_student'::text), ('lost'::text) $$,
  'the pipeline stages are Lead Inquiring → Trial Booked → Paid Student, plus Lost'
);
select is(
  (select count(*)::int from crm.organization_pack_items where organization_id = :'org' and kind = 'message_template'),
  8,
  'the template library is applied'
);
select ok(
  (select bool_and(value->'languages' ? 'en' and value->'languages' ? 'hi')
   from crm.organization_pack_items where organization_id = :'org' and kind = 'message_template'),
  'every template has English and Hindi'
);
select ok(
  (select value = 'true'::jsonb from crm.organization_pack_items
   where organization_id = :'org' and kind = 'compliance' and item_key = 'marketing_requires_opt_in'),
  'compliance defaults require opt-in for marketing'
);
select is(
  (select value->>'en' from crm.organization_pack_items
   where organization_id = :'org' and kind = 'terminology' and item_key = 'customer'),
  'Student',
  'the terminology map is applied'
);
select is(
  (select count(*)::int from crm.organization_pack_items where organization_id = :'org' and is_customized),
  0,
  'nothing is customized at first'
);

-- Tenant edits ----------------------------------------------------------------------

select tests.as_user('owner@test.local');
update crm.organization_pack_items
set value = jsonb_set(value, '{name,en}', '"New Enquiry"')
where organization_id = :'org' and kind = 'pipeline_stage' and item_key = 'lead_inquiring';

select ok(
  (select is_customized from crm.organization_pack_items
   where organization_id = :'org' and kind = 'pipeline_stage' and item_key = 'lead_inquiring'),
  'an owner edit marks the item customized'
);

select throws_ok(
  format($$ update crm.organization_pack_items set pack_value = '{}' where organization_id = %L $$, :'org'),
  '42501',
  null,
  'tenants cannot rewrite what the pack says'
);

select tests.as_user('viewer@test.local');
update crm.organization_pack_items
set value = '"hacked"'
where organization_id = :'org' and kind = 'module' and item_key = 'inbox';
select tests.as_postgres();
select is(
  (select value from crm.organization_pack_items
   where organization_id = :'org' and kind = 'module' and item_key = 'inbox'),
  'true'::jsonb,
  'a viewer cannot edit pack items'
);

-- Publish v2: rename two stages, drop "lost", add "demo_attended".
insert into crm.pack_versions (pack_key, version, definition, checksum)
select
  'trading_institute',
  2,
  jsonb_set(
    jsonb_set(definition, '{version}', '2'),
    '{pipeline_stages}',
    (
      select jsonb_agg(
        case s->>'key'
          when 'lead_inquiring' then jsonb_set(s, '{name,en}', '"Inquiry (v2)"')
          when 'trial_booked' then jsonb_set(s, '{name,en}', '"Trial Scheduled"')
          else s
        end
        order by ord
      )
      from jsonb_array_elements(definition->'pipeline_stages') with ordinality t(s, ord)
      where s->>'key' <> 'lost'
    ) || jsonb_build_array(jsonb_build_object(
      'key', 'demo_attended', 'type', 'open',
      'name', jsonb_build_object('en', 'Demo Attended', 'hi', 'डेमो में शामिल')
    ))
  ),
  'test'
from crm.pack_versions where pack_key = 'trading_institute' and version = 1;

-- Upgrade ---------------------------------------------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format('select crm.upgrade_organization_pack(%L)', :'org'),
  '42501',
  'permission organization.manage required',
  'a viewer cannot upgrade the pack'
);

select tests.as_user('owner@test.local');
select is(crm.upgrade_organization_pack(:'org'), 2, 'an owner upgrades to the latest version');

select tests.as_postgres();
select is(
  (select version from crm.organization_packs where organization_id = :'org'),
  2,
  'the organization now runs v2'
);
select is(
  (select value->'name'->>'en' from crm.organization_pack_items
   where organization_id = :'org' and kind = 'pipeline_stage' and item_key = 'lead_inquiring'),
  'New Enquiry',
  'the upgrade keeps the tenant''s edit'
);
select is(
  (select pack_value->'name'->>'en' from crm.organization_pack_items
   where organization_id = :'org' and kind = 'pipeline_stage' and item_key = 'lead_inquiring'),
  'Inquiry (v2)',
  'and records what the pack now says'
);
select is(
  (select value->'name'->>'en' from crm.organization_pack_items
   where organization_id = :'org' and kind = 'pipeline_stage' and item_key = 'trial_booked'),
  'Trial Scheduled',
  'unedited items follow the pack'
);
select ok(
  exists (select 1 from crm.organization_pack_items
          where organization_id = :'org' and kind = 'pipeline_stage' and item_key = 'demo_attended'),
  'new items are added'
);
select ok(
  (select removed_from_pack from crm.organization_pack_items
   where organization_id = :'org' and kind = 'pipeline_stage' and item_key = 'lost'),
  'dropped items are kept and flagged'
);

select throws_ok(
  format('select crm.apply_pack(%L, ''trading_institute'', 1)', :'org'),
  '22023',
  'cannot downgrade pack from 2 to 1',
  'packs do not downgrade'
);

select tests.as_user('owner@test.local');
select crm.reset_pack_item(
  (select id from crm.organization_pack_items
   where organization_id = :'org' and kind = 'pipeline_stage' and item_key = 'lead_inquiring')
);
select is(
  (select value->'name'->>'en' from crm.organization_pack_items
   where organization_id = :'org' and kind = 'pipeline_stage' and item_key = 'lead_inquiring'),
  'Inquiry (v2)',
  'resetting an item brings back the pack''s value'
);

select tests.create_org('owner@test.local', 'Zeta Academy') as org2 \gset
select is(
  (select version from crm.organization_packs where organization_id = :'org2'),
  2,
  'new organizations get the latest version'
);

select * from finish();
rollback;
