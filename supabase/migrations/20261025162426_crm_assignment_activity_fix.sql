set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.sweep_lead_reassignment()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;


