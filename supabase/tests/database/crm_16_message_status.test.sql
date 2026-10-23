-- P2-08: status tracking -- forward-only status changes
-- (public.enforce_forward_only_status) and orphan handling
-- (public.apply_message_statuses).
begin;
\ir _helpers.psql

select plan(14);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');
insert into public.conversations (id, organization_id, organization_address, address, service, name)
values ('00000000-0000-0000-0000-0000000000e1', :'org', 'phone-1', '919000000010', 'whatsapp', 'Status test');

-- Forward-only: the normal ladder --------------------------------------------------------

select tests.as_service();
insert into public.messages (organization_id, conversation_id, service, organization_address, conversation_address, content, external_id)
values (:'org', '00000000-0000-0000-0000-0000000000e1', 'whatsapp', 'phone-1', '919000000010', '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb, 'wamid-ladder')
returning id as msg_ladder \gset

update public.messages set status = jsonb_build_object('sent', now()::text) where id = :'msg_ladder';
select is(
  (select status ? 'sent' from public.messages where id = :'msg_ladder'),
  true,
  'sent is recorded normally'
);

update public.messages set status = jsonb_build_object('delivered', now()::text) where id = :'msg_ladder';
select is(
  (select status ? 'delivered' from public.messages where id = :'msg_ladder'),
  true,
  'delivered is recorded normally (forward progression)'
);

-- A stale, newly-introduced lower rung (accepted, rank 2) must not appear
-- once delivered (rank 4) is already recorded -- out-of-order webhook
-- processing is the realistic cause (P2-01's async cron batching).
update public.messages set status = jsonb_build_object('accepted', now()::text) where id = :'msg_ladder';
select is(
  (select status ? 'accepted' from public.messages where id = :'msg_ladder'),
  false,
  'a stale "accepted" arriving after "delivered" is dropped, not displayed as a regression'
);
select is(
  (select status ? 'delivered' from public.messages where id = :'msg_ladder'),
  true,
  '...and "delivered" is still there, untouched'
);

-- Re-merging an EXISTING key's own value (not a new key) is never blocked --
-- it is the same rung restating itself, not a regression.
update public.messages set status = jsonb_build_object('delivered', (now() + interval '1 second')::text) where id = :'msg_ladder';
select is(
  (select status ? 'delivered' from public.messages where id = :'msg_ladder'),
  true,
  're-merging the same rung''s own value is never blocked'
);

-- "errors" is a side-channel, not a progress rung -- always free to update.
update public.messages set status = jsonb_build_object('errors', '["still trying"]'::jsonb) where id = :'msg_ladder';
select is(
  (select status -> 'errors' from public.messages where id = :'msg_ladder'),
  '["still trying"]'::jsonb,
  '"errors" updates freely regardless of rank'
);

-- Forward-only: the "failed" special case --------------------------------------------------

insert into public.messages (organization_id, conversation_id, service, organization_address, conversation_address, content, external_id)
values (:'org', '00000000-0000-0000-0000-0000000000e1', 'whatsapp', 'phone-1', '919000000010', '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb, 'wamid-failed-after-delivered')
returning id as msg_failed_late \gset

update public.messages set status = jsonb_build_object('delivered', now()::text) where id = :'msg_failed_late';
update public.messages set status = jsonb_build_object('failed', now()::text) where id = :'msg_failed_late';
select is(
  (select status ? 'failed' from public.messages where id = :'msg_failed_late'),
  false,
  'a stale "failed" arriving after "delivered" is dropped -- Meta does not walk back a real delivery'
);
select is(
  (select status ? 'delivered' from public.messages where id = :'msg_failed_late'),
  true,
  '...delivered stays the shown outcome'
);

insert into public.messages (organization_id, conversation_id, service, organization_address, conversation_address, content, external_id)
values (:'org', '00000000-0000-0000-0000-0000000000e1', 'whatsapp', 'phone-1', '919000000010', '{"version":"1","type":"text","kind":"text","text":"hi"}'::jsonb, 'wamid-failed-from-sent')
returning id as msg_failed_legit \gset

update public.messages set status = jsonb_build_object('sent', now()::text) where id = :'msg_failed_legit';
update public.messages set status = jsonb_build_object('pending', null, 'failed', now()::text) where id = :'msg_failed_legit';
select is(
  (select status ? 'failed' from public.messages where id = :'msg_failed_legit'),
  true,
  'a real failure following only "sent" (no delivered/read yet) is the common, legitimate case -- not blocked'
);

-- Orphan handling: apply_message_statuses --------------------------------------------------

select is(
  (select count(*) from public.apply_message_statuses(
    jsonb_build_array(jsonb_build_object('external_id', 'wamid-does-not-exist', 'status', jsonb_build_object('sent', now()::text)))
  )),
  0::bigint,
  'a status event for an unknown external_id matches nothing -- no row is fabricated'
);
select is(
  (select count(*)::int from public.messages where external_id = 'wamid-does-not-exist'),
  0,
  '...and no ghost row was created'
);

select is(
  (select array_agg(ext_id) from public.apply_message_statuses(
    jsonb_build_array(
      jsonb_build_object('external_id', 'wamid-ladder', 'status', jsonb_build_object('read', now()::text)),
      jsonb_build_object('external_id', 'wamid-does-not-exist', 'status', jsonb_build_object('read', now()::text))
    )
  ) as ext_id),
  array['wamid-ladder'],
  'a mixed batch updates the real row and silently skips the orphan, in one call'
);
select is(
  (select status ? 'read' from public.messages where id = :'msg_ladder'),
  true,
  '...the real row''s status was actually applied'
);

select tests.as_user('owner@test.local');
select throws_ok(
  $$ select public.apply_message_statuses('[]'::jsonb) $$,
  '42501', null,
  'a tenant owner cannot call apply_message_statuses directly (service-role only)'
);

select * from finish();
rollback;
