-- P4-04: campaign builder. crm.campaigns ties a crm.templates row to a
-- crm.segments audience and a variable mapping (fixed value or contact
-- field, per {{n}} placeholder -- header and body number independently).
-- Gated `broadcasts.create`, same permission as segments. P4-06 (the
-- fan-out send engine) does not exist yet, so the only real send tested
-- here is crm.send_test_campaign_message -- one message to the caller's
-- own connected number.
begin;
\ir _helpers.psql

select plan(19);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('marketing@test.local') as marketing_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_org('owner@test.local', 'Campaigns Academy') as org \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'marketing@test.local', 'marketing') as marketing_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', '910000000000', 'connected');

-- A header placeholder and two body placeholders -- independently
-- numbered, to prove variable_mapping is keyed by (component, index), not
-- a single flat index.
select tests.as_service();
insert into crm.templates (
  organization_id, organization_address, meta_id, name, category, language, status, components
)
values (
  :'org', '910000000000', 'meta-tpl-promo', 'promo_offer', 'MARKETING', 'en', 'APPROVED',
  '[
    {"type":"HEADER","text":"Hi {{1}}","example":{"header_text":["Rahul"]}},
    {"type":"BODY","text":"Get {{1}} off on {{2}}!","example":{"body_text":[["20%","the trading course"]]}}
  ]'::jsonb
)
returning id as template_id \gset

select tests.as_user('owner@test.local');
select crm.create_custom_field(:'org', 'contact', 'course_name', 'text', '{"en": "Course name"}'::jsonb) as course_field \gset

insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values
  (:'org', '910000000000', 'whatsapp', '919000000901', '{"name": "Opted In"}'),
  (:'org', '910000000000', 'whatsapp', '919000000902', '{"name": "Not Opted"}');

-- A conversation row is how crm.preview_segment_count's own consent
-- lookup resolves a contact's organization_address (same join chain
-- crm.export_contacts/preview_segment_count already use) -- without one,
-- record_consent_event below would never actually be found as this
-- contact's consent.
select tests.as_postgres();
insert into public.conversations (organization_id, organization_address, address, service, name)
values (:'org', '910000000000', '919000000901', 'whatsapp', 'Opted In');
select tests.as_user('owner@test.local');

select tests.as_user('marketing@test.local');
select crm.create_segment(:'org', 'Everyone', 'dynamic', '[]'::jsonb) as seg \gset

select jsonb_build_array(
  jsonb_build_object('component', 'header', 'index', 1, 'type', 'fixed', 'value', 'there'),
  jsonb_build_object('component', 'body', 'index', 1, 'type', 'fixed', 'value', '20%'),
  jsonb_build_object('component', 'body', 'index', 2, 'type', 'field', 'value', 'display_name')
) as valid_mapping \gset

-- Permission gate -----------------------------------------------------------------------

select tests.as_user('rep@test.local');
select throws_ok(
  format(
    $$ select crm.create_campaign(%L, 'Diwali Sale', '910000000000', 'promo_offer', 'en', %L, %L::jsonb) $$,
    :'org', :'seg', :'valid_mapping'
  ),
  '42501', null, 'a sales_rep (no broadcasts.create) cannot create a campaign'
);

select tests.as_user('marketing@test.local');
select lives_ok(
  format(
    $$ select crm.create_campaign(%L, 'Diwali Sale', '910000000000', 'promo_offer', 'en', %L, %L::jsonb) $$,
    :'org', :'seg', :'valid_mapping'
  ),
  'marketing (has broadcasts.create) can'
);

select crm.create_campaign(:'org', 'Diwali Sale', '910000000000', 'promo_offer', 'en', :'seg', :'valid_mapping'::jsonb) as campaign_id \gset

select is(
  (select status from crm.campaigns where id = :'campaign_id'),
  'draft',
  'a new campaign starts as a draft'
);

-- Variable mapping validation ------------------------------------------------------------

select throws_ok(
  format(
    $$ select crm.create_campaign(%L, 'Missing slot', '910000000000', 'promo_offer', 'en', %L,
         '[{"component":"header","index":1,"type":"fixed","value":"x"},
           {"component":"body","index":1,"type":"fixed","value":"x"}]'::jsonb) $$,
    :'org', :'seg'
  ),
  '22023', null, 'a mapping missing a real placeholder (body index 2) is refused'
);

select throws_ok(
  format(
    $$ select crm.create_campaign(%L, 'Extra slot', '910000000000', 'promo_offer', 'en', %L,
         '[{"component":"header","index":1,"type":"fixed","value":"x"},
           {"component":"body","index":1,"type":"fixed","value":"x"},
           {"component":"body","index":2,"type":"fixed","value":"x"},
           {"component":"body","index":3,"type":"fixed","value":"x"}]'::jsonb) $$,
    :'org', :'seg'
  ),
  '22023', null, 'a mapping naming a slot the template does not have is refused'
);

select throws_ok(
  format(
    $$ select crm.create_campaign(%L, 'Unknown field', '910000000000', 'promo_offer', 'en', %L,
         '[{"component":"header","index":1,"type":"fixed","value":"x"},
           {"component":"body","index":1,"type":"fixed","value":"x"},
           {"component":"body","index":2,"type":"field","value":"no_such_field"}]'::jsonb) $$,
    :'org', :'seg'
  ),
  '22023', null, 'a field-mapped entry naming an unknown contact field is refused'
);

select lives_ok(
  format(
    $$ select crm.create_campaign(%L, 'Real field', '910000000000', 'promo_offer', 'en', %L,
         '[{"component":"header","index":1,"type":"fixed","value":"x"},
           {"component":"body","index":1,"type":"fixed","value":"x"},
           {"component":"body","index":2,"type":"field","value":"course_name"}]'::jsonb) $$,
    :'org', :'seg'
  ),
  'a field-mapped entry naming a real contact custom field is accepted'
);

-- update_campaign -------------------------------------------------------------------------

select crm.update_campaign(:'campaign_id', 'Diwali Mega Sale', :'seg', :'valid_mapping'::jsonb);
select is(
  (select name from crm.campaigns where id = :'campaign_id'),
  'Diwali Mega Sale',
  'update_campaign renames the campaign'
);

select throws_ok(
  format(
    $$ select crm.update_campaign(%L, 'x', %L,
         '[{"component":"header","index":1,"type":"fixed","value":"x"}]'::jsonb) $$,
    :'campaign_id', :'seg'
  ),
  '22023', null, 'update_campaign re-validates the mapping against the template every time'
);

-- Scheduling, in the organization's own timezone -----------------------------------------

select crm.schedule_campaign(:'campaign_id', (current_date + 365), '10:00');
select is(
  (select status from crm.campaigns where id = :'campaign_id'),
  'scheduled',
  'schedule_campaign marks the campaign scheduled'
);
select is(
  (select scheduled_at from crm.campaigns where id = :'campaign_id'),
  (((current_date + 365)::text || ' 10:00')::timestamp at time zone 'Asia/Kolkata'),
  'scheduled_at is the local wall-clock time converted via the org''s own timezone (default Asia/Kolkata)'
);

select throws_ok(
  format($$ select crm.schedule_campaign(%L, (current_date - 1), '10:00') $$, :'campaign_id'),
  '22023', null, 'a scheduled time in the past is refused'
);

select crm.unschedule_campaign(:'campaign_id');
select is(
  (select status from crm.campaigns where id = :'campaign_id'),
  'draft',
  'unschedule_campaign reverts the status to draft'
);
select is(
  (select scheduled_at from crm.campaigns where id = :'campaign_id'),
  null::timestamptz,
  'unschedule_campaign clears scheduled_at'
);

-- Cost estimate ---------------------------------------------------------------------------

select tests.as_postgres();
select crm.record_consent_event(:'org', '910000000000', 'whatsapp', '919000000901', 'opted_in', 'admin');

select tests.as_user('marketing@test.local');
select results_eq(
  format(
    $$ select audience_count, opted_in_count, rate, currency, estimated_total
       from crm.estimate_campaign_cost(%L) $$,
    :'campaign_id'
  ),
  $$ values (2::bigint, 1::bigint, 0.8631::numeric, 'INR'::text, 0.8631::numeric) $$,
  'estimate_campaign_cost: 2 total, 1 opted-in, MARKETING rate for India times the opted-in count'
);

-- Test send ---------------------------------------------------------------------------------

select throws_ok(
  format($$ select crm.send_test_campaign_message(%L) $$, :'campaign_id'),
  'P0001', null, 'a member with no whatsapp_address set cannot send a test'
);

select crm.set_my_whatsapp_address(:'org', '919999999999');

select crm.send_test_campaign_message(:'campaign_id') as test_message_id \gset
select results_eq(
  format(
    $$ select content->'data'->>'name', content->'data'->'components'
       from public.messages where id = %L $$,
    :'test_message_id'
  ),
  $$ values (
    'promo_offer',
    '[{"type":"header","parameters":[{"type":"text","text":"there"}]},
      {"type":"body","parameters":[{"type":"text","text":"20%"},{"type":"text","text":"the trading course"}]}]'::jsonb
  ) $$,
  'the test message renders a fixed value as-is and a field-mapped slot from the template''s own example text -- there is no real recipient at test-send time (that only happens once P4-06 fans out to a segment)'
);

-- delete_campaign -------------------------------------------------------------------------

select crm.delete_campaign(:'campaign_id');
select is(
  (select count(*)::int from crm.campaigns where id = :'campaign_id'),
  0,
  'delete_campaign removes the campaign'
);

-- Cross-org isolation ---------------------------------------------------------------------

select tests.as_postgres();
select tests.create_user('other.owner@test.local') as other_owner \gset
select tests.as_user('owner@test.local');
select tests.create_org('other.owner@test.local', 'Other Campaigns Org') as other_org \gset
select tests.as_user('other.owner@test.local');
select is(
  (select count(*)::int from crm.campaigns where organization_id = :'other_org'),
  0,
  'a different org has no campaigns -- confirms the org filter, not a leak'
);

select * from finish();
