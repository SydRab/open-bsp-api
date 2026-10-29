set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.get_lead_history(p_lead_id uuid)
 RETURNS TABLE(id bigint, created_at timestamp with time zone, actor_type text, actor_agent_id uuid, actor_name text, action text, details jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
begin
  select organization_id into v_org from crm.leads where id = p_lead_id;
  if v_org is null then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if not exists (
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
  ) then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  return query
  select
    l.id,
    l.created_at,
    l.actor_type,
    l.actor_agent_id,
    coalesce(actor.name, ak.name),
    l.action,
    l.details
  from crm.audit_log l
  left join public.agents actor on actor.id = l.actor_agent_id
  left join public.api_keys ak on ak.id = l.actor_api_key_id
  where l.organization_id = v_org
    and l.target_type = 'lead'
    and l.target_id = p_lead_id::text
  order by l.id desc
  limit 200;
end;
$function$
;


