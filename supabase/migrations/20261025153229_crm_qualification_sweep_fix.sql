set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.sweep_qualification_nudges()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_state crm.lead_qualification_state;
begin
  for v_state in
    select s.*
    from crm.lead_qualification_state s
    where s.completed_at is null
      and s.asked_at <= now() - make_interval(hours => coalesce(
        (crm.get_setting(s.organization_id, 'qualification.question_timeout_hours') #>> '{}')::int,
        6
      ))
  loop
    perform crm._send_nudge(v_state);
  end loop;
end;
$function$
;


