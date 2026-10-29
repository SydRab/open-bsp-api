set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._lead_escalation_managers(p_organization_id uuid, p_agent_id uuid)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;


