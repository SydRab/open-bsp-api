-- [crm] P3-07d: task CRUD, gated on deals.edit (the same bar every other
-- lead-working action uses since P3-02) plus the lead_scope visibility
-- check crm.leads' own RLS policy and crm.get_lead_history (P3-07c) both
-- use -- duplicated rather than factored out, same precedent as
-- crm._lead_escalation_managers (P3-06).

create function crm._lead_visible_to_caller(p_lead_id uuid) returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1 from crm.leads l
    where l.id = p_lead_id
      and (
        crm.resolve_lead_scope(l.organization_id) = 'all'
        or (
          crm.resolve_lead_scope(l.organization_id) = 'team'
          and l.assigned_to in (
            select tm2.agent_id
            from crm.team_members tm1
            join crm.team_members tm2 on tm2.team_id = tm1.team_id
            where tm1.agent_id = (crm.caller_agent(l.organization_id)).id
          )
        )
        or (
          crm.resolve_lead_scope(l.organization_id) = 'own'
          and l.assigned_to = (crm.caller_agent(l.organization_id)).id
        )
      )
  );
$$;

create function crm.create_task(
  p_lead_id uuid,
  p_title text,
  p_due_at timestamp with time zone,
  p_assigned_to uuid default null
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_org uuid;
  v_id uuid;
begin
  select l.organization_id into v_org from crm.leads l where l.id = p_lead_id;
  if v_org is null then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if not crm._lead_visible_to_caller(p_lead_id) then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  insert into crm.tasks (organization_id, lead_id, title, due_at, assigned_to)
  values (v_org, p_lead_id, trim(p_title), p_due_at, p_assigned_to)
  returning id into v_id;

  perform crm.write_audit(
    v_org, 'lead.task_created', 'lead', p_lead_id::text,
    jsonb_build_object('task_id', v_id, 'title', trim(p_title), 'due_at', p_due_at)
  );

  return v_id;
end;
$$;

create function crm.update_task(
  p_id uuid,
  p_title text,
  p_due_at timestamp with time zone,
  p_assigned_to uuid
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_task crm.tasks;
begin
  select * into v_task from crm.tasks where id = p_id;
  if not found then
    raise exception 'task not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_task.organization_id, 'deals.edit');

  if not crm._lead_visible_to_caller(v_task.lead_id) then
    raise exception 'task not found' using errcode = 'P0002';
  end if;

  update crm.tasks
  set title = trim(p_title), due_at = p_due_at, assigned_to = p_assigned_to,
      -- A changed due date means any already-sent reminder no longer
      -- applies -- let the sweep reconsider it.
      reminder_sent_at = case when p_due_at <> v_task.due_at then null else reminder_sent_at end
  where id = p_id;
end;
$$;

create function crm.complete_task(p_id uuid, p_completed boolean default true) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_task crm.tasks;
begin
  select * into v_task from crm.tasks where id = p_id;
  if not found then
    raise exception 'task not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_task.organization_id, 'deals.edit');

  if not crm._lead_visible_to_caller(v_task.lead_id) then
    raise exception 'task not found' using errcode = 'P0002';
  end if;

  update crm.tasks
  set completed_at = case when p_completed then coalesce(completed_at, now()) else null end
  where id = p_id;

  perform crm.write_audit(
    v_task.organization_id,
    case when p_completed then 'lead.task_completed' else 'lead.task_reopened' end,
    'lead', v_task.lead_id::text,
    jsonb_build_object('task_id', p_id, 'title', v_task.title)
  );
end;
$$;

-- [crm] P3-07d: the platform-level "internal alert" template every org
-- needs for WhatsApp-delivered task reminders -- not vertical content
-- (no trading-specific wording), so it's seeded directly rather than
-- through the versioned vertical-pack mechanism (10-13_packs.sql) that
-- trading_institute/v1.json uses. pack_version 0 signals "not from a
-- vertical pack version." Inserted with no pack_value, same shape
-- crm.create_custom_field uses for an organization's "own" items, so the
-- org can edit the wording via the existing template-edit flow if it wants
-- to -- it is not locked read-only.
create function crm.seed_task_reminder_template(p_organization_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into crm.organization_pack_items (
    organization_id, kind, item_key, value, pack_version, sort_order
  )
  values (
    p_organization_id, 'message_template', 'internal_task_reminder',
    jsonb_build_object(
      'name', 'internal_task_reminder',
      'category', 'UTILITY',
      'purpose', 'Remind staff of a due task',
      'attach_disclaimer', false,
      'languages', jsonb_build_object(
        'en', jsonb_build_object(
          'body', 'Reminder: {{1}} is due.',
          'examples', jsonb_build_array('Call back Priya about pricing')
        ),
        'hi', jsonb_build_object(
          'body', 'याद दिलाना: {{1}} बाकी है।',
          'examples', jsonb_build_array('प्रिया को कीमत के बारे में वापस कॉल करें')
        )
      )
    ),
    0, 0
  )
  on conflict (organization_id, kind, item_key) do nothing;
end;
$$;

create function crm.delete_task(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_task crm.tasks;
begin
  select * into v_task from crm.tasks where id = p_id;
  if not found then
    raise exception 'task not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_task.organization_id, 'deals.edit');

  if not crm._lead_visible_to_caller(v_task.lead_id) then
    raise exception 'task not found' using errcode = 'P0002';
  end if;

  delete from crm.tasks where id = p_id;
end;
$$;

-- [crm] P3-07d: the reminder sweep. Always writes a durable crm.notifications
-- row (in-app, same as P3-06) -- WhatsApp is an ADDITIONAL delivery
-- attempt, never a replacement, per the WhatsApp-first policy's "a durable
-- in-app record may still exist as a read model" carve-out. WhatsApp only
-- fires when the assignee has set their own number AND an approved
-- 'internal_task_reminder' template exists for the resolved sender address
-- -- both missing is a silent, graceful no-op (documented, not a bug).
-- The resolve-address/resolve-sender/find-template/send sequence itself
-- is crm._send_internal_whatsapp_alert (10-29zk, P3-12) -- factored out
-- once P3-12's lead/SLA alerts became a second real caller of this exact
-- sequence.
--
-- Telemetry (CLAUDE.md non-negotiable): every dispatch writes
-- 'lead.task_reminder_sent' to crm.audit_log with the channel actually
-- used and the message id (for WhatsApp), so delivery status stays
-- queryable from our own schema via the existing per-message status
-- tracking (P2-08) regardless of what Meta shows the tenant.
create function crm.sweep_task_reminders() returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;
