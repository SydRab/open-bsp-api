-- P2-09e: canned replies -- crm.canned_replies, gated on 'templates.manage'
-- for writes (not the viewer-excluding 'messages.send' assignment used, nor
-- the everyone-has-it 'conversations.view' tags used) while reads stay open
-- to any org member, echoing the admins-manage/members-read split the old,
-- dropped upstream `public.quick_replies` policies had.
begin;
\ir _helpers.psql

select plan(13);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('other.owner@test.local') as other_user \gset
select tests.create_user('marketer@test.local') as marketer_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

select tests.add_member(:'org', 'marketer@test.local', 'marketing') as marketer_agent \gset
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset

-- Create, update ----------------------------------------------------------------------------

select tests.as_user('owner@test.local');
select crm.create_canned_reply(:'org', 'Greeting', '  Hi, thanks for reaching out!  ') as reply_greeting \gset
select isnt_empty(
  format($$ select 1 from crm.canned_replies where id = %L $$, :'reply_greeting'),
  'an owner can create a canned reply'
);
select is(
  (select content from crm.canned_replies where id = :'reply_greeting'),
  'Hi, thanks for reaching out!',
  'create trims the content, same as crm.create_tag trims names'
);

select crm.update_canned_reply(:'reply_greeting', '  Hello!  ', '  Updated body.  ');
select is(
  (select name from crm.canned_replies where id = :'reply_greeting'),
  'Hello!',
  'update trims the new name'
);
select is(
  (select content from crm.canned_replies where id = :'reply_greeting'),
  'Updated body.',
  'update trims the new content'
);

select throws_ok(
  format($$ select crm.create_canned_reply(%L, 'Hello!', 'Another one') $$, :'org'),
  '23505', null, 'reply names are unique per org, same name twice fails'
);
select throws_ok(
  format($$ select crm.create_canned_reply(%L, '', 'Non-empty content') $$, :'org'),
  '23514', null, 'an empty name is rejected'
);
select throws_ok(
  format($$ select crm.create_canned_reply(%L, 'Valid name', '') $$, :'org'),
  '23514', null, 'empty content is rejected too'
);

-- Permission gate: templates.manage, not conversations.view or messages.send ----------------

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.create_canned_reply(%L, 'Rep reply', 'Should not work') $$, :'org'),
  '42501', null, 'a sales_rep (messages.send, no templates.manage) cannot create a canned reply'
);
select isnt_empty(
  format($$ select 1 from crm.canned_replies where id = %L $$, :'reply_greeting'),
  'but can still read it -- reading is open to any member, not gated on templates.manage'
);

select tests.as_user('marketer@test.local');
select lives_ok(
  format(
    $$ select crm.create_canned_reply(%L, 'Marketing reply', 'A marketing-authored reply') $$,
    :'org'
  ),
  'a marketing-role member (has templates.manage by default) can create a canned reply'
);

-- Isolation -----------------------------------------------------------------------------------

select tests.as_user('other.owner@test.local');
select is_empty(
  format($$ select 1 from crm.canned_replies where id = %L $$, :'reply_greeting'),
  'another org cannot read this org''s canned reply'
);
select throws_ok(
  format($$ select crm.update_canned_reply(%L, 'Stolen', 'Stolen') $$, :'reply_greeting'),
  '42501', null, 'nor update it -- require_permission checks against the REPLY''s own org'
);
select throws_ok(
  format($$ select crm.delete_canned_reply(%L) $$, :'reply_greeting'),
  '42501', null, 'nor delete it'
);

select * from finish();
rollback;
