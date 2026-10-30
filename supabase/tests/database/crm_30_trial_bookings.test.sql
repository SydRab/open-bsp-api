-- P3-08: trial booking. trial.schedule (a tenant setting, same "no
-- platform-default fallback" trick as assignment.working_hours) drives
-- crm._upcoming_trial_slots; the qualified-trigger offer, the inbound
-- list-reply booking, staff reschedule/cancel, and the reminder sweep all
-- mirror an existing P3-04/06/07d pattern. The schedule used here covers
-- every day of the week with four times a day so the test never depends
-- on which real-world day/time it happens to run on (the lesson already
-- learned from crm_24_assignment's wall-clock-dependent working_hours
-- test).
begin;
\ir _helpers.psql

select plan(25);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_user('rep.b@test.local') as rep_b_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_org('owner@test.local', 'Zenith Academy') as org \gset

select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep.b@test.local', 'sales_rep') as rep_b_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', '910000000001', 'connected');
insert into public.conversations (id, organization_id, organization_address, address, service, name)
values ('00000000-0000-0000-0000-00000000c001', :'org', '910000000001', '919000000090', 'whatsapp', 'Prospect');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', '910000000001', 'whatsapp', '919000000090', '{"name": "Prospect"}');
select contact_id as prospect from crm.contact_addresses
where organization_id = :'org' and address = '919000000090' \gset

select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-00000000c001', 'whatsapp', '910000000001', '919000000090',
  '919000000090', '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb,
  'ext-trial-1', now()
);

select tests.as_user('owner@test.local');
select crm.find_or_create_lead(:'org', :'prospect', 'organic') as lead \gset
select crm.assign_lead(:'lead', :'rep_agent');

-- The platform template was seeded on org creation --------------------------------------------

select isnt_empty(
  format(
    $$ select 1 from crm.organization_pack_items
       where organization_id = %L and kind = 'message_template' and item_key = 'trial_class_reminder' $$,
    :'org'
  ),
  'the trial_class_reminder template was seeded on org creation'
);

-- No trial.schedule configured: no slots, graceful ---------------------------------------------

select tests.as_user('owner@test.local');
select is(
  (select count(*)::int from crm.list_upcoming_trial_slots(:'org')),
  0,
  'with no trial.schedule set, there are no upcoming slots'
);

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.list_upcoming_trial_slots(%L) $$, :'org'),
  '42501', null, 'a viewer (no deals.edit) cannot list trial slots'
);

-- Configure the schedule: every day, 4 times a day, capacity 2 -----------------------------------

select tests.as_user('owner@test.local');
select lives_ok(
  format(
    $$ select crm.set_setting(%L, 'trial.schedule',
         '{"days": ["mon","tue","wed","thu","fri","sat","sun"],
           "times": ["00:00","06:00","12:00","18:00"],
           "slot_duration_minutes": 60, "capacity_per_slot": 2}'::jsonb) $$,
    :'org'
  ),
  'the owner configures the trial schedule'
);
select cmp_ok(
  (select count(*)::int from crm.list_upcoming_trial_slots(:'org')),
  '>', 0,
  '...and upcoming slots now exist'
);

-- Auto-offer is off by default: qualifying a lead sends nothing ---------------------------------

select tests.as_user('owner@test.local');
select crm.set_lead_status(:'lead', 'qualified');
select is_empty(
  format(
    $$ select 1 from public.messages where organization_id = %L and content->>'kind' = 'interactive_list' $$,
    :'org'
  ),
  'trial.auto_offer defaults off -- qualifying a lead does not send a slot offer'
);

-- Turn it on and re-trigger via a fresh lead -----------------------------------------------------

select tests.as_user('owner@test.local');
select crm.set_setting(:'org', 'trial.auto_offer', 'true'::jsonb);

select tests.as_postgres();
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', '910000000001', 'whatsapp', '919000000091', '{"name": "Second"}');
select contact_id as second from crm.contact_addresses
where organization_id = :'org' and address = '919000000091' \gset
insert into public.conversations (id, organization_id, organization_address, address, service, name)
values ('00000000-0000-0000-0000-00000000c002', :'org', '910000000001', '919000000091', 'whatsapp', 'Second');
select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-00000000c002', 'whatsapp', '910000000001', '919000000091',
  '919000000091', '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb,
  'ext-trial-2', now()
);

select tests.as_user('owner@test.local');
select crm.find_or_create_lead(:'org', :'second', 'organic') as lead_2 \gset
select crm.assign_lead(:'lead_2', :'rep_agent');
select crm.set_lead_status(:'lead_2', 'qualified');

select isnt_empty(
  format(
    $$ select 1 from public.messages where organization_id = %L
       and conversation_address = '919000000091' and content->>'kind' = 'interactive_list' $$,
    :'org'
  ),
  'with trial.auto_offer on, qualifying a lead sends an interactive slot-list offer'
);
select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.trial_offered'
       and target_id = %L $$,
    :'org', :'lead_2'
  ),
  '...and audits it'
);

-- Booking via a list-reply tap -------------------------------------------------------------------

select tests.as_user('owner@test.local');
select slot_start from crm.list_upcoming_trial_slots(:'org') order by slot_start limit 1 \gset
select 'trial_slot::' || to_char(:'slot_start'::timestamptz, 'YYYY-MM-DD"T"HH24:MI:SSOF') as row_id \gset

select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-00000000c002', 'whatsapp', '910000000001', '919000000091',
  '919000000091',
  jsonb_build_object('version', '1', 'type', 'data',
    'kind', 'interactive', 'data', jsonb_build_object('type', 'list_reply',
      'list_reply', jsonb_build_object('id', :'row_id', 'title', 'pick'))),
  'ext-trial-3', now()
);

select tests.as_postgres();
select isnt_empty(
  format(
    $$ select 1 from crm.trial_bookings where organization_id = %L and lead_id = %L
       and status = 'booked' and slot_start = %L::timestamptz $$,
    :'org', :'lead_2', :'slot_start'
  ),
  'tapping an offered slot books it'
);
select isnt_empty(
  format(
    $$ select 1 from public.messages where organization_id = %L
       and conversation_address = '919000000091' and content->>'kind' = 'text'
       and content->>'text' ilike '%%confirmed%%' $$,
    :'org'
  ),
  '...and a plain confirmation text is sent'
);
select isnt_empty(
  format(
    $$ select 1 from crm.notifications where agent_id = %L and kind = 'trial_booked' $$,
    :'rep_agent'
  ),
  '...and the assigned rep is notified in-app'
);
select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.trial_booked'
       and target_id = %L $$,
    :'org', :'lead_2'
  ),
  '...and audited'
);

-- A stale/past tap is recovered with a fresh offer, not an error --------------------------------

select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-00000000c002', 'whatsapp', '910000000001', '919000000091',
  '919000000091',
  jsonb_build_object('version', '1', 'type', 'data',
    'kind', 'interactive', 'data', jsonb_build_object('type', 'list_reply',
      'list_reply', jsonb_build_object('id', 'trial_slot::2000-01-01T00:00:00+00:00', 'title', 'pick'))),
  'ext-trial-4', now()
);
select tests.as_postgres();
select cmp_ok(
  (select count(*)::int from public.messages where organization_id = :'org'
   and conversation_address = '919000000091' and content->>'kind' = 'interactive_list'),
  '>', 1,
  'tapping a slot that has already passed re-sends a fresh offer instead of erroring'
);

-- Staff reschedule / cancel (deals.edit + lead visibility) ---------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.reschedule_trial_booking(%L, %L::timestamptz) $$, :'lead_2', :'slot_start'),
  '42501', null, 'a viewer cannot reschedule a trial booking'
);

select tests.as_user('rep.b@test.local');
select throws_ok(
  format($$ select crm.reschedule_trial_booking(%L, %L::timestamptz) $$, :'lead_2', :'slot_start'),
  'P0002', 'lead not found', 'own-scope: a different rep cannot reschedule this lead''s booking either'
);

select tests.as_user('owner@test.local');
select slot_start from crm.list_upcoming_trial_slots(:'org') order by slot_start desc limit 1 \gset
select crm.reschedule_trial_booking(:'lead_2', :'slot_start') as new_booking \gset

select isnt_empty(
  format($$ select 1 from crm.trial_bookings where id = %L and status = 'booked' $$, :'new_booking'),
  'reschedule_trial_booking creates a new booked row'
);
select is(
  (select count(*)::int from crm.trial_bookings where lead_id = :'lead_2' and status = 'booked'),
  1,
  '...and the earlier booking was cancelled, leaving exactly one active booking'
);
select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.trial_rescheduled' $$,
    :'org'
  ),
  '...audited'
);

select crm.cancel_trial_booking(:'new_booking');
select isnt_empty(
  format($$ select 1 from crm.trial_bookings where id = %L and status = 'cancelled' $$, :'new_booking'),
  'cancel_trial_booking cancels it'
);
select throws_ok(
  format($$ select crm.cancel_trial_booking(%L) $$, :'new_booking'),
  '22023', 'booking is not active', 'cancelling an already-cancelled booking is refused'
);

-- Capacity: once a slot is full, it drops off the list and a reschedule into it is refused -------

select tests.as_user('owner@test.local');
select slot_start from crm.list_upcoming_trial_slots(:'org') order by slot_start limit 1 \gset
select crm.reschedule_trial_booking(:'lead', :'slot_start');
select crm.reschedule_trial_booking(:'lead_2', :'slot_start');
select is_empty(
  format($$ select 1 from crm.list_upcoming_trial_slots(%L) s where s.slot_start = %L::timestamptz $$, :'org', :'slot_start'),
  'once a slot reaches capacity (2 here), it no longer appears in the upcoming list'
);

select tests.as_postgres();
select tests.create_user('third@test.local') as third_user \gset
select tests.as_user('owner@test.local');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', '910000000001', 'whatsapp', '919000000092', '{"name": "Third"}');
select contact_id as third from crm.contact_addresses
where organization_id = :'org' and address = '919000000092' \gset
select crm.find_or_create_lead(:'org', :'third', 'organic') as lead_3 \gset
select throws_ok(
  format($$ select crm.reschedule_trial_booking(%L, %L::timestamptz) $$, :'lead_3', :'slot_start'),
  '22023', 'slot is full', 'a third booking into the same (now-full) slot is refused'
);

-- Reminder sweep: in-app... well, this feature has no in-app notification for the lead itself --
-- audited regardless of channel, WhatsApp only with an approved template --------------------------

select tests.as_postgres();
update crm.trial_bookings set slot_start = now() + interval '1 hour', slot_end = now() + interval '2 hour'
where lead_id = :'lead' and status = 'booked';
select crm.sweep_trial_reminders();
select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.trial_reminder_sent'
       and target_id = %L and details->>'channel' = 'none' $$,
    :'org', :'lead'
  ),
  'the reminder sweep audits a none-channel attempt when no approved template exists yet'
);

insert into crm.templates (organization_id, organization_address, meta_id, name, category, language, status, components)
values (:'org', '910000000001', 'meta-trial-1', 'trial_class_reminder', 'UTILITY', 'en', 'APPROVED', '[]'::jsonb);
update crm.trial_bookings set slot_start = now() + interval '1 hour', slot_end = now() + interval '2 hour',
  reminder_sent_at = null
where lead_id = :'lead' and status = 'booked';
select crm.sweep_trial_reminders();

select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.trial_reminder_sent'
       and target_id = %L and details->>'channel' = 'whatsapp' $$,
    :'org', :'lead'
  ),
  'once a template is approved for the org''s own connected number, the sweep sends via WhatsApp'
);
select isnt_empty(
  format(
    $$ select 1 from public.messages where organization_id = %L and organization_address = '910000000001'
       and content->>'kind' = 'template' and content->'data'->>'name' = 'trial_class_reminder' $$,
    :'org'
  ),
  '...through the tenant''s own connected number, never a global credential'
);

select * from finish();
