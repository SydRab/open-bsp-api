-- P3-09: conversion feedback to Meta. crm.lead_event_mappings (status or
-- stage -> a Meta event name, seeded by default with qualified -> Lead)
-- and crm.outbox_events (one row per actually-queued event, mirroring
-- crm.webhook_events' exact claim/replay shape, P2-01) -- only for
-- ad-sourced leads with a captured ctwa_clid.
begin;
\ir _helpers.psql

select plan(26);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_org('owner@test.local', 'Vertex Academy') as org \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status, extra)
values (:'org', 'whatsapp', '910000000001', 'connected', '{"waba_id": "waba-1"}');
insert into public.conversations (id, organization_id, organization_address, address, service, name)
values ('00000000-0000-0000-0000-00000000d001', :'org', '910000000001', '919000000190', 'whatsapp', 'Ad lead');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', '910000000001', 'whatsapp', '919000000190', '{"name": "Ad Lead"}');
select contact_id as ad_contact from crm.contact_addresses
where organization_id = :'org' and address = '919000000190' \gset

-- The lead is created automatically by crm.z_welcome_and_create_lead
-- (P3-03) on this very first inbound message, which derives source from
-- crm.contacts.first_touch_referral -- itself set by crm.
-- touch_contact_referral (P3-01) from THIS SAME message's content.
-- referral, same trigger order both those tasks' own comments document.
-- A post-hoc UPDATE after the fact would be too late and unrealistic --
-- the referral has to ride the actual first inbound message.
select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-00000000d001', 'whatsapp', '910000000001', '919000000190',
  '919000000190',
  '{"version":"1","type":"text","kind":"text","text":"hi","referral":{"source_id":"ad-1","source_type":"ad","source_url":"https://fb.me/ad1","headline":"Trading course","body":"Learn to trade","ctwa_clid":"clid-abc"}}'::jsonb,
  'ext-conv-1', now()
);

select tests.as_postgres();
select id as ad_lead from crm.leads where contact_id = :'ad_contact' \gset

select tests.as_user('owner@test.local');
select crm.set_lead_deal_value(:'ad_lead', 25000);

-- The default mapping was seeded on org creation -----------------------------------------------

select isnt_empty(
  format(
    $$ select 1 from crm.lead_event_mappings where organization_id = %L
       and trigger_type = 'status' and trigger_status = 'qualified' and meta_event_name = 'Lead' $$,
    :'org'
  ),
  'qualified -> Lead was seeded on org creation'
);

-- set_event_mapping / delete_event_mapping: permission gate + validation ------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.set_event_mapping(%L, 'status', 'open', 'Contact') $$, :'org'),
  '42501', null, 'a viewer (no organization.manage) cannot set a mapping'
);

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.set_event_mapping(%L, 'status', 'not-a-status', 'X') $$, :'org'),
  '22023', null, 'an unknown status value is rejected'
);
select throws_ok(
  format($$ select crm.set_event_mapping(%L, 'stage', %L, 'X') $$, :'org', '00000000-0000-0000-0000-000000000000'),
  '22023', 'stage not found', 'an unknown stage id is rejected'
);

select id as trial_booked_stage from crm.lead_stages
where organization_id = :'org' and key = 'trial_booked' \gset
select crm.set_event_mapping(:'org', 'stage', :'trial_booked_stage', 'CustomTrialBooked') as mapping_id \gset
select isnt_empty(
  format($$ select 1 from crm.lead_event_mappings where id = %L and meta_event_name = 'CustomTrialBooked' $$, :'mapping_id'),
  'a stage-based mapping is created'
);

select crm.set_event_mapping(:'org', 'stage', :'trial_booked_stage', 'Renamed');
select is(
  (select count(*)::int from crm.lead_event_mappings where organization_id = :'org' and trigger_stage_id = :'trial_booked_stage'),
  1,
  're-setting the same stage mapping updates it in place, not a second row'
);

select crm.delete_event_mapping(:'mapping_id');
select is_empty(
  format($$ select 1 from crm.lead_event_mappings where id = %L $$, :'mapping_id'),
  'delete_event_mapping removes it'
);

-- Enqueue on the status transition: ad-sourced + ctwa_clid -> an outbox row ----------------------

select tests.as_user('owner@test.local');
select crm.set_lead_status(:'ad_lead', 'qualified');

select isnt_empty(
  format(
    $$ select 1 from crm.outbox_events where organization_id = %L and lead_id = %L
       and event_name = 'Lead' and ctwa_clid = 'clid-abc' and organization_address = '910000000001'
       and value = 25000 and currency = 'INR' $$,
    :'org', :'ad_lead'
  ),
  'qualifying an ad-sourced lead with a ctwa_clid enqueues a Lead event, carrying deal_value'
);
select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.conversion_event_enqueued'
       and target_id = %L $$,
    :'org', :'ad_lead'
  ),
  '...and audits it'
);

-- Organic leads never enqueue, even with a matching status transition ---------------------------

select tests.as_postgres();
insert into public.conversations (id, organization_id, organization_address, address, service, name)
values ('00000000-0000-0000-0000-00000000d002', :'org', '910000000001', '919000000191', 'whatsapp', 'Organic');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', '910000000001', 'whatsapp', '919000000191', '{"name": "Organic"}');
select contact_id as organic_contact from crm.contact_addresses
where organization_id = :'org' and address = '919000000191' \gset

select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-00000000d002', 'whatsapp', '910000000001', '919000000191',
  '919000000191', '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb,
  'ext-conv-2', now()
);

select tests.as_postgres();
select id as organic_lead from crm.leads where contact_id = :'organic_contact' \gset

select tests.as_user('owner@test.local');
select crm.set_lead_status(:'organic_lead', 'qualified');
select is_empty(
  format($$ select 1 from crm.outbox_events where lead_id = %L $$, :'organic_lead'),
  'an organic lead (no referral at all) never enqueues, even on a matching status transition'
);

-- An ad-sourced lead with no captured ctwa_clid also never enqueues (Meta's own documented -------
-- edge case: the property is omitted for messages from an ad in WhatsApp Status) ----------------

select tests.as_postgres();
insert into public.conversations (id, organization_id, organization_address, address, service, name)
values ('00000000-0000-0000-0000-00000000d003', :'org', '910000000001', '919000000192', 'whatsapp', 'No clid');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', '910000000001', 'whatsapp', '919000000192', '{"name": "No clid"}');
select contact_id as no_clid_contact from crm.contact_addresses
where organization_id = :'org' and address = '919000000192' \gset

select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-00000000d003', 'whatsapp', '910000000001', '919000000192',
  '919000000192',
  '{"version":"1","type":"text","kind":"text","text":"hi","referral":{"source_id":"ad-2","source_type":"ad","source_url":"https://fb.me/ad2","headline":"H","body":"B"}}'::jsonb,
  'ext-conv-3', now()
);

select tests.as_postgres();
select id as no_clid_lead from crm.leads where contact_id = :'no_clid_contact' \gset

select tests.as_user('owner@test.local');
select crm.set_lead_status(:'no_clid_lead', 'qualified');
select is_empty(
  format($$ select 1 from crm.outbox_events where lead_id = %L $$, :'no_clid_lead'),
  'an ad-sourced lead with no ctwa_clid captured never enqueues'
);

-- Stage-based mapping, exercised through the real set_lead_stage path ----------------------------

select tests.as_user('owner@test.local');
select crm.set_event_mapping(:'org', 'stage', :'trial_booked_stage', 'TrialBookedCustom');
select crm.set_lead_stage(:'ad_lead', :'trial_booked_stage');
select isnt_empty(
  format(
    $$ select 1 from crm.outbox_events where lead_id = %L and event_name = 'TrialBookedCustom' $$,
    :'ad_lead'
  ),
  'moving an ad-sourced lead into a mapped stage enqueues that stage''s event'
);

-- Moving into an unmapped stage enqueues nothing -------------------------------------------------

select id as dropped_stage from crm.lead_stages where organization_id = :'org' and key = 'dropped' \gset
select crm.set_lead_stage(:'ad_lead', :'dropped_stage');
select is(
  (select count(*)::int from crm.outbox_events where lead_id = :'ad_lead'),
  2,
  'moving into an unmapped stage (dropped) adds no third outbox row -- still exactly 2'
);

-- claim / mark_sent / mark_failed / replay --------------------------------------------------------

select tests.as_postgres();
select id as outbox_id from crm.outbox_events
where lead_id = :'ad_lead' and event_name = 'Lead' \gset

select is_empty(
  $$ select 1 from crm.claim_outbox_event('00000000-0000-0000-0000-000000000000') $$,
  'claiming a nonexistent event returns no row'
);
select isnt_empty(
  format($$ select 1 from crm.claim_outbox_event(%L) $$, :'outbox_id'),
  'claiming a real pending event returns it'
);
select is(
  (select attempts from crm.outbox_events where id = :'outbox_id'),
  1,
  '...and bumps attempts'
);

select crm.mark_outbox_event_sent(:'outbox_id');
select isnt_empty(
  format($$ select 1 from crm.outbox_events where id = %L and processed_at is not null $$, :'outbox_id'),
  'mark_outbox_event_sent marks it processed'
);
select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.conversion_event_sent' $$,
    :'org'
  ),
  '...and audits it'
);

select id as second_outbox_id from crm.outbox_events
where lead_id = :'ad_lead' and event_name = 'TrialBookedCustom' \gset
select crm.claim_outbox_event(:'second_outbox_id');
select crm.mark_outbox_event_failed(:'second_outbox_id', 'simulated network error');
select isnt_empty(
  format(
    $$ select 1 from crm.outbox_events where id = %L and processing_error = 'simulated network error' $$,
    :'second_outbox_id'
  ),
  'mark_outbox_event_failed records the error'
);
select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.conversion_event_failed' $$,
    :'org'
  ),
  '...and audits it'
);

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.replay_outbox_event(%L) $$, :'second_outbox_id'),
  '42501', null, 'a viewer cannot replay a failed event'
);

select tests.as_user('owner@test.local');
select throws_ok(
  $$ select crm.replay_outbox_event('00000000-0000-0000-0000-000000000000') $$,
  'P0002', 'event not found', 'replaying a nonexistent event is refused'
);
select crm.replay_outbox_event(:'second_outbox_id');
select isnt_empty(
  format(
    $$ select 1 from crm.outbox_events where id = %L and processed_at is null
       and attempts = 0 and processing_error is null $$,
    :'second_outbox_id'
  ),
  'replay_outbox_event resets it for the next cron tick'
);
select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.conversion_event_replayed' $$,
    :'org'
  ),
  '...and audits it'
);

-- Cross-org isolation -----------------------------------------------------------------------------

select tests.as_postgres();
select tests.create_user('other.owner@test.local') as other_owner \gset
select tests.as_user('owner@test.local');
select tests.create_org('other.owner@test.local', 'Other Academy') as other_org \gset

select tests.as_user('other.owner@test.local');
select is_empty(
  format($$ select 1 from crm.outbox_events where organization_id = %L $$, :'org'),
  'tenant isolation: a different org cannot see this org''s outbox events'
);
select is_empty(
  format($$ select 1 from crm.lead_event_mappings where organization_id = %L $$, :'org'),
  '...nor its event mappings'
);

select * from finish();
