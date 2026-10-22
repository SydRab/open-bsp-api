-- P2-01: crm.webhook_events. RLS posture (service_role only, despite the
-- blanket schema grant), the claim/replay/purge functions it ships with.
begin;
\ir _helpers.psql

select plan(20);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset

-- Who can see the table directly ----------------------------------------------------

select tests.as_user('owner@test.local');
select is_empty(
  'select 1 from crm.webhook_events',
  'a tenant owner sees no rows (no policy at all, not even 0 rows of their own)'
);
select throws_ok(
  $$ insert into crm.webhook_events (service, dedupe_key, raw_body, signature_valid)
     values ('whatsapp', 'x', '{}', true) $$,
  '42501', null, 'and cannot insert one'
);

select tests.as_api_key('anon-key');
select is_empty(
  'select 1 from crm.webhook_events',
  'an anon caller sees no rows either, despite the blanket schema-level grant'
);
select throws_ok(
  $$ insert into crm.webhook_events (service, dedupe_key, raw_body, signature_valid)
     values ('whatsapp', 'x', '{}', true) $$,
  '42501', null, 'and cannot insert one'
);

-- service_role bypasses RLS, same as every other platform-infra table ---------------

select tests.as_service();
insert into crm.webhook_events (service, dedupe_key, raw_body, signature_valid)
values ('whatsapp', 'dedupe-1', '{"entry":[]}', true)
returning id as event1 \gset
select isnt_empty(
  'select 1 from crm.webhook_events',
  'service_role can read what it just inserted'
);

select throws_ok(
  $$ insert into crm.webhook_events (service, dedupe_key, raw_body, signature_valid)
     values ('whatsapp', 'dedupe-1', '{}', true) $$,
  '23505', null, 'the same (service, dedupe_key) pair cannot be inserted twice (Meta retry dedupe)'
);

-- claim_webhook_event ---------------------------------------------------------------

select results_eq(
  format($$ select raw_body, attempts from crm.claim_webhook_event(%L) $$, :'event1'),
  $$ values ('{"entry":[]}'::text, 1) $$,
  'claiming an unprocessed row bumps attempts to 1 and returns its raw_body'
);
select ok(
  (select last_attempt_at from crm.webhook_events where id = :'event1') is not null,
  'last_attempt_at is set by the claim'
);
select results_eq(
  format($$ select attempts from crm.claim_webhook_event(%L) $$, :'event1'),
  $$ values (2) $$,
  'claiming again (still unprocessed) bumps attempts again, to 2 -- this is what drives the cron backoff'
);

update crm.webhook_events set processed_at = now() where id = :'event1';
select is_empty(
  format($$ select 1 from crm.claim_webhook_event(%L) $$, :'event1'),
  'once processed_at is set, claiming returns nothing'
);
select is(
  (select attempts from crm.webhook_events where id = :'event1'),
  2,
  'and does not bump attempts again'
);

-- replay_webhook_event ----------------------------------------------------------------

select crm.replay_webhook_event(:'event1');
select results_eq(
  format($$ select processed_at, attempts, processing_error, last_attempt_at
            from crm.webhook_events where id = %L $$, :'event1'),
  $$ values (null::timestamptz, 0, null::text, null::timestamptz) $$,
  'replay clears processed_at, attempts, processing_error and last_attempt_at'
);
select results_eq(
  format($$ select raw_body, attempts from crm.claim_webhook_event(%L) $$, :'event1'),
  $$ values ('{"entry":[]}'::text, 1) $$,
  'so the row is claimable again afterwards'
);

-- purge_webhook_events ------------------------------------------------------------------

insert into crm.webhook_events (service, dedupe_key, raw_body, signature_valid, received_at)
values ('whatsapp', 'old-one', '{}', true, now() - interval '15 days')
returning id as old_event \gset
insert into crm.webhook_events (service, dedupe_key, raw_body, signature_valid, received_at)
values ('whatsapp', 'recent-one', '{}', true, now() - interval '1 day')
returning id as recent_event \gset

select crm.purge_webhook_events();

select is_empty(
  format($$ select 1 from crm.webhook_events where id = %L $$, :'old_event'),
  'a row older than 14 days is purged'
);
select isnt_empty(
  format($$ select 1 from crm.webhook_events where id = %L $$, :'recent_event'),
  'a recent row is left alone'
);
select isnt_empty(
  format($$ select 1 from crm.webhook_events where id = %L $$, :'event1'),
  'and so is the one from earlier in this test (well within the window)'
);

-- Grant surface -------------------------------------------------------------------------

select is(
  (select bool_and(privilege_type = 'EXECUTE') from information_schema.routine_privileges
    where routine_schema = 'crm' and routine_name = 'claim_webhook_event' and grantee = 'service_role'),
  true,
  'claim_webhook_event is executable by service_role'
);
select is_empty(
  $$ select 1 from information_schema.routine_privileges
     where routine_schema = 'crm' and routine_name = 'claim_webhook_event' and grantee = 'authenticated' $$,
  'but not granted to authenticated (security definer functions are access-controlled by grant, not by a check inside)'
);
select is_empty(
  $$ select 1 from information_schema.routine_privileges
     where routine_schema = 'crm' and routine_name = 'replay_webhook_event' and grantee = 'authenticated' $$,
  'same for replay_webhook_event'
);
select is_empty(
  $$ select 1 from information_schema.routine_privileges
     where routine_schema = 'crm' and routine_name = 'purge_webhook_events' and grantee = 'authenticated' $$,
  'and purge_webhook_events'
);

select * from finish();
rollback;
