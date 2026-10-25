set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._pick_assignee(p_organization_id uuid, p_team_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;


