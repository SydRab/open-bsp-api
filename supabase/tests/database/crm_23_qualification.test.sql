-- P3-04: qualification engine. The question SET (crm.organization_pack_
-- items kind qualification_question) and custom fields already existed;
-- this tests the new orchestration -- resumable state, scoring, nudges --
-- against the trading_institute pack's real 5 questions.
begin;
\ir _helpers.psql

select plan(34);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_org('owner@test.local', 'Orion Academy') as org \gset
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset

-- Seeding on org creation -------------------------------------------------------------------

select is(
  (select count(*)::int from crm.qualification_question_scores where organization_id = :'org'),
  8,
  'the trading_institute preset seeds 8 answer-score rows (5 capital_range + 3 learning_goal)'
);
select is(
  (select count(*)::int from crm.qualification_score_thresholds where organization_id = :'org'),
  3,
  '...and 3 score bands'
);
select is(
  (select t.status from crm.qualification_score_thresholds t where t.organization_id = :'org' and t.min_score = 6),
  'qualified',
  'the top band (score >= 6) is qualified'
);
select is(
  (select q.key from crm.qualification_score_thresholds t
   join crm.lead_qualities q on q.id = t.quality_id
   where t.organization_id = :'org' and t.min_score = 6),
  'high_intent',
  '...mapped to high_intent (resolved from the preset quality_key)'
);

-- Catalog CRUD permission gate (organization.manage) ----------------------------------------

select tests.as_user('owner@test.local');
select lives_ok(
  format($$ select crm.set_qualification_question_score(%L, 'experience_level', 'experienced', 5) $$, :'org'),
  'the owner can add a score rule for a field this task left unscored by default'
);
select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.set_qualification_question_score(%L, 'experience_level', 'experienced', 9) $$, :'org'),
  '42501',
  null,
  'a viewer cannot edit the scoring catalog'
);

-- Fixtures for the message-driven tests ------------------------------------------------------

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');
insert into public.conversations (id, organization_id, organization_address, address, service, name)
values
  ('00000000-0000-0000-0000-0000000000f6', :'org', 'phone-1', '919000000050', 'whatsapp', 'Full walk'),
  ('00000000-0000-0000-0000-0000000000f7', :'org', 'phone-1', '919000000051', 'whatsapp', 'Nudged'),
  ('00000000-0000-0000-0000-0000000000f8', :'org', 'phone-1', '919000000052', 'whatsapp', 'Resuming'),
  ('00000000-0000-0000-0000-0000000000f9', :'org', 'phone-1', '919000000053', 'whatsapp', 'Off by default');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values
  (:'org', 'phone-1', 'whatsapp', '919000000050', '{"name": "Full"}'),
  (:'org', 'phone-1', 'whatsapp', '919000000051', '{"name": "Nudged"}'),
  (:'org', 'phone-1', 'whatsapp', '919000000052', '{"name": "Resuming"}'),
  (:'org', 'phone-1', 'whatsapp', '919000000053', '{"name": "Off"}');

select contact_id as full_walk from crm.contact_addresses
where organization_id = :'org' and address = '919000000050' \gset
select contact_id as nudged from crm.contact_addresses
where organization_id = :'org' and address = '919000000051' \gset
select contact_id as resuming from crm.contact_addresses
where organization_id = :'org' and address = '919000000052' \gset
select contact_id as off_contact from crm.contact_addresses
where organization_id = :'org' and address = '919000000053' \gset

-- Off by default: a lead is created (by the instant-welcome trigger) but no question is asked --

select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000f9', 'whatsapp', 'phone-1', '919000000053',
  '919000000053', '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb,
  'wamid-qual-off-1', '2026-10-25T12:00:00Z'
);

select is(
  (select status from crm.leads where organization_id = :'org' and contact_id = :'off_contact'),
  'open',
  'a lead still exists even with qualification.auto_start off'
);
select is_empty(
  format($$ select 1 from crm.lead_qualification_state s
            join crm.leads l on l.id = s.lead_id
            where l.contact_id = %L $$, :'off_contact'),
  'no qualification state is created while auto_start is off'
);

-- Turn auto_start on for the rest of the tests -----------------------------------------------

select lives_ok(
  format($$ select crm.set_setting(%L, 'qualification.auto_start', 'true'::jsonb) $$, :'org'),
  'the owner turns qualification auto-start on'
);

-- Full walk: all 5 questions, in pack order, scored only on capital_range + learning_goal -----

select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000f6', 'whatsapp', 'phone-1', '919000000050',
  '919000000050', '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb,
  'wamid-qual-full-1', '2026-10-25T12:00:00Z'
);

select results_eq(
  format($$ select current_question_key from crm.lead_qualification_state s
            join crm.leads l on l.id = s.lead_id
            where l.organization_id = %L and l.contact_id = %L $$, :'org', :'full_walk'),
  $$ values ('ask_experience'::text) $$,
  'the first question asked (by pack sort_order) is ask_experience'
);
select is(
  (select content->>'kind' from public.messages
   where conversation_id = '00000000-0000-0000-0000-0000000000f6' and sender_address is null),
  'interactive_buttons',
  'experience_level has 3 options -> delivered as buttons'
);

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000f6', 'whatsapp', 'phone-1', '919000000050',
  '919000000050',
  '{"version":"1","type":"data","kind":"interactive","data":{"type":"button_reply","button_reply":{"id":"ask_experience::beginner","title":"Beginner"}}}'::jsonb,
  'wamid-qual-full-2', '2026-10-25T12:01:00Z'
);

select is(
  (select custom_fields->>'experience_level' from crm.contacts where id = :'full_walk'),
  'beginner',
  'the button tap writes the answer to the matching custom field'
);
select is(
  (select current_question_key from crm.lead_qualification_state s join crm.leads l on l.id = s.lead_id
   where l.contact_id = :'full_walk'),
  'ask_market',
  'advances to the next unanswered question (ask_market)'
);
select is(
  exists(
    select 1 from public.messages
    where conversation_id = '00000000-0000-0000-0000-0000000000f6' and sender_address is null
      and content->>'kind' = 'interactive_list'
  ),
  true,
  'preferred_market has 5 options -> delivered as a list (same-transaction inserts share one now(), so check existence, not recency)'
);

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000f6', 'whatsapp', 'phone-1', '919000000050',
  '919000000050',
  '{"version":"1","type":"data","kind":"interactive","data":{"type":"list_reply","list_reply":{"id":"ask_market::equity","title":"Equity"}}}'::jsonb,
  'wamid-qual-full-3', '2026-10-25T12:02:00Z'
);

select results_eq(
  format($$ select custom_fields->'preferred_market' from crm.contacts where id = %L $$, :'full_walk'),
  $$ values ('["equity"]'::jsonb) $$,
  'a multi_select field is written as a one-element array (the confirmed v1 scope cut)'
);

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000f6', 'whatsapp', 'phone-1', '919000000050',
  '919000000050',
  '{"version":"1","type":"data","kind":"interactive","data":{"type":"button_reply","button_reply":{"id":"ask_goal::full_time","title":"Full-time"}}}'::jsonb,
  'wamid-qual-full-4', '2026-10-25T12:03:00Z'
);
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000f6', 'whatsapp', 'phone-1', '919000000050',
  '919000000050',
  '{"version":"1","type":"data","kind":"interactive","data":{"type":"list_reply","list_reply":{"id":"ask_capital::above_10l","title":"Above 10L"}}}'::jsonb,
  'wamid-qual-full-5', '2026-10-25T12:04:00Z'
);

select is(
  (select status from crm.leads where organization_id = :'org' and contact_id = :'full_walk'),
  'open',
  'still open before the last question is answered'
);

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000f6', 'whatsapp', 'phone-1', '919000000050',
  '919000000050',
  '{"version":"1","type":"data","kind":"interactive","data":{"type":"button_reply","button_reply":{"id":"ask_timing::morning","title":"Morning"}}}'::jsonb,
  'wamid-qual-full-6', '2026-10-25T12:05:00Z'
);

select is(
  (select score from crm.leads where organization_id = :'org' and contact_id = :'full_walk'),
  7,
  'the last answer completes qualification; score = 3 (full_time) + 4 (above_10l) = 7'
);
select is(
  (select status from crm.leads where organization_id = :'org' and contact_id = :'full_walk'),
  'qualified',
  'score 7 clears the >=6 band -> qualified'
);
select is(
  (select q.key from crm.leads l join crm.lead_qualities q on q.id = l.quality_id
   where l.organization_id = :'org' and l.contact_id = :'full_walk'),
  'high_intent',
  '...and high_intent'
);
select is(
  (select completed_at is not null from crm.lead_qualification_state s join crm.leads l on l.id = s.lead_id
   where l.contact_id = :'full_walk'),
  true,
  'the state row is marked completed'
);
select results_eq(
  format($$ select action from crm.audit_log where organization_id = %L
            and target_id = (select id::text from crm.leads where contact_id = %L)
            and (action like 'lead.%%qualif%%' or action = 'lead.answer_recorded')
            order by action $$, :'org', :'full_walk'),
  $$ values ('lead.answer_recorded'::text), ('lead.answer_recorded'), ('lead.answer_recorded'),
            ('lead.answer_recorded'), ('lead.answer_recorded'),
            ('lead.qualification_completed'), ('lead.qualification_started') $$,
  'the full audit trail is recorded'
);

-- Nudges: an unrecognized reply re-prompts, up to the org's max_nudges (default 2) -----------

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000f7', 'whatsapp', 'phone-1', '919000000051',
  '919000000051', '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb,
  'wamid-qual-nudge-1', '2026-10-25T12:00:00Z'
);

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000f7', 'whatsapp', 'phone-1', '919000000051',
  '919000000051', '{"version":"1","type":"text","kind":"text","text":"what?"}'::jsonb,
  'wamid-qual-nudge-2', '2026-10-25T12:01:00Z'
);
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000f7', 'whatsapp', 'phone-1', '919000000051',
  '919000000051', '{"version":"1","type":"text","kind":"text","text":"still there?"}'::jsonb,
  'wamid-qual-nudge-3', '2026-10-25T12:02:00Z'
);

select is(
  (select nudge_count from crm.lead_qualification_state s join crm.leads l on l.id = s.lead_id
   where l.contact_id = :'nudged'),
  2,
  'two unrecognized replies use up the default 2-nudge budget'
);
select is(
  (select count(*)::int from public.messages
   where conversation_id = '00000000-0000-0000-0000-0000000000f7' and sender_address is null),
  3,
  '3 outbound messages so far: the initial question + 2 nudges'
);

insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000f7', 'whatsapp', 'phone-1', '919000000051',
  '919000000051', '{"version":"1","type":"text","kind":"text","text":"hello??"}'::jsonb,
  'wamid-qual-nudge-4', '2026-10-25T12:03:00Z'
);

select is(
  (select count(*)::int from public.messages
   where conversation_id = '00000000-0000-0000-0000-0000000000f7' and sender_address is null),
  3,
  'past the budget, a further unrecognized reply sends nothing more'
);
select is(
  (select status from crm.leads where organization_id = :'org' and contact_id = :'nudged'),
  'open',
  '...and the lead is simply left open for manual follow-up, not auto-dropped'
);

-- Resuming: a field already answered (some other way) before qualification starts is skipped -

select tests.as_postgres();
update crm.contacts set custom_fields = '{"experience_level": "experienced"}'::jsonb
where id = :'resuming';

select tests.as_service();
insert into public.messages (
  organization_id, conversation_id, service, organization_address, conversation_address,
  sender_address, content, external_id, timestamp
) values (
  :'org', '00000000-0000-0000-0000-0000000000f8', 'whatsapp', 'phone-1', '919000000052',
  '919000000052', '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb,
  'wamid-qual-resume-1', '2026-10-25T12:00:00Z'
);

select is(
  (select current_question_key from crm.lead_qualification_state s join crm.leads l on l.id = s.lead_id
   where l.contact_id = :'resuming'),
  'ask_market',
  'a pre-filled field is skipped -- the engine resumes at the next unanswered question'
);

-- The cron sweep nudges a stalled lead whose question timed out, direct unit test -----------

select tests.as_postgres();
update crm.lead_qualification_state s set asked_at = now() - interval '7 hours'
from crm.leads l where l.id = s.lead_id and l.contact_id = :'nudged';
-- nudge_count is already at the 2-of-2 budget from the earlier scenario --
-- the sweep must still honor it and do nothing.
select crm.sweep_qualification_nudges();
select is(
  (select count(*)::int from public.messages
   where conversation_id = '00000000-0000-0000-0000-0000000000f7' and sender_address is null),
  3,
  'the cron sweep also respects an already-exhausted nudge budget'
);

update crm.lead_qualification_state s set asked_at = now() - interval '7 hours', nudge_count = 0
from crm.leads l where l.id = s.lead_id and l.contact_id = :'resuming';
select crm.sweep_qualification_nudges();
select is(
  (select nudge_count from crm.lead_qualification_state s join crm.leads l on l.id = s.lead_id
   where l.contact_id = :'resuming'),
  1,
  'a stalled question past the timeout gets nudged by the cron sweep'
);

-- Direct scoring unit tests for the other two bands ------------------------------------------

select tests.as_postgres();
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', 'phone-1', 'whatsapp', '919000000054', '{"name": "Low"}');
select contact_id as low_contact from crm.contact_addresses
where organization_id = :'org' and address = '919000000054' \gset
update crm.contacts set custom_fields = '{"capital_range": "under_50k", "learning_goal": "understand_basics"}'::jsonb
where id = :'low_contact';
select crm._ensure_lead(:'org', :'low_contact', 'organic') as low_lead \gset
insert into crm.lead_qualification_state (lead_id, organization_id) values (:'low_lead', :'org');
select crm._score_and_complete_qualification(:'org', :'low_lead', :'low_contact');

select is(
  (select score from crm.leads where id = :'low_lead'),
  2,
  'capital=under_50k(1) + goal=understand_basics(1) = 2'
);
select is(
  (select status from crm.leads where id = :'low_lead'),
  'unqualified',
  'score 2 lands in the lowest band -> unqualified'
);

insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', 'phone-1', 'whatsapp', '919000000055', '{"name": "Medium"}');
select contact_id as med_contact from crm.contact_addresses
where organization_id = :'org' and address = '919000000055' \gset
update crm.contacts set custom_fields = '{"capital_range": "between_50k_2l", "learning_goal": "part_time"}'::jsonb
where id = :'med_contact';
select crm._ensure_lead(:'org', :'med_contact', 'organic') as med_lead \gset
insert into crm.lead_qualification_state (lead_id, organization_id) values (:'med_lead', :'org');
select crm._score_and_complete_qualification(:'org', :'med_lead', :'med_contact');

select is(
  (select status from crm.leads where id = :'med_lead'),
  'qualified',
  'capital=between_50k_2l(2) + goal=part_time(2) = 4 -> medium band -> qualified'
);
select is(
  (select q.key from crm.leads l join crm.lead_qualities q on q.id = l.quality_id where l.id = :'med_lead'),
  'medium_intent',
  '...and medium_intent'
);

-- Cross-org isolation on the scoring catalog -------------------------------------------------

select tests.create_user('other.owner@test.local') as other_user \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

select isnt(
  (select count(*)::int from crm.qualification_question_scores where organization_id = :'other'),
  0,
  'a second org gets its own independently-seeded scoring rows'
);
select is_empty(
  format($$ select 1 from crm.qualification_question_scores
            where organization_id = %L and field_key = 'experience_level' $$, :'other'),
  '...and does not see the first org''s manually-added rule (experience_level)'
);

select * from finish();
rollback;
