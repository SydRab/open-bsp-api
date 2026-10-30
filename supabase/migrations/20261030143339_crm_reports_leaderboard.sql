set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.report_rep_leaderboard(p_organization_id uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(agent_id uuid, leads_assigned bigint, leads_converted bigint, deal_value_won numeric, avg_response_minutes numeric, breached_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.report_response_times(p_organization_id uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(assigned_count bigint, responded_count bigint, breached_count bigint, avg_response_minutes numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;


