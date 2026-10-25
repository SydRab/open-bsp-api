-- [crm] P3-05: assignment engine functions.
--
-- Rule CRUD is gated on 'organization.manage', the same bar every other
-- lead catalog uses. Claiming/reassigning/unassigning a lead is gated on
-- 'deals.edit', the same bar every other lead-working function has used
-- since P3-02 -- this is also the FIRST time anything writes an audit
-- entry for an assignment: crm.conversation_assignments (P2-09c) writes
-- none today, so 'lead.assigned'/'lead.reassigned'/'lead.unassigned' are
-- new conventions, not an extension of an existing one.
--
-- The engine itself (crm.z_assign_on_qualified, crm.sweep_lead_
-- reassignment) runs from a trigger/pg_cron with no member/JWT context,
-- so its internal functions (prefixed _) skip permission checks --
-- same reasoning crm._ensure_lead (P3-03) already established. They read
-- settings via crm.resolve_setting, never crm.get_setting -- the P3-04
-- lesson: crm.get_setting's service_role bypass depends on a GUC that
-- only a PostgREST-routed request sets, which pg_cron's direct SQL
-- execution never does.

-- Team member weight (members.manage, the same gate crm.set_team_member --
-- 10-15_settings.sql -- already uses for team membership itself) --------------------------

create function crm.set_team_member_weight(
  p_team_id uuid,
  p_agent_id uuid,
  p_weight int
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_org uuid;
begin
  select organization_id into v_org from crm.teams where id = p_team_id;
  if v_org is null then
    raise exception 'team not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_org, 'members.manage');

  if p_weight < 1 then
    raise exception 'weight must be at least 1' using errcode = '22023';
  end if;

  update crm.team_members set weight = p_weight
  where team_id = p_team_id and agent_id = p_agent_id;

  if not found then
    raise exception 'member not found on this team' using errcode = '22023';
  end if;
end;
$$;

-- Rule CRUD (organization.manage) ----------------------------------------------------------

create function crm.set_assignment_rule(
  p_organization_id uuid,
  p_team_id uuid,
  p_match_language text,
  p_match_source text,
  p_match_campaign_ref text,
  p_sort_order int default null
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  if not exists (
    select 1 from crm.teams where id = p_team_id and organization_id = p_organization_id
  ) then
    raise exception 'team not found' using errcode = '22023';
  end if;

  insert into crm.assignment_rules (
    organization_id, team_id, match_language, match_source, match_campaign_ref, sort_order
  ) values (
    p_organization_id, p_team_id, p_match_language, p_match_source, p_match_campaign_ref,
    coalesce(
      p_sort_order,
      (select max(sort_order) + 1 from crm.assignment_rules where organization_id = p_organization_id),
      0
    )
  )
  returning id into v_id;

  return v_id;
end;
$$;

create function crm.update_assignment_rule(
  p_id uuid,
  p_team_id uuid,
  p_match_language text,
  p_match_source text,
  p_match_campaign_ref text,
  p_sort_order int,
  p_is_active boolean
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_org uuid;
begin
  select organization_id into v_org from crm.assignment_rules where id = p_id;
  if v_org is null then
    raise exception 'rule not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_org, 'organization.manage');

  if not exists (select 1 from crm.teams where id = p_team_id and organization_id = v_org) then
    raise exception 'team not found' using errcode = '22023';
  end if;

  update crm.assignment_rules
  set team_id = p_team_id, match_language = p_match_language, match_source = p_match_source,
      match_campaign_ref = p_match_campaign_ref, sort_order = p_sort_order, is_active = p_is_active
  where id = p_id;
end;
$$;

create function crm.delete_assignment_rule(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select organization_id from crm.assignment_rules where id = p_id),
    'organization.manage'
  );

  delete from crm.assignment_rules where id = p_id;
end;
$$;

-- Engine internals (unchecked -- see header note) ------------------------------------------

-- The first active rule (in sort_order) whose conditions all match this
-- lead's contact/source, or null (no match -> leave unassigned).
create function crm._match_assignment_rule(
  p_organization_id uuid,
  p_lead_id uuid
) returns uuid
language sql
stable
security definer
set search_path to ''
as $$
  select r.team_id
  from crm.leads l
  join crm.contacts c on c.id = l.contact_id
  join crm.assignment_rules r
    on r.organization_id = p_organization_id and r.is_active
  where l.id = p_lead_id
    and (r.match_language is null or r.match_language = coalesce(c.locale, 'en'))
    and (r.match_source is null or r.match_source = l.source)
    and (
      r.match_campaign_ref is null
      or r.match_campaign_ref = c.first_touch_referral->>'source_id'
    )
  order by r.sort_order
  limit 1;
$$;

-- Weighted round robin within a team: the member with the lowest (open
-- leads currently held / weight) ratio, excluding anyone off-hours or at
-- the org's capacity cap. Null if the whole pool is ineligible --
-- confirmed with the user: leave the lead unassigned rather than widen
-- the search past the matched team.
create function crm._pick_assignee(
  p_organization_id uuid,
  p_team_id uuid
) returns uuid
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_cap int;
  v_hours jsonb;
  v_tz text;
  v_now_local timestamp;
  v_day text;
  v_agent uuid;
begin
  -- Tenant-wide, falling all the way back to the platform default (20)
  -- like every other setting -- unlike working_hours below, "never set"
  -- here means "use the platform default," not "unrestricted."
  select (r.value #>> '{}')::int into v_cap
  from crm.resolve_setting(p_organization_id, 'assignment.capacity_cap') r;

  -- Unset per team = unrestricted, by design (not crm.resolve_setting's
  -- usual fallback chain -- a team with no working_hours row is simply
  -- always available, rather than inheriting a platform default that
  -- would restrict every team nobody has configured yet).
  select value into v_hours
  from crm.setting_values
  where organization_id = p_organization_id
    and setting_key = 'assignment.working_hours' and scope = 'team' and team_id = p_team_id;

  select coalesce(timezone, 'Asia/Kolkata') into v_tz
  from crm.organization_profiles where organization_id = p_organization_id;
  v_now_local := now() at time zone coalesce(v_tz, 'Asia/Kolkata');
  v_day := lower(to_char(v_now_local, 'dy'));

  if v_hours is not null and not (
    v_hours->'days' @> to_jsonb(v_day)
    and v_now_local::time between (v_hours->>'start')::time and (v_hours->>'end')::time
  ) then
    return null;
  end if;

  select tm.agent_id into v_agent
  from crm.team_members tm
  join public.agents a on a.id = tm.agent_id and a.deleted_at is null
  where tm.organization_id = p_organization_id and tm.team_id = p_team_id
    and (
      v_cap is null
      or (
        select count(*) from crm.leads l
        where l.organization_id = p_organization_id and l.assigned_to = tm.agent_id
          and l.status in ('open', 'qualified')
      ) < v_cap
    )
  order by (
    select count(*)::numeric from crm.leads l
    where l.organization_id = p_organization_id and l.assigned_to = tm.agent_id
      and l.status in ('open', 'qualified')
  ) / tm.weight asc
  limit 1;

  return v_agent;
end;
$$;

-- Routes and assigns a qualified lead, if nothing has already. Called
-- from crm.z_assign_on_qualified (opt-in auto-assign) and crm.
-- sweep_lead_reassignment (timeout). A no-op for anything not currently
-- 'qualified' -- a lead that converted, dropped, or reopened mid-flow is
-- left alone.
create function crm._ensure_assignment(
  p_organization_id uuid,
  p_lead_id uuid
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_lead crm.leads;
  v_team uuid;
  v_agent uuid;
begin
  select * into v_lead from crm.leads where id = p_lead_id and status = 'qualified';
  if not found then
    return;
  end if;

  v_team := crm._match_assignment_rule(p_organization_id, p_lead_id);
  if v_team is null then
    return;
  end if;

  v_agent := crm._pick_assignee(p_organization_id, v_team);
  if v_agent is null then
    return;
  end if;

  update crm.leads set assigned_to = v_agent, assigned_at = now() where id = p_lead_id;

  perform crm.write_audit(
    p_organization_id,
    case when v_lead.assigned_to is null then 'lead.assigned' else 'lead.reassigned' end,
    'lead', p_lead_id::text,
    jsonb_build_object('agent_id', v_agent, 'from_agent_id', v_lead.assigned_to, 'team_id', v_team)
  );
end;
$$;

-- Opt-in auto-assign (qualification.auto_start's sibling setting) fires
-- the moment a lead becomes qualified, regardless of whether that came
-- from the qualification engine (P3-04) or a manual crm.set_lead_status
-- override -- one trigger on crm.leads covers both paths uniformly.
create function crm.z_assign_on_qualified() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_auto_assign boolean;
begin
  v_auto_assign := coalesce(
    ((select r.value from crm.resolve_setting(new.organization_id, 'assignment.auto_assign') r) #>> '{}')::boolean,
    false
  );

  if v_auto_assign and new.assigned_to is null then
    perform crm._ensure_assignment(new.organization_id, new.id);
  end if;

  return new;
end;
$$;

create trigger z_assign_on_qualified
after update
on crm.leads
for each row
when (new.status = 'qualified' and old.status is distinct from 'qualified')
execute function crm.z_assign_on_qualified();

-- Manual assignment (deals.edit) -------------------------------------------------------------

create function crm.assign_lead(p_lead_id uuid, p_agent_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_lead crm.leads;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_lead.organization_id, 'deals.edit');

  if not exists (
    select 1 from public.agents a
    where a.id = p_agent_id and a.organization_id = v_lead.organization_id and a.deleted_at is null
  ) then
    raise exception 'agent not found' using errcode = '22023';
  end if;

  update crm.leads set assigned_to = p_agent_id, assigned_at = now() where id = p_lead_id;

  perform crm.write_audit(
    v_lead.organization_id,
    case when v_lead.assigned_to is null then 'lead.assigned' else 'lead.reassigned' end,
    'lead', p_lead_id::text,
    jsonb_build_object('agent_id', p_agent_id, 'from_agent_id', v_lead.assigned_to, 'manual', true)
  );
end;
$$;

create function crm.unassign_lead(p_lead_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_lead crm.leads;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_lead.organization_id, 'deals.edit');

  update crm.leads set assigned_to = null, assigned_at = null where id = p_lead_id;

  perform crm.write_audit(
    v_lead.organization_id, 'lead.unassigned', 'lead', p_lead_id::text,
    jsonb_build_object('from_agent_id', v_lead.assigned_to, 'manual', true)
  );
end;
$$;

-- Auto-reassign on timeout (pg_cron) ----------------------------------------------------------

-- "The rep took action," confirmed with the user: a lead.stage_changed/
-- quality_changed/status_changed audit entry (not lead.created or lead.
-- reopened -- those are the system's own doing, not the rep's) or a
-- message sent by a human agent (public.agents.user_id is not null --
-- excludes the welcome/qualification engine's own automated replies,
-- which would otherwise reset the clock without anyone actually working
-- the lead) since assigned_at. Past the timeout with neither, crm.
-- _ensure_assignment picks a (possibly different) assignee -- the same fair-share math, now
-- counting this lead against whoever still holds it.
create function crm.sweep_lead_reassignment() returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_lead crm.leads;
  v_timeout_hours int;
  v_has_activity boolean;
begin
  for v_lead in
    select * from crm.leads where assigned_to is not null and status = 'qualified'
  loop
    v_timeout_hours := coalesce(
      ((select r.value from crm.resolve_setting(v_lead.organization_id, 'assignment.reassign_timeout_hours') r) #>> '{}')::int,
      24
    );

    if v_lead.assigned_at is null
      or v_lead.assigned_at > now() - make_interval(hours => v_timeout_hours)
    then
      continue;
    end if;

    v_has_activity := exists (
      select 1 from crm.audit_log al
      where al.organization_id = v_lead.organization_id
        and al.target_type = 'lead' and al.target_id = v_lead.id::text
        and al.action in ('lead.stage_changed', 'lead.quality_changed', 'lead.status_changed')
        and al.created_at > v_lead.assigned_at
    ) or exists (
      select 1 from crm.contact_addresses ca
      join public.conversations cv
        on cv.organization_id = ca.organization_id
        and cv.service = ca.service and cv.address = ca.address
      join public.messages m on m.conversation_id = cv.id
      join public.agents a on a.id = m.agent_id
      where ca.organization_id = v_lead.organization_id and ca.contact_id = v_lead.contact_id
        and a.user_id is not null
        and m.created_at > v_lead.assigned_at
    );

    if not v_has_activity then
      perform crm._ensure_assignment(v_lead.organization_id, v_lead.id);
    end if;
  end loop;
end;
$$;
