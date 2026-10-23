-- P2-09b: tags -- crm.tags/crm.conversation_tags, structurally mirroring
-- crm.teams/crm.team_members. RLS (members read, writes through
-- crm.create_tag & co., gated on 'conversations.view'), the unique-name
-- constraint, the color check, and conversation tagging/untagging.
begin;
\ir _helpers.psql

select plan(18);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('other.owner@test.local') as other_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');
insert into public.conversations (id, organization_id, organization_address, address, service, name)
values ('00000000-0000-0000-0000-0000000000f1', :'org', 'phone-1', '919000000020', 'whatsapp', 'Tag test');

-- Create, rename, recolor -----------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.create_tag(:'org', 'VIP') as tag_vip \gset
select isnt_empty(
  format($$ select 1 from crm.tags where id = %L $$, :'tag_vip'),
  'a member can create a tag'
);
select is(
  (select color from crm.tags where id = :'tag_vip'),
  'gray',
  'a new tag defaults to gray'
);

select crm.set_tag_color(:'tag_vip', 'red');
select is(
  (select color from crm.tags where id = :'tag_vip'),
  'red',
  'a member can recolor their org''s tag'
);

select crm.rename_tag(:'tag_vip', '  Priority  ');
select is(
  (select name from crm.tags where id = :'tag_vip'),
  'Priority',
  'rename trims whitespace, same as crm.rename_team'
);

select throws_ok(
  format($$ select crm.create_tag(%L, 'Priority') $$, :'org'),
  '23505', null, 'tag names are unique per org, same name twice fails'
);
select throws_ok(
  format($$ select crm.create_tag(%L, 'Priority') $$, :'org'),
  null, 'duplicate key value violates unique constraint "tags_organization_id_name_key"',
  '...on the expected constraint'
);
select throws_ok(
  format($$ select crm.set_tag_color(%L, 'turquoise') $$, :'tag_vip'),
  '23514', null, 'color is restricted to the fixed palette'
);
select throws_ok(
  format($$ select crm.create_tag(%L, '') $$, :'org'),
  '23514', null, 'an empty name is rejected'
);

-- Isolation ---------------------------------------------------------------------------------

select tests.as_user('other.owner@test.local');
select is_empty(
  format($$ select 1 from crm.tags where id = %L $$, :'tag_vip'),
  'another org cannot read this tag'
);
select throws_ok(
  format($$ select crm.rename_tag(%L, 'Stolen') $$, :'tag_vip'),
  '42501', null, 'nor rename it -- require_permission checks against the TAG''s own org'
);
select throws_ok(
  format($$ select crm.delete_tag(%L) $$, :'tag_vip'),
  '42501', null, 'nor delete it'
);
select throws_ok(
  format($$ select crm.set_conversation_tag('00000000-0000-0000-0000-0000000000f1', %L, true) $$, :'tag_vip'),
  '42501', null, 'nor tag org A''s conversation with it -- require_permission checks against the CONVERSATION''s org'
);

-- Tagging a conversation ---------------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.set_conversation_tag('00000000-0000-0000-0000-0000000000f1', :'tag_vip', true);
select isnt_empty(
  format(
    $$ select 1 from crm.conversation_tags where conversation_id = '00000000-0000-0000-0000-0000000000f1' and tag_id = %L $$,
    :'tag_vip'
  ),
  'tagging a conversation creates the join row'
);

select crm.set_conversation_tag('00000000-0000-0000-0000-0000000000f1', :'tag_vip', true);
select is(
  (select count(*)::int from crm.conversation_tags where conversation_id = '00000000-0000-0000-0000-0000000000f1'),
  1,
  'tagging twice is idempotent, not a duplicate row'
);

select crm.set_conversation_tag('00000000-0000-0000-0000-0000000000f1', :'tag_vip', false);
select is_empty(
  format(
    $$ select 1 from crm.conversation_tags where conversation_id = '00000000-0000-0000-0000-0000000000f1' and tag_id = %L $$,
    :'tag_vip'
  ),
  'untagging removes the join row'
);
select lives_ok(
  $$ select crm.set_conversation_tag('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000000', false) $$,
  'untagging a tag that was never applied is a no-op, not an error'
);

-- A tag from a DIFFERENT org than the conversation must be rejected.
select tests.as_user('other.owner@test.local');
select crm.create_tag(:'other', 'Foreign') as tag_foreign \gset
select tests.as_user('owner@test.local');
select throws_ok(
  format(
    $$ select crm.set_conversation_tag('00000000-0000-0000-0000-0000000000f1', %L, true) $$,
    :'tag_foreign'
  ),
  '22023', 'tag not found', 'a tag from a different org cannot be applied to this conversation'
);

select crm.delete_tag(:'tag_vip');
select is_empty(
  format($$ select 1 from crm.tags where id = %L $$, :'tag_vip'),
  'a deleted tag is gone'
);

select * from finish();
rollback;
