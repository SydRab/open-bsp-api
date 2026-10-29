-- P3-07d: tasks and follow-up reminders. CRUD gated on deals.edit +
-- lead_scope visibility; the reminder sweep (crm.sweep_task_reminders)
-- always notifies in-app, and additionally sends a WhatsApp template
-- through the tenant's own connected number when the assignee has set
-- their own number and an approved template exists -- never a global
-- credential (CLAUDE.md's tenant-isolated-billing mandate), and always
-- audited (the local-telemetry mandate) regardless of channel.
begin;
\ir _helpers.psql

select plan(18);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_user('viewer@test.local') as viewer_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset

select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'viewer@test.local', 'viewer') as viewer_agent \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', '910000000001', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', '910000000001', 'whatsapp', '919000000070', '{"name": "Harish"}');
select contact_id as harish from crm.contact_addresses
where organization_id = :'org' and address = '919000000070' \gset

select tests.as_user('owner@test.local');
select crm.find_or_create_lead(:'org', :'harish', 'organic') as lead_harish \gset
select crm.assign_lead(:'lead_harish', :'rep_agent');

-- The platform template was seeded on org creation --------------------------------------------

select isnt_empty(
  format(
    $$ select 1 from crm.organization_pack_items
       where organization_id = %L and kind = 'message_template' and item_key = 'internal_task_reminder' $$,
    :'org'
  ),
  'the internal_task_reminder template was seeded on org creation'
);

-- set_my_whatsapp_address: self-service, validated ---------------------------------------------

select tests.as_user('rep@test.local');
select throws_ok(
  format($$ select crm.set_my_whatsapp_address(%L, 'not-a-number') $$, :'org'),
  '22023', null, 'a non-digits address is rejected'
);
select lives_ok(
  format($$ select crm.set_my_whatsapp_address(%L, '919000000071') $$, :'org'),
  'the rep sets their own WhatsApp number'
);
select is(
  (select whatsapp_address from crm.member_roles where agent_id = :'rep_agent'),
  '919000000071',
  '...and it sticks'
);

-- create_task: permission gate + lead_scope visibility ------------------------------------------

select tests.as_user('viewer@test.local');
select throws_ok(
  format($$ select crm.create_task(%L, 'Call back', now() - interval '1 hour') $$, :'lead_harish'),
  '42501', null, 'a viewer (no deals.edit) cannot create a task'
);

select tests.as_user('owner@test.local');
select crm.create_task(:'lead_harish', 'Call back about pricing', now() - interval '1 hour', :'rep_agent') as task_id \gset
select isnt_empty(
  format($$ select 1 from crm.tasks where id = %L $$, :'task_id'),
  'the owner creates an overdue task assigned to the rep'
);
select isnt_empty(
  format($$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.task_created' $$, :'org'),
  '...audit-logged'
);

-- complete_task / update_task clears/keeps reminder_sent_at correctly --------------------------

select crm.complete_task(:'task_id');
select isnt_empty(
  format($$ select 1 from crm.tasks where id = %L and completed_at is not null $$, :'task_id'),
  'complete_task marks it done'
);
select crm.complete_task(:'task_id', false);
select isnt_empty(
  format($$ select 1 from crm.tasks where id = %L and completed_at is null $$, :'task_id'),
  'complete_task(false) reopens it'
);

-- The reminder sweep: in-app always, WhatsApp only once both prerequisites are met -------------

select tests.as_postgres();
select crm.sweep_task_reminders();
select isnt_empty(
  format($$ select 1 from crm.notifications where agent_id = %L and kind = 'task_due' $$, :'rep_agent'),
  'the sweep writes an in-app notification regardless of WhatsApp readiness'
);
select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.task_reminder_sent'
       and details->>'channel' = 'in_app' $$,
    :'org'
  ),
  '...and audits it as in_app -- no approved template exists yet'
);
select isnt_empty(
  format($$ select 1 from crm.tasks where id = %L and reminder_sent_at is not null $$, :'task_id'),
  '...and marks the task reminded, so it is not reprocessed'
);

select crm.sweep_task_reminders();
select is(
  (select count(*)::int from crm.notifications where agent_id = :'rep_agent' and kind = 'task_due'),
  1,
  'running the sweep again does not double-notify -- reminder_sent_at makes it a no-op'
);

-- Now approve a template for the org's connected number and re-test the WhatsApp path -----------

select tests.as_postgres();
insert into crm.templates (organization_id, organization_address, meta_id, name, category, language, status, components)
values (:'org', '910000000001', 'meta-1', 'internal_task_reminder', 'UTILITY', 'en', 'APPROVED', '[]'::jsonb);

select tests.as_user('owner@test.local');
select crm.create_task(:'lead_harish', 'Follow up on documents', now() - interval '1 hour', :'rep_agent') as task_2 \gset

select tests.as_postgres();
select crm.sweep_task_reminders();

select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.task_reminder_sent'
       and details->>'channel' = 'whatsapp' and (details->>'task_id')::uuid = %L $$,
    :'org', :'task_2'
  ),
  'with an approved template and a set number, the sweep sends via WhatsApp'
);
select isnt_empty(
  format(
    $$ select 1 from public.messages where organization_id = %L and organization_address = '910000000001'
       and conversation_address = '919000000071' and content->>'kind' = 'template' $$,
    :'org'
  ),
  '...and a real outbound template message row exists, through the tenant''s own connected number'
);
select is(
  (select service from public.conversations
   where organization_id = :'org' and organization_address = '910000000001' and address = '919000000071'),
  'whatsapp'::public.service,
  '...on a normal conversation between the org''s number and the rep''s own number'
);

-- Cross-visibility: a different rep cannot see/act on this lead's tasks -------------------------

select tests.as_postgres();
select tests.create_user('rep.b@test.local') as rep_b_user \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep.b@test.local', 'sales_rep') as rep_b \gset

select tests.as_user('rep.b@test.local');
select is_empty(
  format($$ select 1 from crm.tasks where id = %L $$, :'task_id'),
  'own scope: a different rep cannot see this lead''s tasks'
);
select throws_ok(
  format($$ select crm.complete_task(%L) $$, :'task_id'),
  'P0002', 'task not found', '...nor act on them -- "not found," not "forbidden"'
);

select * from finish();
