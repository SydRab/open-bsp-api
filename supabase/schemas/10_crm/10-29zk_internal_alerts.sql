-- [crm] P3-12: "rep mobile experience" -- the WhatsApp half. Literal
-- browser push (VAPID/service worker push subscriptions) is exactly what
-- CLAUDE.md's "Internal/system notifications are WhatsApp-first,
-- permanently" rule forbids for this purpose; the roadmap's "push
-- notifications for new leads and SLA alerts" is delivered over WhatsApp
-- instead, through the same single send path every other outbound message
-- uses. This closes the retroactive follow-up CLAUDE.md itself flagged
-- against P3-06's speed-to-lead alerts, and adds the one notification kind
-- that never existed at all: a lead actually being assigned to someone.

-- Factored out of crm.sweep_task_reminders (P3-07d, the only prior
-- caller) -- this is the second real caller (lead/SLA alerts) needing the
-- exact same resolve-address/resolve-sender/find-template/send sequence.
-- Returns the new message id when WhatsApp actually fired, null on either
-- documented graceful no-op (no whatsapp_address set, or no APPROVED
-- template by that name for the resolved sender) -- the caller decides
-- what "channel" means for its own audit entry, same as
-- sweep_task_reminders already did before this refactor.
--
-- Tenant isolation (CLAUDE.md non-negotiable): the sender is always this
-- org's own connected number (notifications.whatsapp_sender_address if
-- set, else the org's first connected WhatsApp number) -- never a global
-- credential.
create function crm._send_internal_whatsapp_alert(
  p_organization_id uuid,
  p_agent_id uuid,
  p_template_name text,
  p_body text
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_whatsapp_address text;
  v_sender_address text;
  v_template_lang text;
  v_conversation_id uuid;
  v_message_id uuid;
begin
  select mr.whatsapp_address into v_whatsapp_address
  from crm.member_roles mr where mr.agent_id = p_agent_id;

  if v_whatsapp_address is null then
    return null;
  end if;

  select ((select r.value from crm.resolve_setting(
    p_organization_id, 'notifications.whatsapp_sender_address'
  ) r) #>> '{}')
  into v_sender_address;

  if v_sender_address is null or v_sender_address = '' then
    select oa.address into v_sender_address
    from public.organizations_addresses oa
    where oa.organization_id = p_organization_id
      and oa.service = 'whatsapp' and oa.status = 'connected'
    order by oa.created_at asc
    limit 1;
  end if;

  if v_sender_address is null then
    return null;
  end if;

  select t.language into v_template_lang
  from crm.templates t
  where t.organization_id = p_organization_id
    and t.organization_address = v_sender_address
    and t.name = p_template_name
    and t.status = 'APPROVED'
  order by t.language
  limit 1;

  if v_template_lang is null then
    return null;
  end if;

  insert into public.conversations (organization_id, service, organization_address, address)
  values (p_organization_id, 'whatsapp', v_sender_address, v_whatsapp_address)
  on conflict (organization_id, organization_address, service, address) do nothing;

  select c.id into v_conversation_id from public.conversations c
  where c.organization_id = p_organization_id
    and c.organization_address = v_sender_address
    and c.service = 'whatsapp' and c.address = v_whatsapp_address;

  insert into public.messages (
    organization_id, conversation_id, service, organization_address,
    conversation_address, content
  )
  values (
    p_organization_id, v_conversation_id, 'whatsapp', v_sender_address,
    v_whatsapp_address,
    jsonb_build_object(
      'version', '1', 'type', 'data', 'kind', 'template',
      'data', jsonb_build_object(
        'name', p_template_name,
        'language', jsonb_build_object('code', v_template_lang, 'policy', 'deterministic'),
        'components', jsonb_build_array(
          jsonb_build_object(
            'type', 'body',
            'parameters', jsonb_build_array(
              jsonb_build_object('type', 'text', 'text', p_body)
            )
          )
        )
      )
    )
  )
  returning id into v_message_id;

  return v_message_id;
end;
$$;

-- The one platform-level "internal alert" template every org needs for
-- lead/SLA WhatsApp delivery -- generic ("Alert: {{1}}"), not task-
-- specific like internal_task_reminder's wording, so the same one
-- template covers all four crm.notifications kinds this touches (lead_
-- assigned/sla_breached/escalated_to_manager/auto_reassigned) without
-- needing four separate template approvals. Same seeding shape as
-- crm.seed_task_reminder_template (10-29w): not vertical content, so
-- seeded directly rather than through the versioned pack mechanism;
-- pack_version 0; no pack_value, so an org can edit the wording via the
-- existing template-edit flow.
create function crm.seed_internal_lead_alert_template(p_organization_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into crm.organization_pack_items (
    organization_id, kind, item_key, value, pack_version, sort_order
  )
  values (
    p_organization_id, 'message_template', 'internal_lead_alert',
    jsonb_build_object(
      'name', 'internal_lead_alert',
      'category', 'UTILITY',
      'purpose', 'Notify staff about a lead assignment or SLA alert',
      'attach_disclaimer', false,
      'languages', jsonb_build_object(
        'en', jsonb_build_object(
          'body', 'Alert: {{1}}',
          'examples', jsonb_build_array('New lead assigned to you')
        ),
        'hi', jsonb_build_object(
          'body', 'सूचना: {{1}}',
          'examples', jsonb_build_array('आपको एक नया लीड सौंपा गया है')
        )
      )
    ),
    0, 0
  )
  on conflict (organization_id, kind, item_key) do nothing;
end;
$$;

-- "New lead assigned to me" -- a trigger, not a call inside assign_lead/
-- _ensure_assignment, because both independently UPDATE assigned_to
-- (manual pick vs. the auto-assign engine, plus the speed-to-lead sweep's
-- own reassignment) -- the same "one trigger covers every path" lesson
-- P3-05's z_assign_on_qualified and P3-09's conversion-event trigger
-- already established for crm.leads. Fires only when assigned_to actually
-- changes to a real agent (never on unassignment, which sets it to null).
create function crm.z_notify_on_assignment() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_message_id uuid;
begin
  perform crm._create_notification(
    new.organization_id, new.assigned_to, 'lead_assigned',
    'New lead assigned', 'A lead was assigned to you.', new.id
  );

  v_message_id := crm._send_internal_whatsapp_alert(
    new.organization_id, new.assigned_to, 'internal_lead_alert',
    'New lead assigned to you'
  );

  perform crm.write_audit(
    new.organization_id, 'lead.assignment_notified', 'lead', new.id::text,
    jsonb_build_object(
      'channel', case when v_message_id is not null then 'whatsapp' else 'in_app' end,
      'message_id', v_message_id,
      'assigned_to', new.assigned_to
    )
  );

  return null;
end;
$$;

create trigger z_notify_on_assignment
after update of assigned_to
on crm.leads
for each row
when (new.assigned_to is distinct from old.assigned_to and new.assigned_to is not null)
execute function crm.z_notify_on_assignment();
