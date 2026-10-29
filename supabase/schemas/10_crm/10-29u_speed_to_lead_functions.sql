-- [crm] P3-06: speed-to-lead functions.
--
-- Everything here reads settings via crm.resolve_setting, never crm.
-- get_setting -- the lesson from P3-04/P3-05, generalized: ANY trigger-
-- or cron-fired code can run against a plain connection with none of the
-- request-scoped GUCs crm.get_setting's service_role bypass depends on
-- (confirmed the hard way for P3-03's own trigger, against `supabase db
-- reset`'s plain-connection seed.sql insert).
--
-- Notification creation and the escalation engine are unchecked/internal
-- (prefixed _ or z_) for the same reason crm._ensure_lead (P3-03) already
-- established: they run from triggers/pg_cron with no member/JWT context.
-- Only marking a notification read is member-facing.

-- Notifications ---------------------------------------------------------------------------

create function crm._create_notification(
  p_organization_id uuid,
  p_agent_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_lead_id uuid default null
) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into crm.notifications (organization_id, agent_id, kind, title, body, lead_id)
  values (p_organization_id, p_agent_id, p_kind, p_title, p_body, p_lead_id);
end;
$$;

create function crm.mark_notification_read(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_organization_id uuid;
  v_self uuid;
begin
  select organization_id into v_organization_id from crm.notifications where id = p_id;
  if v_organization_id is null then
    raise exception 'notification not found' using errcode = 'P0002';
  end if;

  v_self := (crm.caller_agent(v_organization_id)).id;

  update crm.notifications
  set read_at = coalesce(read_at, now())
  where id = p_id and agent_id = v_self;

  if not found then
    raise exception 'notification not found' using errcode = 'P0002';
  end if;
end;
$$;

create function crm.mark_all_notifications_read(p_organization_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_self uuid := (crm.caller_agent(p_organization_id)).id;
begin
  update crm.notifications
  set read_at = now()
  where organization_id = p_organization_id and agent_id = v_self and read_at is null;
end;
$$;

-- Escalation internals (unchecked -- see header note) --------------------------------------

-- Who to notify at the "manager" escalation step for a rep: anyone who
-- can actually work leads (holds deals.edit -- excludes a lead_scope=
-- 'all' viewer, who sees everything but can act on nothing) with
-- effective lead_scope 'all' (org-wide), or 'team' and sharing a team
-- with the rep. crm.roles.lead_scope/crm.member_roles.lead_scope (P1-02)
-- already exist for exactly this -- its own role description ("sales_
-- manager", lead_scope 'all') already names the intent -- but nothing
-- has read it until now; this is its first real consumer.
create function crm._lead_escalation_managers(
  p_organization_id uuid,
  p_agent_id uuid
) returns setof uuid
language sql
stable
security definer
set search_path to ''
as $$
  select distinct a.id
  from public.agents a
  join crm.member_roles mr on mr.agent_id = a.id and mr.organization_id = p_organization_id
  join crm.roles r on r.id = mr.role_id
  where a.organization_id = p_organization_id
    and a.deleted_at is null
    and a.id <> p_agent_id
    and exists (
      select 1 from crm.role_permissions rp
      where rp.role_id = mr.role_id and rp.permission = 'deals.edit'
    )
    and (
      coalesce(mr.lead_scope, r.lead_scope) = 'all'
      or (
        coalesce(mr.lead_scope, r.lead_scope) = 'team'
        and exists (
          select 1 from crm.team_members tm1
          join crm.team_members tm2 on tm2.team_id = tm1.team_id
          where tm1.agent_id = p_agent_id and tm2.agent_id = a.id
        )
      )
    );
$$;

-- Sets (or refreshes, on reassignment) the first-response deadline
-- whenever a lead gains an assignee and nobody has responded yet. A
-- BEFORE trigger modifying NEW directly -- no second UPDATE statement,
-- so no self-trigger recursion to reason about.
create function crm.z_set_response_deadline() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_minutes int;
begin
  v_minutes := coalesce(
    ((select r.value from crm.resolve_setting(new.organization_id, 'speed_to_lead.first_response_sla_minutes') r) #>> '{}')::int,
    15
  );
  new.first_response_due_at := now() + make_interval(mins => v_minutes);
  return new;
end;
$$;

create trigger z_set_response_deadline
before update
on crm.leads
for each row
when (
  new.assigned_to is distinct from old.assigned_to
  and new.assigned_to is not null
  and new.first_responded_at is null
)
execute function crm.z_set_response_deadline();

-- The other half: the first human-sent message in a lead's conversation
-- after assignment stamps first_responded_at. Any human reply counts --
-- not just the assignee's own -- the goal is the lead getting answered,
-- not strict rep accountability. public.agents.user_id is not null is
-- what "human" means here (excludes the welcome/qualification engine's
-- own automated sends, same signal P3-05's reassign-on-timeout check
-- already established).
create function crm.z_record_first_response() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_human boolean;
  v_contact_id uuid;
  v_lead crm.leads;
begin
  select (user_id is not null) into v_human from public.agents where id = new.agent_id;
  if not coalesce(v_human, false) then
    return new;
  end if;

  select ca.contact_id into v_contact_id
  from crm.contact_addresses ca
  where ca.organization_id = new.organization_id
    and ca.service = new.service
    and ca.address = new.conversation_address;
  if v_contact_id is null then
    return new;
  end if;

  select * into v_lead from crm.leads
  where organization_id = new.organization_id and contact_id = v_contact_id
    and assigned_to is not null and first_responded_at is null;
  if not found then
    return new;
  end if;

  update crm.leads set first_responded_at = now() where id = v_lead.id;

  perform crm.write_audit(
    new.organization_id, 'lead.first_responded', 'lead', v_lead.id::text,
    jsonb_build_object(
      'minutes_to_respond', round(extract(epoch from (now() - v_lead.assigned_at)) / 60, 1)
    )
  );

  return new;
end;
$$;

create trigger z_record_first_response
after insert
on public.messages
for each row
when (new.sender_address is null and new.agent_id is not null)
execute function crm.z_record_first_response();

-- pg_cron sweep (every 5 minutes -- tighter than P3-04/P3-05's 15-minute
-- sweeps, since this task's own windows are measured in single-digit/
-- low-double-digit minutes, not hours). Each step's "already done" check
-- is an crm.audit_log lookup, the same idiom P3-05 uses, so a lead
-- revisited every 5 minutes is never double-notified or double-
-- escalated.
create function crm.sweep_speed_to_lead_escalation() returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_lead crm.leads;
  v_manager_minutes int;
  v_reassign_minutes int;
  v_manager_due timestamp with time zone;
  v_reassign_due timestamp with time zone;
  v_manager_id uuid;
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
      perform crm.write_audit(
        v_lead.organization_id, 'lead.sla_breached', 'lead', v_lead.id::text, '{}'::jsonb
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
      for v_manager_id in
        select m from crm._lead_escalation_managers(v_lead.organization_id, v_lead.assigned_to) m
      loop
        perform crm._create_notification(
          v_lead.organization_id, v_manager_id, 'lead_escalated_to_manager',
          'Lead response overdue', 'A lead has gone unanswered past the escalation window.',
          v_lead.id
        );
      end loop;
      perform crm.write_audit(
        v_lead.organization_id, 'lead.escalated_to_manager', 'lead', v_lead.id::text, '{}'::jsonb
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
      perform crm.write_audit(
        v_lead.organization_id, 'lead.auto_reassigned_sla', 'lead', v_lead.id::text,
        jsonb_build_object('from_agent_id', v_lead.assigned_to)
      );

      update crm.leads
      set assigned_to = null, assigned_at = null, first_response_due_at = null
      where id = v_lead.id;

      perform crm._ensure_assignment(v_lead.organization_id, v_lead.id);
    end if;
  end loop;
end;
$$;
