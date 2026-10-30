-- P3-10a: pipeline reports (funnel, source/ad performance). Gated on
-- `reports.view` -- already in the permission catalog since P1-02
-- (sales_manager/marketing/admin/owner by default, not sales_rep), never
-- consumed by any code before this. `status` is the funnel (fixed
-- lifecycle); `stage_id` is left alone (tenant vocabulary, not guaranteed
-- sequential).
begin;
\ir _helpers.psql

select plan(13);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_org('owner@test.local', 'Zenith Reports') as org \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', '910000000000', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values
  (:'org', '910000000000', 'whatsapp', '919000000201', '{"name": "Ad Won"}'),
  (:'org', '910000000000', 'whatsapp', '919000000202', '{"name": "Ad Lost"}'),
  (:'org', '910000000000', 'whatsapp', '919000000203', '{"name": "Organic Open"}'),
  (:'org', '910000000000', 'whatsapp', '919000000204', '{"name": "Old Lead"}');
select contact_id as c_ad_won from crm.contact_addresses where organization_id = :'org' and address = '919000000201' \gset
select contact_id as c_ad_lost from crm.contact_addresses where organization_id = :'org' and address = '919000000202' \gset
select contact_id as c_organic from crm.contact_addresses where organization_id = :'org' and address = '919000000203' \gset
select contact_id as c_old from crm.contact_addresses where organization_id = :'org' and address = '919000000204' \gset

update crm.contacts set first_touch_referral = '{"ctwa_clid": "clid-1", "source_type": "ad", "source_id": "ad-100"}'::jsonb
where id in (:'c_ad_won', :'c_ad_lost');

select tests.as_user('owner@test.local');
select crm.find_or_create_lead(:'org', :'c_ad_won', 'ctwa_ad') as lead_ad_won \gset
select crm.set_lead_status(:'lead_ad_won', 'qualified');
select crm.set_lead_status(:'lead_ad_won', 'converted');
select crm.set_lead_deal_value(:'lead_ad_won', 30000);

select crm.find_or_create_lead(:'org', :'c_ad_lost', 'ctwa_ad') as lead_ad_lost \gset
select crm.set_lead_status(:'lead_ad_lost', 'dropped', (select id from crm.lead_drop_reasons where organization_id = :'org' limit 1));

select crm.find_or_create_lead(:'org', :'c_organic', 'organic') as lead_organic \gset

select crm.find_or_create_lead(:'org', :'c_old', 'organic') as lead_old \gset
select tests.as_postgres();
update crm.leads set created_at = now() - interval '60 days' where id = :'lead_old';

-- Permission gate --------------------------------------------------------------------------------

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.report_status_funnel(%L) $$, :'org'),
  '42501', null, 'a sales_rep (no reports.view by default) cannot read the funnel report'
);
select throws_ok(
  format($$ select crm.report_source_performance(%L) $$, :'org'),
  '42501', null, '...nor the source-performance report'
);

-- Status funnel ------------------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select is(
  (select lead_count from crm.report_status_funnel(:'org') where status = 'converted'),
  1::bigint,
  'one converted lead in the all-time funnel'
);
select is(
  (select lead_count from crm.report_status_funnel(:'org') where status = 'dropped'),
  1::bigint,
  '...one dropped'
);
select is(
  (select lead_count from crm.report_status_funnel(:'org') where status = 'open'),
  2::bigint,
  '...two still open (organic + the backdated old lead)'
);
select is(
  (select count(*)::int from crm.report_status_funnel(:'org', now() - interval '7 days', null)),
  3,
  'a from-date filter excludes the 60-day-old lead''s status row entirely'
);

-- Source/ad performance -----------------------------------------------------------------------------

select is(
  (select lead_count from crm.report_source_performance(:'org') where source = 'ctwa_ad' and ad_source_id = 'ad-100'),
  2::bigint,
  'both ad-sourced leads group under the same ad_source_id'
);
select is(
  (select converted_count from crm.report_source_performance(:'org') where source = 'ctwa_ad' and ad_source_id = 'ad-100'),
  1::bigint,
  '...one of them converted'
);
select is(
  (select dropped_count from crm.report_source_performance(:'org') where source = 'ctwa_ad' and ad_source_id = 'ad-100'),
  1::bigint,
  '...one dropped'
);
select is(
  (select total_deal_value from crm.report_source_performance(:'org') where source = 'ctwa_ad' and ad_source_id = 'ad-100'),
  30000::numeric,
  '...total_deal_value only counts the converted one, not the dropped one''s (unset) value'
);
select is(
  (select ad_source_id from crm.report_source_performance(:'org') where source = 'organic' limit 1),
  null,
  'an organic lead has no ad_source_id'
);
select is(
  (select lead_count from crm.report_source_performance(:'org', now() - interval '7 days', null) where source = 'organic'),
  1::bigint,
  'a from-date filter excludes the backdated organic lead, leaving only the fresh one in the count'
);

-- Cross-org isolation ---------------------------------------------------------------------------

select tests.as_postgres();
select tests.create_user('other.owner@test.local') as other_owner \gset
select tests.as_user('owner@test.local');
select tests.create_org('other.owner@test.local', 'Other Reports Org') as other_org \gset

select tests.as_user('other.owner@test.local');
select is(
  (select count(*)::int from crm.report_status_funnel(:'other_org')),
  0,
  'a different org''s owner sees zero rows for their own (empty) org -- confirms the org filter, not a leak'
);

select * from finish();
