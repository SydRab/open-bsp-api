alter table "crm"."notifications" drop constraint "notifications_kind_check";

alter table "crm"."notifications" add constraint "notifications_kind_check" CHECK ((kind = ANY (ARRAY['lead_sla_breached'::text, 'lead_escalated_to_manager'::text, 'lead_auto_reassigned'::text, 'task_due'::text, 'trial_booked'::text, 'lead_assigned'::text]))) not valid;

alter table "crm"."notifications" validate constraint "notifications_kind_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._send_internal_whatsapp_alert(p_organization_id uuid, p_agent_id uuid, p_template_name text, p_body text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.seed_internal_lead_alert_template(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.z_notify_on_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.after_insert_on_organizations()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into crm.organization_profiles (organization_id, slug)
  values (new.id, crm.generate_slug(new.name));

  perform crm.create_preset_roles(new.id);
  perform crm.apply_default_pack(new.id);
  -- [crm] P3-02
  perform crm.seed_lead_catalogs(new.id);
  -- [crm] P3-04: after seed_lead_catalogs, so crm.lead_qualities already
  -- has rows for seed_qualification_scoring to resolve quality_key against.
  perform crm.seed_qualification_scoring(new.id);
  -- [crm] P3-07d
  perform crm.seed_task_reminder_template(new.id);
  -- [crm] P3-08
  perform crm.seed_trial_reminder_template(new.id);
  -- [crm] P3-09
  perform crm.seed_default_event_mapping(new.id);
  -- [crm] P3-12
  perform crm.seed_internal_lead_alert_template(new.id);

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.sweep_speed_to_lead_escalation()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads;
  v_manager_minutes int;
  v_reassign_minutes int;
  v_manager_due timestamp with time zone;
  v_reassign_due timestamp with time zone;
  v_manager_id uuid;
  v_message_id uuid;
  v_managers_notified int;
  v_managers_via_whatsapp int;
begin
  for v_lead in
    select * from crm.leads
    where assigned_to is not null
      and first_responded_at is null
      and status in ('open', 'qualified')
      and first_response_due_at is not null
      and first_response_due_at <= now()
  loop
    if not exists (
      select 1 from crm.audit_log
      where organization_id = v_lead.organization_id and target_type = 'lead'
        and target_id = v_lead.id::text and action = 'lead.sla_breached'
    ) then
      perform crm._create_notification(
        v_lead.organization_id, v_lead.assigned_to, 'lead_sla_breached',
        'Lead needs a response', 'A lead assigned to you has passed the first-response SLA.',
        v_lead.id
      );
      v_message_id := crm._send_internal_whatsapp_alert(
        v_lead.organization_id, v_lead.assigned_to, 'internal_lead_alert',
        'Lead needs a response: a lead assigned to you has passed the first-response SLA'
      );
      perform crm.write_audit(
        v_lead.organization_id, 'lead.sla_breached', 'lead', v_lead.id::text,
        jsonb_build_object(
          'channel', case when v_message_id is not null then 'whatsapp' else 'in_app' end,
          'message_id', v_message_id
        )
      );
    end if;

    v_manager_minutes := coalesce(
      ((select r.value from crm.resolve_setting(v_lead.organization_id, 'speed_to_lead.manager_escalation_minutes') r) #>> '{}')::int,
      15
    );
    v_manager_due := v_lead.first_response_due_at + make_interval(mins => v_manager_minutes);

    if now() >= v_manager_due and not exists (
      select 1 from crm.audit_log
      where organization_id = v_lead.organization_id and target_type = 'lead'
        and target_id = v_lead.id::text and action = 'lead.escalated_to_manager'
    ) then
      v_managers_notified := 0;
      v_managers_via_whatsapp := 0;
      for v_manager_id in
        select m from crm._lead_escalation_managers(v_lead.organization_id, v_lead.assigned_to) m
      loop
        perform crm._create_notification(
          v_lead.organization_id, v_manager_id, 'lead_escalated_to_manager',
          'Lead response overdue', 'A lead has gone unanswered past the escalation window.',
          v_lead.id
        );
        v_message_id := crm._send_internal_whatsapp_alert(
          v_lead.organization_id, v_manager_id, 'internal_lead_alert',
          'Lead response overdue: a lead has gone unanswered past the escalation window'
        );
        v_managers_notified := v_managers_notified + 1;
        if v_message_id is not null then
          v_managers_via_whatsapp := v_managers_via_whatsapp + 1;
        end if;
      end loop;
      perform crm.write_audit(
        v_lead.organization_id, 'lead.escalated_to_manager', 'lead', v_lead.id::text,
        jsonb_build_object(
          'managers_notified', v_managers_notified,
          'managers_notified_via_whatsapp', v_managers_via_whatsapp
        )
      );
    end if;

    v_reassign_minutes := coalesce(
      ((select r.value from crm.resolve_setting(v_lead.organization_id, 'speed_to_lead.reassign_escalation_minutes') r) #>> '{}')::int,
      30
    );
    v_reassign_due := v_manager_due + make_interval(mins => v_reassign_minutes);

    -- Only a qualified lead has an assignment rule/team to re-route
    -- through (crm._ensure_assignment's own guard) -- a manually
    -- assigned, still-open lead stays with the same unresponsive rep
    -- past this point rather than being silently dropped; the manager
    -- notification above already fired for it.
    if now() >= v_reassign_due then
      perform crm._create_notification(
        v_lead.organization_id, v_lead.assigned_to, 'lead_auto_reassigned',
        'Lead reassigned', 'A lead assigned to you was reassigned after going unanswered too long.',
        v_lead.id
      );
      v_message_id := crm._send_internal_whatsapp_alert(
        v_lead.organization_id, v_lead.assigned_to, 'internal_lead_alert',
        'Lead reassigned: a lead assigned to you was reassigned after going unanswered too long'
      );
      perform crm.write_audit(
        v_lead.organization_id, 'lead.auto_reassigned_sla', 'lead', v_lead.id::text,
        jsonb_build_object(
          'from_agent_id', v_lead.assigned_to,
          'channel', case when v_message_id is not null then 'whatsapp' else 'in_app' end,
          'message_id', v_message_id
        )
      );

      update crm.leads
      set assigned_to = null, assigned_at = null, first_response_due_at = null
      where id = v_lead.id;

      perform crm._ensure_assignment(v_lead.organization_id, v_lead.id);
    end if;
  end loop;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.sweep_task_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_task crm.tasks;
  v_message_id uuid;
begin
  for v_task in
    select * from crm.tasks
    where due_at <= now() and completed_at is null and reminder_sent_at is null
      and assigned_to is not null
  loop
    perform crm._create_notification(
      v_task.organization_id, v_task.assigned_to, 'task_due',
      'Task due', v_task.title, v_task.lead_id
    );

    v_message_id := crm._send_internal_whatsapp_alert(
      v_task.organization_id, v_task.assigned_to, 'internal_task_reminder', v_task.title
    );

    update crm.tasks set reminder_sent_at = now() where id = v_task.id;

    perform crm.write_audit(
      v_task.organization_id, 'lead.task_reminder_sent', 'lead', v_task.lead_id::text,
      jsonb_build_object(
        'task_id', v_task.id,
        'channel', case when v_message_id is not null then 'whatsapp' else 'in_app' end,
        'message_id', v_message_id,
        'assigned_to', v_task.assigned_to
      )
    );
  end loop;
end;
$function$
;

CREATE TRIGGER z_notify_on_assignment AFTER UPDATE OF assigned_to ON crm.leads FOR EACH ROW WHEN (((new.assigned_to IS DISTINCT FROM old.assigned_to) AND (new.assigned_to IS NOT NULL))) EXECUTE FUNCTION crm.z_notify_on_assignment();

-- db diff doesn't derive privilege changes for a brand-new function (see
-- P3-11c/P3-11d's own migrations for the full explanation) -- match the
-- same shape the sibling internal functions (crm._create_notification,
-- crm.sweep_task_reminders, crm.z_assign_on_qualified) already have:
-- postgres + service_role only, never PUBLIC. This one is more than a
-- discoverability gap -- it can trigger a real outbound WhatsApp send
-- (crm._send_internal_whatsapp_alert), so leaving it PUBLIC-executable
-- would let any authenticated caller spend an arbitrary tenant's own
-- WhatsApp number/template allowance by passing that tenant's
-- organization_id and one of their agent ids directly.
revoke execute on function crm._send_internal_whatsapp_alert(uuid, uuid, text, text) from public;
grant execute on function crm._send_internal_whatsapp_alert(uuid, uuid, text, text) to service_role;

revoke execute on function crm.seed_internal_lead_alert_template(uuid) from public;
grant execute on function crm.seed_internal_lead_alert_template(uuid) to service_role;

revoke execute on function crm.z_notify_on_assignment() from public;
grant execute on function crm.z_notify_on_assignment() to service_role;


