-- [crm] P3-10b: reports, sub-phase 2 (response times, rep leaderboard).
-- Same `reports.view` gate as P3-10a's pipeline reports -- reports are
-- cross-rep aggregates, not scoped by the caller's own lead_scope.
--
-- Deliberately reads crm.leads' own first_responded_at/assigned_at/
-- first_response_due_at columns directly, NOT crm.audit_log's
-- 'lead.first_responded' entry (which does carry a pre-computed
-- minutes_to_respond, P3-06) -- that audit write happens from a trigger
-- fired by the dispatcher's own service-role client, so it has no
-- auth.uid() and its actor_agent_id is never the responding rep. The
-- leads table itself has everything needed, correctly attributable to
-- whoever is (or was) assigned, with no such gap.
--
-- "Breached" is computed the same way for both reports: responded late
-- (first_responded_at > first_response_due_at) or still overdue and
-- unresponded (first_responded_at is null and first_response_due_at <
-- now()) -- this does not depend on crm.audit_log's own
-- 'lead.sla_breached' entries (P3-06's escalation sweep only writes one
-- once, as a side effect of escalating -- not the same thing as "was this
-- particular lead ever late").
create function crm.report_response_times(
  p_organization_id uuid,
  p_from timestamp with time zone default null,
  p_to timestamp with time zone default null
) returns table (
  assigned_count bigint,
  responded_count bigint,
  breached_count bigint,
  avg_response_minutes numeric
)
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(p_organization_id, 'reports.view');

  return query
  select
    count(*)::bigint,
    count(*) filter (where l.first_responded_at is not null)::bigint,
    count(*) filter (
      where l.first_response_due_at is not null
        and (
          (l.first_responded_at is not null and l.first_responded_at > l.first_response_due_at)
          or (l.first_responded_at is null and l.first_response_due_at < now())
        )
    )::bigint,
    round(
      avg(extract(epoch from (l.first_responded_at - l.assigned_at)) / 60)
        filter (where l.first_responded_at is not null),
      1
    )
  from crm.leads l
  where l.organization_id = p_organization_id
    and l.assigned_at is not null
    and (p_from is null or l.assigned_at >= p_from)
    and (p_to is null or l.assigned_at < p_to);
end;
$$;

-- One row per agent who has ever been assigned a lead in range -- name
-- resolution is left to the UI (crm.member_roles/public.agents, same
-- "resolve ids to names client-side from an already-cached list"
-- convention every other lead-working modal already uses), so this stays
-- a plain aggregate with no join of its own.
create function crm.report_rep_leaderboard(
  p_organization_id uuid,
  p_from timestamp with time zone default null,
  p_to timestamp with time zone default null
) returns table (
  agent_id uuid,
  leads_assigned bigint,
  leads_converted bigint,
  deal_value_won numeric,
  avg_response_minutes numeric,
  breached_count bigint
)
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(p_organization_id, 'reports.view');

  return query
  select
    l.assigned_to,
    count(*)::bigint,
    count(*) filter (where l.status = 'converted')::bigint,
    coalesce(sum(l.deal_value) filter (where l.status = 'converted'), 0),
    round(
      avg(extract(epoch from (l.first_responded_at - l.assigned_at)) / 60)
        filter (where l.first_responded_at is not null),
      1
    ),
    count(*) filter (
      where l.first_response_due_at is not null
        and (
          (l.first_responded_at is not null and l.first_responded_at > l.first_response_due_at)
          or (l.first_responded_at is null and l.first_response_due_at < now())
        )
    )::bigint
  from crm.leads l
  where l.organization_id = p_organization_id
    and l.assigned_to is not null
    and (p_from is null or l.assigned_at >= p_from)
    and (p_to is null or l.assigned_at < p_to)
  group by l.assigned_to
  order by count(*) filter (where l.status = 'converted') desc, count(*) desc;
end;
$$;
