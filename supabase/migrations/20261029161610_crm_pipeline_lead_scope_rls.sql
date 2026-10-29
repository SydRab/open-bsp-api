drop policy "members can read their orgs leads" on "crm"."leads";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.resolve_lead_scope(p_organization_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(mr.lead_scope, r.lead_scope)
  from crm.member_roles mr
  join crm.roles r on r.id = mr.role_id
  where mr.organization_id = p_organization_id
    and mr.agent_id = (crm.caller_agent(p_organization_id)).id;
$function$
;


  create policy "members can read leads within their lead_scope"
  on "crm"."leads"
  as permissive
  for select
  to authenticated, anon
using (((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)) AND ((crm.resolve_lead_scope(organization_id) = 'all'::text) OR ((crm.resolve_lead_scope(organization_id) = 'team'::text) AND (assigned_to IN ( SELECT tm2.agent_id
   FROM (crm.team_members tm1
     JOIN crm.team_members tm2 ON ((tm2.team_id = tm1.team_id)))
  WHERE (tm1.agent_id = (crm.caller_agent(leads.organization_id)).id)))) OR ((crm.resolve_lead_scope(organization_id) = 'own'::text) AND (assigned_to = (crm.caller_agent(organization_id)).id)))));



