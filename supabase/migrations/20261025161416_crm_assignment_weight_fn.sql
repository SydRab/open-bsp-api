set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.set_team_member_weight(p_team_id uuid, p_agent_id uuid, p_weight integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;


