set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.needs_mfa_step_up(p_organization_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.agents a
    join crm.member_roles mr on mr.agent_id = a.id
    join crm.roles r on r.id = mr.role_id
    join crm.organization_profiles p on p.organization_id = a.organization_id
    where a.organization_id = p_organization_id
      and a.user_id = auth.uid()
      and a.deleted_at is null
      and p.status = 'active'
      and p.require_mfa_for_admins
      and r.tier <> 'member'
      and coalesce(auth.jwt()->>'aal', 'aal1') <> 'aal2'
  );
$function$
;


