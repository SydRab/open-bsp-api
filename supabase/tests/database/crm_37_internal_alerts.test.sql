-- P3-12: internal WhatsApp alerts. crm._send_internal_whatsapp_alert
-- (the resolve-address/resolve-sender/find-template/send sequence,
-- factored out of crm.sweep_task_reminders, P3-07d) and its two new
-- callers: crm.z_notify_on_assignment (a trigger, fires on both the
-- manual assign_lead path and the auto-assign/_ensure_assignment path)
-- and crm.sweep_speed_to_lead_escalation's three existing steps.
begin;
\ir _helpers.psql

select plan(14);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('rep@test.local') as rep_user \gset
select tests.create_user('rep.b@test.local') as rep_b_user \gset
select tests.create_org('owner@test.local', 'Alerts Academy') as org \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep@test.local', 'sales_rep') as rep_agent \gset
select tests.as_user('owner@test.local');
select tests.add_member(:'org', 'rep.b@test.local', 'sales_rep') as rep_b_agent \gset

-- The seed on org creation --------------------------------------------------------------------

select isnt_empty(
  format(
    $$ select 1 from crm.organization_pack_items
       where organization_id = %L and kind = 'message_template' and item_key = 'internal_lead_alert' $$,
    :'org'
  ),
  'the internal_lead_alert template was seeded on org creation'
);

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', '910000000001', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address, extra)
values (:'org', '910000000001', 'whatsapp', '919000000701', '{"name": "Lead"}');
select contact_id as c_lead from crm.contact_addresses where organization_id = :'org' and address = '919000000701' \gset

select tests.as_user('owner@test.local');
select crm.find_or_create_lead(:'org', :'c_lead', 'organic') as lead_id \gset

-- crm._send_internal_whatsapp_alert: graceful no-ops --------------------------------------------

select tests.as_postgres();
select is(
  crm._send_internal_whatsapp_alert(:'org', :'rep_agent', 'internal_lead_alert', 'hi'),
  null::uuid,
  'no whatsapp_address set on the agent -- a graceful no-op, not an error'
);

select tests.as_user('rep@test.local');
select crm.set_my_whatsapp_address(:'org', '919000000702');

select tests.as_postgres();
select is(
  crm._send_internal_whatsapp_alert(:'org', :'rep_agent', 'internal_lead_alert', 'hi'),
  null::uuid,
  'an address is set but no APPROVED template exists yet -- still a graceful no-op'
);

-- z_notify_on_assignment: fires on the manual assign_lead path -----------------------------------

select tests.as_user('owner@test.local');
select crm.assign_lead(:'lead_id', :'rep_agent');

-- crm.notifications' own RLS is "only my own rows" (P3-06) -- read it as
-- postgres here, not as owner, who has no visibility into another
-- agent's notification row.
select tests.as_postgres();
select isnt_empty(
  format(
    $$ select 1 from crm.notifications where organization_id = %L and agent_id = %L and kind = 'lead_assigned' $$,
    :'org', :'rep_agent'
  ),
  'assigning a lead manually creates a lead_assigned in-app notification'
);
select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.assignment_notified'
       and details->>'channel' = 'in_app' $$,
    :'org'
  ),
  '...audited as in_app -- no approved template exists yet'
);

-- unassign_lead sets assigned_to to null -- the trigger''s own WHEN guard skips it ---------------

select tests.as_user('owner@test.local');
select crm.unassign_lead(:'lead_id');
select tests.as_postgres();
select is(
  (select count(*)::int from crm.notifications where organization_id = :'org' and kind = 'lead_assigned'),
  1,
  'unassigning never fires the assignment trigger -- still exactly one lead_assigned notification'
);

-- Approve a template for the org''s connected number and re-test the WhatsApp path ---------------

select tests.as_postgres();
insert into crm.templates (organization_id, organization_address, meta_id, name, category, language, status, components)
values (:'org', '910000000001', 'meta-2', 'internal_lead_alert', 'UTILITY', 'en', 'APPROVED', '[]'::jsonb);

select tests.as_user('owner@test.local');
select crm.assign_lead(:'lead_id', :'rep_agent');

select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.assignment_notified'
       and details->>'channel' = 'whatsapp' $$,
    :'org'
  ),
  'with an approved template and a set number, assignment now sends via WhatsApp'
);
select isnt_empty(
  format(
    $$ select 1 from public.messages where organization_id = %L and organization_address = '910000000001'
       and conversation_address = '919000000702' and content->>'kind' = 'template' $$,
    :'org'
  ),
  '...and a real outbound template message row exists, through the tenant''s own connected number'
);

-- z_notify_on_assignment fires on ANY write to assigned_to, not just
-- assign_lead's own call site -- a trigger on the column, not logic
-- threaded through every function that happens to touch it. This is
-- exactly why it has to be a trigger: crm._ensure_assignment (the
-- auto-assign engine) and the escalation sweep's own reassignment step
-- both update assigned_to directly too, same as assign_lead does.

select tests.as_user('rep.b@test.local');
select crm.set_my_whatsapp_address(:'org', '919000000703');

select tests.as_postgres();
update crm.leads set assigned_to = :'rep_b_agent', assigned_at = now() where id = :'lead_id';
select isnt_empty(
  format(
    $$ select 1 from crm.notifications where organization_id = %L and agent_id = %L and kind = 'lead_assigned' $$,
    :'org', :'rep_b_agent'
  ),
  'any write to assigned_to fires the same trigger, not just assign_lead''s own call site'
);

-- sweep_speed_to_lead_escalation: now also attempts WhatsApp -------------------------------------

select tests.as_postgres();
update crm.leads set assigned_to = :'rep_agent', assigned_at = now() where id = :'lead_id';
-- A second, separate update: z_set_response_deadline's own WHEN clause
-- only fires when assigned_to itself changes, so backdating the deadline
-- here (not in the same statement as the assignment above) survives.
update crm.leads set first_response_due_at = now() - interval '1 hour' where id = :'lead_id';

select crm.sweep_speed_to_lead_escalation();

select isnt_empty(
  format(
    $$ select 1 from crm.audit_log where organization_id = %L and action = 'lead.sla_breached'
       and details->>'channel' = 'whatsapp' $$,
    :'org'
  ),
  'the escalation sweep''s SLA-breach step now also sends via WhatsApp (same seeded template)'
);
select isnt_empty(
  format(
    $$ select 1 from crm.notifications where organization_id = %L and agent_id = %L and kind = 'lead_sla_breached' $$,
    :'org', :'rep_agent'
  ),
  '...and the in-app notification still fires unconditionally, same as before this change'
);

select crm.sweep_speed_to_lead_escalation();
select is(
  (select count(*)::int from crm.notifications where organization_id = :'org' and kind = 'lead_sla_breached'),
  1,
  'running the sweep again does not double-notify -- the existing audit-log idempotency guard is untouched'
);

-- Tenant isolation: the sender is always this org''s own number, never a global credential -------

select is(
  (select organization_address from public.messages
   where organization_id = :'org' and content->>'kind' = 'template'
   order by timestamp desc limit 1),
  '910000000001',
  'every WhatsApp alert this test sent used the org''s own connected number'
);

-- Cross-org isolation -----------------------------------------------------------------------------

select tests.as_postgres();
select tests.create_user('other.owner@test.local') as other_owner \gset
select tests.as_user('owner@test.local');
select tests.create_org('other.owner@test.local', 'Other Alerts Org') as other_org \gset
select is(
  crm._send_internal_whatsapp_alert(:'other_org', :'rep_agent', 'internal_lead_alert', 'hi'),
  null::uuid,
  'a different org cannot resolve a sender through an agent that is not its own -- a no-op, not a leak'
);

select * from finish();
