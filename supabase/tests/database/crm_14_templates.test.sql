-- P2-04: crm.templates. A local cache of each number's Meta templates --
-- RLS (members read, writes are service-role only), the unique key that
-- every sync path upserts through, and the category check constraint.
begin;
\ir _helpers.psql

select plan(13);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('other.owner@test.local') as other_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');

-- Who can read -------------------------------------------------------------------------

select tests.as_service();
insert into crm.templates (organization_id, organization_address, meta_id, name, category, language, status, components)
values (:'org', 'phone-1', 'meta-tpl-1', 'lead_inquiry_ack', 'UTILITY', 'en', 'APPROVED', '[{"type":"BODY","text":"Hi {{1}}"}]'::jsonb)
returning id as template_id \gset

select tests.as_user('owner@test.local');
select isnt_empty(
  format($$ select 1 from crm.templates where id = %L $$, :'template_id'),
  'a member of the org can read its templates'
);

select tests.as_user('other.owner@test.local');
select is_empty(
  format($$ select 1 from crm.templates where id = %L $$, :'template_id'),
  'another organization cannot'
);

-- Writes are service-role only ----------------------------------------------------------

select tests.as_user('owner@test.local');
select throws_ok(
  format($$
    insert into crm.templates (organization_id, organization_address, meta_id, name, category, language, components)
    values (%L, 'phone-1', 'meta-tpl-2', 'hand_inserted', 'UTILITY', 'en', '[]'::jsonb)
  $$, :'org'),
  '42501', null, 'a tenant owner cannot insert a template row directly'
);
select throws_ok(
  format($$ update crm.templates set status = 'REJECTED' where id = %L $$, :'template_id'),
  '42501', null, 'nor update one'
);
select throws_ok(
  format($$ delete from crm.templates where id = %L $$, :'template_id'),
  '42501', null, 'nor delete one'
);

select tests.as_api_key('some-key');
select throws_ok(
  format($$
    insert into crm.templates (organization_id, organization_address, meta_id, name, category, language, components)
    values (%L, 'phone-1', 'meta-tpl-3', 'api_key_inserted', 'UTILITY', 'en', '[]'::jsonb)
  $$, :'org'),
  '42501', null, 'an API key cannot insert one either'
);

-- Unique key: (organization_id, organization_address, name, language) ------------------

select tests.as_service();
select throws_ok(
  format($$
    insert into crm.templates (organization_id, organization_address, meta_id, name, category, language, components)
    values (%L, 'phone-1', 'meta-tpl-4', 'lead_inquiry_ack', 'UTILITY', 'en', '[]'::jsonb)
  $$, :'org'),
  '23505', null, 'the same (org, number, name, language) cannot be inserted twice'
);
select lives_ok(
  format($$
    insert into crm.templates (organization_id, organization_address, meta_id, name, category, language, components)
    values (%L, 'phone-1', 'meta-tpl-5', 'lead_inquiry_ack', 'UTILITY', 'hi', '[]'::jsonb)
  $$, :'org'),
  'but a different language for the same name is a distinct row'
);

-- Upsert reuses the row rather than erroring ---------------------------------------------

update crm.templates
set status = 'PENDING', quality_score = 'GREEN'
where organization_id = :'org' and organization_address = 'phone-1' and name = 'lead_inquiry_ack' and language = 'en';
select is(
  (select status from crm.templates where id = :'template_id'),
  'PENDING',
  'a status update (what the webhook handler does) lands on the same row'
);
select is(
  (select count(*)::int from crm.templates where organization_id = :'org' and name = 'lead_inquiry_ack'),
  2,
  'still exactly 2 rows (en + hi) for this template name -- the update did not fork a new one'
);

-- Category check constraint ---------------------------------------------------------------

select throws_ok(
  format($$
    insert into crm.templates (organization_id, organization_address, meta_id, name, category, language, components)
    values (%L, 'phone-1', 'meta-tpl-6', 'bad_category', 'AUTHENTICATION', 'en', '[]'::jsonb)
  $$, :'org'),
  '23514', null, 'AUTHENTICATION is rejected -- only MARKETING/UTILITY are supported this phase'
);

-- pack_item_key is independently settable, for pack-submission tracking ------------------

select lives_ok(
  format($$
    insert into crm.templates (organization_id, organization_address, meta_id, name, category, language, components, pack_item_key)
    values (%L, 'phone-1', 'meta-tpl-7', 'trial_class_confirmation', 'UTILITY', 'en', '[]'::jsonb, 'trial_class_confirmation')
  $$, :'org'),
  'a pack-submitted template records which pack item it came from'
);
select is(
  (select pack_item_key from crm.templates where organization_id = :'org' and name = 'trial_class_confirmation'),
  'trial_class_confirmation',
  'and it is readable back'
);

select * from finish();
rollback;
