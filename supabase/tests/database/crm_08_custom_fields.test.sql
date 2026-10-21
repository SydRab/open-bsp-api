-- P1-06: person-level contacts and custom fields. One person per address
-- across the organization's numbers; field definitions (validation, options
-- added/archived never removed, archiving, permissions, audit); values (types,
-- options, required on form saves only, archived fields/options); visibility
-- (contacts.view, number scope, other tenants); filters; template formatting.
begin;
\ir _helpers.psql

select plan(54);

select tests.create_user('owner@test.local');
select tests.create_user('rep@test.local');
select tests.create_user('viewer@test.local');
select tests.create_user('other.owner@test.local');

select tests.create_org('owner@test.local', 'Hotel Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep \gset
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer \gset

insert into public.organizations_addresses (organization_id, service, address, status) values
  (:'org', 'whatsapp', '1001', 'connected'),
  (:'org', 'whatsapp', '1002', 'connected');

-- Asha writes to both numbers; Ravi only to the second.
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra) values
  (:'org', '1001', 'whatsapp', '919800000001', '{"name": "Asha"}'),
  (:'org', '1002', 'whatsapp', '919800000001', '{"name": "Asha K"}'),
  (:'org', '1002', 'whatsapp', '919800000002', '{"name": "Ravi"}');

select contact_id as asha from crm.contact_addresses
where organization_id = :'org' and address = '919800000001' \gset
select contact_id as ravi from crm.contact_addresses
where organization_id = :'org' and address = '919800000002' \gset
select value->'label'->>'en' as city_label from crm.organization_pack_items
where organization_id = :'org' and kind = 'custom_field' and item_key = 'city' \gset
select id as city_field from crm.organization_pack_items
where organization_id = :'org' and kind = 'custom_field' and item_key = 'city' \gset
select id as experience_field from crm.organization_pack_items
where organization_id = :'org' and kind = 'custom_field' and item_key = 'experience_level' \gset

-- Person-level contacts -------------------------------------------------------------

select is(
  (select count(*)::int from crm.contacts where organization_id = :'org'),
  2,
  'one person per address, whichever of the organization''s numbers they wrote to'
);
select is(
  (select display_name from crm.contacts where id = :'asha'),
  'Asha',
  'the person is named from the first contact row'
);
select is(
  (select count(*)::int from crm.contacts where organization_id = :'other'),
  0,
  'contacts belong to their own organization'
);

-- Definitions --------------------------------------------------------------------------

select is(
  (select count(*)::int from crm.organization_pack_items
   where organization_id = :'org' and kind = 'custom_field' and value->>'entity' = 'contact'),
  7,
  'the pack brings its seven contact fields'
);

select tests.as_user('owner@test.local');
select crm.create_custom_field(:'org', 'contact', 'age', 'number', '{"en": "Age", "hi": "उम्र"}') as age_field \gset
select crm.create_custom_field(:'org', 'contact', 'demo_done', 'boolean', '{"en": "Demo done"}') as demo_field \gset
select results_eq(
  format($$ select value->>'type', pack_value is null from crm.organization_pack_items where id = %L $$, :'age_field'),
  $$ values ('number'::text, true) $$,
  'the owner adds a field of their own (no pack value)'
);
select throws_ok(
  format($$ select crm.create_custom_field(%L, 'contact', 'age', 'text', '{"en": "Age again"}') $$, :'org'),
  '23505', 'a field with the key age already exists', 'keys are unique'
);
select throws_ok(
  format($$ select crm.create_custom_field(%L, 'contact', 'Bad Key', 'text', '{"en": "x"}') $$, :'org'),
  '22023', 'field.key has the wrong format', 'keys are lowercase identifiers'
);
select throws_ok(
  format($$ select crm.create_custom_field(%L, 'contact', 'level', 'select', '{"en": "Level"}') $$, :'org'),
  '22023', 'a choice field needs at least one option', 'choice fields need options'
);
select throws_ok(
  format($$ select crm.create_custom_field(%L, 'contact', 'nick', 'text', '{"en": "Nick"}', '[{"value": "a", "label": {"en": "A"}}]') $$, :'org'),
  '22023', 'only choice fields have options', 'other fields have none'
);
select throws_ok(
  format($$ select crm.create_custom_field(%L, 'contact', 'level', 'select', '{"en": "Level"}', '[{"value": "a", "label": {"en": "A"}}, {"value": "a", "label": {"en": "B"}}]') $$, :'org'),
  '22023', 'option values must be unique', 'option values are unique'
);
select throws_ok(
  format($$ select crm.create_custom_field(%L, 'contact', 'level', 'rating', '{"en": "Level"}') $$, :'org'),
  '22023', 'field.type is not one of the allowed values', 'unknown types are refused'
);

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.create_custom_field(%L, 'contact', 'mine', 'text', '{"en": "Mine"}') $$, :'org'),
  '42501', 'permission organization.manage required', 'a sales rep cannot define fields'
);
update crm.organization_pack_items set value = value || '{"type": "number"}'
where id = :'city_field';
select tests.as_user('owner@test.local');
update crm.organization_pack_items set value = value || '{"type": "number"}'
where id = :'city_field';
select tests.as_postgres();
select is(
  (select value->>'type' from crm.organization_pack_items where id = :'city_field'),
  'text',
  'definitions cannot be edited directly, not even by the owner (functions only)'
);

-- Options: added and archived, never removed.
select tests.as_user('owner@test.local');
select lives_ok(
  format($$ select crm.update_custom_field(%L,
    (select value->'label' from crm.organization_pack_items where id = %1$L),
    (select jsonb_agg(case when o->>'value' = 'beginner' then o || '{"archived": true}' else o end)
       || '[{"value": "professional", "label": {"en": "Professional"}}]'
     from jsonb_array_elements((select value->'options' from crm.organization_pack_items where id = %1$L)) o),
    false) $$, :'experience_field'),
  'the owner adds an option and archives another'
);
select throws_ok(
  format($$ select crm.update_custom_field(%L, '{"en": "Experience"}', '[{"value": "professional", "label": {"en": "Pro"}}]', false) $$, :'experience_field'),
  '22023', 'options cannot be removed; archive them instead', 'options in use are never removed'
);
select is(
  (select is_customized from crm.organization_pack_items where id = :'experience_field'),
  true,
  'editing a pack field marks it customized, so pack upgrades leave it alone'
);

-- Values -------------------------------------------------------------------------------

select tests.as_user('rep@test.local');
select is(
  crm.set_contact_fields(:'asha', '{"experience_level": "some_experience", "city": "Pune", "preferred_market": ["equity", "futures_options"], "capital_range": "between_2l_10l"}'),
  '{"experience_level": "some_experience", "city": "Pune", "preferred_market": ["equity", "futures_options"], "capital_range": "between_2l_10l"}'::jsonb,
  'a sales rep saves a contact''s fields'
);
select throws_ok(
  format($$ select crm.set_contact_fields(%L, '{"experience_level": "guru"}') $$, :'asha'),
  '22023', 'experience_level: unknown option guru', 'unknown options are refused'
);
select throws_ok(
  format($$ select crm.set_contact_fields(%L, '{"experience_level": "beginner"}') $$, :'asha'),
  '22023', 'experience_level: option beginner is archived', 'archived options cannot be newly chosen'
);
select throws_ok(
  format($$ select crm.set_contact_fields(%L, '{"age": "twenty"}') $$, :'asha'),
  '22023', 'age must be a number', 'numbers are numbers'
);
select throws_ok(
  format($$ select crm.set_contact_fields(%L, '{"preferred_market": ["equity", "equity"]}') $$, :'asha'),
  '22023', 'preferred_market lists an option twice', 'no duplicate choices'
);
select throws_ok(
  format($$ select crm.set_contact_fields(%L, '{"nope": 1}') $$, :'asha'),
  '22023', 'unknown field nope', 'unknown fields are refused'
);
select lives_ok(
  format($$ select crm.set_contact_fields(%L, '{"age": 31, "demo_done": true}') $$, :'asha'),
  'numbers and yes/no values save'
);
select is(
  crm.set_contact_fields(:'asha', '{"demo_done": null}') ? 'demo_done',
  false,
  'null clears a field'
);

-- An archived option already stored stays when other fields change.
select tests.as_postgres();
update crm.contacts set custom_fields = custom_fields || '{"learning_goal": "part_time"}' where id = :'asha';
select tests.as_user('owner@test.local');
select crm.update_custom_field(:'experience_field',
  (select value->'label' from crm.organization_pack_items where id = :'experience_field'),
  (select jsonb_agg(case when o->>'value' = 'some_experience' then o || '{"archived": true}' else o end)
   from jsonb_array_elements((select value->'options' from crm.organization_pack_items where id = :'experience_field')) o),
  false);
select tests.as_user('rep@test.local');
select lives_ok(
  format($$ select crm.set_contact_fields(%L, '{"city": "Mumbai"}') $$, :'asha'),
  'a stored value whose option was archived later does not block other edits'
);

-- Required: enforced on form saves, never on automatic creation.
select tests.as_user('owner@test.local');
select crm.update_custom_field(:'city_field',
  (select value->'label' from crm.organization_pack_items where id = :'city_field'), '[]', true);
select throws_ok(
  format($$ select crm.set_contact_fields(%L, '{"age": 40}') $$, :'ravi'),
  '22023', 'required: ' || :'city_label', 'saving the form needs the required fields'
);
select lives_ok(
  format($$ select crm.set_contact_fields(%L, '{"age": 40, "city": "Delhi"}') $$, :'ravi'),
  'with them it saves'
);
select tests.as_postgres();
insert into public.contacts_addresses (organization_id, organization_address, service, address)
values (:'org', '1001', 'whatsapp', '919800000003');
select is(
  (select count(*)::int from crm.contacts where organization_id = :'org'),
  3,
  'a new inbound contact is created even though City is required'
);

-- Archived fields keep their values but take no new ones.
select tests.as_user('owner@test.local');
select crm.archive_custom_field(:'age_field');
select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.set_contact_fields(%L, '{"age": 32}') $$, :'asha'),
  '22023', 'field age is archived', 'an archived field takes no new values'
);
select is(
  (select custom_fields->'age' from crm.contacts where id = :'asha'),
  '31'::jsonb,
  'its stored values stay'
);

-- Visibility and permissions -------------------------------------------------------------

-- The rep only handles the first number.
select tests.as_user('owner@test.local');
select crm.set_member_address_access(:'rep', 'whatsapp', '1001', true);

select tests.as_user('rep@test.local');
select results_eq(
  format($$ select id from crm.contacts where organization_id = %L $$, :'org'),
  format($$ values (%L::uuid), ((select contact_id from crm.contact_addresses where address = '919800000003' and organization_id = %L)) $$, :'asha', :'org'),
  'a number-scoped member sees only people who wrote to their numbers'
);
select throws_ok(
  format($$ select crm.set_contact_fields(%L, '{"city": "Goa"}') $$, :'ravi'),
  'P0002', 'contact not found', 'and cannot change anyone else'
);
select is_empty(
  format($$ select 1 from crm.contact_addresses where contact_id = %L $$, :'ravi'),
  'nor see their addresses'
);
select throws_ok(
  format($$ update crm.contacts set display_name = 'X' where id = %L $$, :'asha'),
  '42501', null, 'only field values can be written directly (column grant)'
);
select throws_ok(
  format($$ update crm.contacts set custom_fields = custom_fields || '{"capital_range": "lots"}' where id = %L $$, :'asha'),
  '22023', 'capital_range: unknown option lots', 'direct writes are checked by the trigger too'
);

select tests.as_user('viewer@test.local');
select isnt_empty(
  format($$ select 1 from crm.contacts where id = %L $$, :'ravi'),
  'a viewer (contacts.view) sees contacts'
);
select throws_ok(
  format($$ select crm.set_contact_fields(%L, '{"city": "Goa"}') $$, :'ravi'),
  '42501', 'permission contacts.edit required', 'but cannot edit them'
);

select tests.as_user('other.owner@test.local');
select is_empty(
  format($$ select 1 from crm.contacts where organization_id = %L $$, :'org'),
  'another tenant sees none of our contacts'
);
select throws_ok(
  format($$ select crm.set_contact_fields(%L, '{"city": "Goa"}') $$, :'asha'),
  'P0002', 'contact not found', 'or edits them'
);
select throws_ok(
  format($$ select crm.create_custom_field(%L, 'contact', 'spy', 'text', '{"en": "Spy"}') $$, :'org'),
  '42501', 'permission organization.manage required', 'or defines fields for us'
);

-- Filters ------------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select results_eq(
  format($$ select id from crm.filter_contacts(%L, '[{"field": "capital_range", "op": "eq", "value": "between_2l_10l"}]') $$, :'org'),
  format($$ values (%L::uuid) $$, :'asha'),
  'eq'
);
select results_eq(
  format($$ select id from crm.filter_contacts(%L, '[{"field": "preferred_market", "op": "contains", "value": "futures_options"}]') $$, :'org'),
  format($$ values (%L::uuid) $$, :'asha'),
  'contains on a multiple-choice field'
);
select results_eq(
  format($$ select id from crm.filter_contacts(%L, '[{"field": "city", "op": "in", "value": ["Delhi", "Goa"]}]') $$, :'org'),
  format($$ values (%L::uuid) $$, :'ravi'),
  'in'
);
select results_eq(
  format($$ select id from crm.filter_contacts(%L, '[{"field": "age", "op": "gt", "value": 35}]') $$, :'org'),
  format($$ values (%L::uuid) $$, :'ravi'),
  'greater than on numbers'
);
select is(
  (select count(*)::int from crm.filter_contacts(:'org', '[{"field": "city", "op": "is_empty"}]')),
  1,
  'is_empty finds the new inbound contact'
);
select is(
  (select count(*)::int from crm.filter_contacts(:'org', '[{"field": "city", "op": "contains", "value": "MUM"}, {"field": "age", "op": "lt", "value": 35}]')),
  1,
  'conditions combine (text contains ignores case)'
);
select throws_ok(
  format($$ select * from crm.filter_contacts(%L, '[{"field": "zodiac", "op": "eq", "value": "leo"}]') $$, :'org'),
  '22023', 'unknown field zodiac', 'filters name real fields'
);
select throws_ok(
  format($$ select * from crm.filter_contacts(%L, '[{"field": "city", "op": "like", "value": "x"}]') $$, :'org'),
  '22023', 'unknown filter operator like', 'and real operators'
);

select tests.as_user('rep@test.local');
select is(
  (select count(*)::int from crm.filter_contacts(:'org', '[{"field": "age", "op": "is_not_empty"}]')),
  1,
  'filters only return contacts the caller can see'
);

-- Formatting for templates ----------------------------------------------------------------

select is(
  crm.format_custom_field(:'org', 'contact', 'capital_range', '"between_2l_10l"', 'en'),
  '₹2 lakh – ₹10 lakh',
  'a choice shows its label'
);
select is(
  crm.format_custom_field(:'org', 'contact', 'capital_range', '"between_2l_10l"', 'hi'),
  '₹2 लाख – ₹10 लाख',
  'in the contact''s language'
);
select is(
  crm.format_custom_field(:'org', 'contact', 'preferred_market', '["equity", "futures_options"]', 'en'),
  'Equity (stocks), Futures & options',
  'multiple choices are listed'
);
select is(
  crm.format_custom_field(:'org', 'contact', 'demo_done', 'true', 'hi'),
  'हाँ',
  'yes/no in Hindi'
);

-- Audit --------------------------------------------------------------------------------

select tests.as_postgres();
select results_eq(
  format($$ select action, target_id from crm.audit_log where organization_id = %L and action like 'custom_field.%%' order by id $$, :'org'),
  $$ values ('custom_field.created'::text, 'age'::text), ('custom_field.created', 'demo_done'),
            ('custom_field.updated', 'experience_level'), ('custom_field.updated', 'experience_level'),
            ('custom_field.updated', 'city'), ('custom_field.archived', 'age') $$,
  'field definitions are audited'
);

select * from finish();
rollback;
