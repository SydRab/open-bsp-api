-- P4-03: segments. crm._filter_contact_rows (the extended core of
-- crm.filter_contacts, P1-06) now also filters by tag, lead stage, and
-- last-contact recency, not just custom fields. crm.segments/
-- crm.segment_members save a filter as static (frozen membership) or
-- dynamic (re-evaluated live). All gated `broadcasts.create` -- another
-- permission reserved unused in the catalog since P1-02.
begin;
\ir _helpers.psql

select plan(20);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('marketing@test.local') as marketing_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_org('owner@test.local', 'Segments Academy') as org \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'marketing@test.local', 'marketing') as marketing_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', '910000000000', 'connected');

-- Three contacts: one tagged + staged + recently active, one untagged with
-- no lead at all, one with a lead but no stage, long dormant.
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values
  (:'org', '910000000000', 'whatsapp', '919000000801', '{"name": "Active"}'),
  (:'org', '910000000000', 'whatsapp', '919000000802', '{"name": "NoLead"}'),
  (:'org', '910000000000', 'whatsapp', '919000000803', '{"name": "Dormant"}');
select contact_id as c_active from crm.contact_addresses where organization_id = :'org' and address = '919000000801' \gset
select contact_id as c_nolead from crm.contact_addresses where organization_id = :'org' and address = '919000000802' \gset
select contact_id as c_dormant from crm.contact_addresses where organization_id = :'org' and address = '919000000803' \gset

insert into public.conversations (id, organization_id, organization_address, address, service, name, last_inbound_at)
values
  ('00000000-0000-0000-0000-00000000f001', :'org', '910000000000', '919000000801', 'whatsapp', 'Active', now()),
  ('00000000-0000-0000-0000-00000000f003', :'org', '910000000000', '919000000803', 'whatsapp', 'Dormant', now() - interval '60 days');

select tests.as_user('owner@test.local');
select crm.create_tag(:'org', 'VIP') as tag_vip \gset
select crm.set_contact_tag(:'c_active', :'tag_vip', true);
select id as stage_id from crm.lead_stages where organization_id = :'org' order by sort_order limit 1 \gset
select crm.find_or_create_lead(:'org', :'c_active', 'organic') as lead_active \gset
select crm.set_lead_stage(:'lead_active', :'stage_id');
select crm.find_or_create_lead(:'org', :'c_dormant', 'organic') as lead_dormant \gset

-- crm.filter_contacts / crm._filter_contact_rows: permission gate --------------------------------

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.filter_contacts(%L, '[]'::jsonb) $$, :'org'),
  '42501', null, 'a sales_rep (no broadcasts.create) cannot filter contacts for a segment'
);

select tests.as_user('marketing@test.local');
select lives_ok(
  format($$ select crm.filter_contacts(%L, '[]'::jsonb) $$, :'org'),
  'marketing (has broadcasts.create) can'
);

-- tag filter --------------------------------------------------------------------------------------

select jsonb_build_array(jsonb_build_object('field', 'tag', 'op', 'has', 'value', :'tag_vip')) as crit_tag_has \gset
select jsonb_build_array(jsonb_build_object('field', 'tag', 'op', 'not_has', 'value', :'tag_vip')) as crit_tag_not_has \gset

select results_eq(
  format($$ select id from crm.filter_contacts(%L, %L::jsonb) $$, :'org', :'crit_tag_has'),
  format($$ values (%L::uuid) $$, :'c_active'),
  'tag has: only the tagged contact matches'
);
select results_eq(
  format($$ select count(*)::int from crm.filter_contacts(%L, %L::jsonb) $$, :'org', :'crit_tag_not_has'),
  $$ values (2) $$,
  'tag not_has: the other two match'
);

-- stage filter, including the "no lead at all" case ------------------------------------------------

select jsonb_build_array(jsonb_build_object('field', 'stage', 'op', 'eq', 'value', :'stage_id')) as crit_stage_eq \gset

select results_eq(
  format($$ select id from crm.filter_contacts(%L, %L::jsonb) $$, :'org', :'crit_stage_eq'),
  format($$ values (%L::uuid) $$, :'c_active'),
  'stage eq: only the contact actually on that stage matches'
);
select bag_eq(
  format($$ select id from crm.filter_contacts(%L, '[{"field":"stage","op":"is_empty"}]'::jsonb) $$, :'org'),
  format($$ values (%L::uuid), (%L::uuid) $$, :'c_nolead', :'c_dormant'),
  'stage is_empty: a contact with no lead at all is caught, same as a lead with no stage set -- never silently excluded'
);

-- last_contact_days filter ------------------------------------------------------------------------

select results_eq(
  format($$ select id from crm.filter_contacts(%L, '[{"field":"last_contact_days","op":"lte","value":7}]'::jsonb) $$, :'org'),
  format($$ values (%L::uuid) $$, :'c_active'),
  'last_contact_days lte 7: only the recently active contact'
);
select results_eq(
  format($$ select id from crm.filter_contacts(%L, '[{"field":"last_contact_days","op":"gte","value":30}]'::jsonb) $$, :'org'),
  format($$ values (%L::uuid) $$, :'c_dormant'),
  'last_contact_days gte 30: only the dormant contact -- never contacted is its own bucket, not folded in here'
);
select results_eq(
  format($$ select id from crm.filter_contacts(%L, '[{"field":"last_contact_days","op":"is_empty"}]'::jsonb) $$, :'org'),
  format($$ values (%L::uuid) $$, :'c_nolead'),
  'last_contact_days is_empty: only the never-contacted contact'
);

select throws_ok(
  format($$ select crm.filter_contacts(%L, '[{"field":"tag","op":"eq","value":"x"}]'::jsonb) $$, :'org'),
  '22023', null, 'an operator that does not apply to the tag field is refused'
);
select throws_ok(
  format($$ select crm.filter_contacts(%L, '[{"field":"nonsense","op":"eq","value":"x"}]'::jsonb) $$, :'org'),
  '22023', null, 'an unknown field (not tag/stage/last_contact_days, and not a real custom field) is still refused'
);

-- Dynamic segments: live-evaluated, never snapshotted ----------------------------------------------

select tests.as_user('marketing@test.local');
select crm.create_segment(:'org', 'Dynamic Active', 'dynamic', '[{"field":"last_contact_days","op":"lte","value":7}]'::jsonb) as seg_dynamic \gset
select is(
  (select count(*)::int from crm.segment_members where segment_id = :'seg_dynamic'),
  0,
  'a dynamic segment never gets a membership snapshot'
);
select results_eq(
  format($$ select id from crm.get_segment_contacts(%L) $$, :'seg_dynamic'),
  format($$ values (%L::uuid) $$, :'c_active'),
  'a dynamic segment re-evaluates its criteria live'
);

-- Static segments: snapshotted at creation and on refresh/update -----------------------------------

select crm.create_segment(:'org', 'Static Tagged', 'static', :'crit_tag_has'::jsonb) as seg_static \gset
select is(
  (select count(*)::int from crm.segment_members where segment_id = :'seg_static'),
  1,
  'a static segment snapshots its membership right at creation'
);

select tests.as_user('owner@test.local');
select crm.set_contact_tag(:'c_dormant', :'tag_vip', true);
select tests.as_user('marketing@test.local');
select is(
  (select count(*)::int from crm.segment_members where segment_id = :'seg_static'),
  1,
  'the static snapshot does not silently drift when the underlying data changes'
);
select crm.refresh_segment(:'seg_static');
select is(
  (select count(*)::int from crm.segment_members where segment_id = :'seg_static'),
  2,
  'refresh_segment re-evaluates and replaces the snapshot'
);

-- preview_segment_count: total vs. reachable-for-marketing -----------------------------------------

select tests.as_postgres();
select crm.record_consent_event(:'org', '910000000000', 'whatsapp', '919000000801', 'opted_in', 'admin');
select tests.as_user('marketing@test.local');
select results_eq(
  format($$ select total_count, opted_in_count from crm.preview_segment_count(%L, '[]'::jsonb) $$, :'org'),
  $$ values (3::bigint, 1::bigint) $$,
  'preview_segment_count: 3 total contacts, 1 with a recorded opt-in'
);

-- delete_segment ------------------------------------------------------------------------------------

select crm.delete_segment(:'seg_dynamic');
select is(
  (select count(*)::int from crm.segments where id = :'seg_dynamic'),
  0,
  'delete_segment removes the segment'
);

-- Cross-org isolation ---------------------------------------------------------------------------

select tests.as_postgres();
select tests.create_user('other.owner@test.local') as other_owner \gset
select tests.as_user('owner@test.local');
select tests.create_org('other.owner@test.local', 'Other Segments Org') as other_org \gset
select tests.as_user('other.owner@test.local');
select is(
  (select count(*)::int from crm.filter_contacts(:'other_org', '[]'::jsonb)),
  0,
  'a different (empty) org filters to zero contacts -- confirms the org filter, not a leak'
);
select throws_ok(
  format($$ select crm.refresh_segment(%L) $$, :'seg_static'),
  '42501', null, 'another org''s owner cannot refresh a segment that is not theirs'
);

select * from finish();
