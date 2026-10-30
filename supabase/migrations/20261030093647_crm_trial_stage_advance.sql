set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._advance_to_trial_booked_stage(p_organization_id uuid, p_lead_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_target crm.lead_stages;
  v_current_sort int;
begin
  select * into v_target from crm.lead_stages
  where organization_id = p_organization_id and key = 'trial_booked';
  if not found then
    return;
  end if;

  select s.sort_order into v_current_sort
  from crm.leads l
  join crm.lead_stages s on s.id = l.stage_id
  where l.id = p_lead_id;

  if v_current_sort is not null and v_current_sort >= v_target.sort_order then
    return;
  end if;

  begin
    perform crm._set_lead_stage(p_lead_id, p_organization_id, v_target.id);
  exception when others then
    null;
  end;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.reschedule_trial_booking(p_lead_id uuid, p_slot_start timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
  v_schedule jsonb;
  v_capacity int;
  v_booked int;
  v_slot_end timestamp with time zone;
  v_id uuid;
begin
  select l.organization_id into v_org from crm.leads l where l.id = p_lead_id;
  if v_org is null then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if not crm._lead_visible_to_caller(p_lead_id) then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  select value into v_schedule from crm.setting_values
  where organization_id = v_org and setting_key = 'trial.schedule' and scope = 'tenant';
  if v_schedule is null then
    raise exception 'trial schedule not configured' using errcode = '22023';
  end if;

  v_capacity := coalesce((v_schedule->>'capacity_per_slot')::int, 1);
  v_slot_end := p_slot_start + make_interval(
    mins => coalesce((v_schedule->>'slot_duration_minutes')::int, 60)
  );

  select count(*) into v_booked from crm.trial_bookings
  where organization_id = v_org and slot_start = p_slot_start and status = 'booked';
  if v_booked >= v_capacity then
    raise exception 'slot is full' using errcode = '22023';
  end if;

  update crm.trial_bookings
  set status = 'cancelled', cancelled_at = now()
  where lead_id = p_lead_id and status = 'booked';

  insert into crm.trial_bookings (organization_id, lead_id, slot_start, slot_end)
  values (v_org, p_lead_id, p_slot_start, v_slot_end)
  returning id into v_id;

  perform crm.write_audit(
    v_org, 'lead.trial_rescheduled', 'lead', p_lead_id::text,
    jsonb_build_object('booking_id', v_id, 'slot_start', p_slot_start)
  );

  perform crm._advance_to_trial_booked_stage(v_org, p_lead_id);

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.z_handle_trial_slot_reply()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row_id text;
  v_contact_id uuid;
  v_lead crm.leads;
  v_schedule jsonb;
  v_slot_start timestamp with time zone;
  v_slot_end timestamp with time zone;
  v_capacity int;
  v_booked int;
  v_booking_id uuid;
  v_locale text;
  v_body text;
begin
  v_row_id := null;
  if new.content->>'kind' = 'interactive' and new.content->'data'->>'type' = 'list_reply' then
    v_row_id := new.content->'data'->'list_reply'->>'id';
  end if;

  if v_row_id is null or split_part(v_row_id, '::', 1) <> 'trial_slot' then
    return new;
  end if;

  select ca.contact_id into v_contact_id
  from crm.contact_addresses ca
  where ca.organization_id = new.organization_id
    and ca.service = new.service and ca.address = new.conversation_address;
  if v_contact_id is null then
    return new;
  end if;

  select * into v_lead from crm.leads
  where organization_id = new.organization_id and contact_id = v_contact_id;
  if not found then
    return new;
  end if;

  v_slot_start := substr(v_row_id, length('trial_slot::') + 1)::timestamp with time zone;

  select value into v_schedule from crm.setting_values
  where organization_id = new.organization_id and setting_key = 'trial.schedule' and scope = 'tenant';
  if v_schedule is null then
    return new;
  end if;

  v_slot_end := v_slot_start + make_interval(
    mins => coalesce((v_schedule->>'slot_duration_minutes')::int, 60)
  );
  v_capacity := coalesce((v_schedule->>'capacity_per_slot')::int, 1);

  if v_slot_start <= now() then
    perform crm._send_trial_slot_offer(new.organization_id, v_lead.id);
    return new;
  end if;

  select count(*) into v_booked from crm.trial_bookings
  where organization_id = new.organization_id and slot_start = v_slot_start and status = 'booked';
  if v_booked >= v_capacity then
    perform crm._send_trial_slot_offer(new.organization_id, v_lead.id);
    return new;
  end if;

  -- One active booking per lead: picking a different slot later (via
  -- crm.reschedule_trial_booking, or by replying to a fresh offer) is a
  -- reschedule, not a second booking.
  update crm.trial_bookings
  set status = 'cancelled', cancelled_at = now()
  where lead_id = v_lead.id and status = 'booked';

  insert into crm.trial_bookings (organization_id, lead_id, slot_start, slot_end)
  values (new.organization_id, v_lead.id, v_slot_start, v_slot_end)
  returning id into v_booking_id;

  select coalesce(c.locale, 'en') into v_locale from crm.contacts c where c.id = v_contact_id;
  v_body := case when v_locale = 'hi'
    then 'पक्का! आपकी ट्रायल क्लास ' || to_char(v_slot_start, 'DD Mon, HH12:MI AM') || ' के लिए बुक हो गई है।'
    else 'Confirmed! Your trial class is booked for ' || to_char(v_slot_start, 'Dy DD Mon, HH12:MI AM') || '.' end;

  insert into public.messages (
    organization_id, conversation_id, service, organization_address,
    conversation_address, content
  ) values (
    new.organization_id, new.conversation_id, new.service,
    new.organization_address, new.conversation_address,
    jsonb_build_object('version', '1', 'type', 'text', 'kind', 'text', 'text', v_body)
  );

  if v_lead.assigned_to is not null then
    perform crm._create_notification(
      new.organization_id, v_lead.assigned_to, 'trial_booked',
      'Trial booked', 'A lead assigned to you booked a trial class.', v_lead.id
    );
  end if;

  perform crm.write_audit(
    new.organization_id, 'lead.trial_booked', 'lead', v_lead.id::text,
    jsonb_build_object('booking_id', v_booking_id, 'slot_start', v_slot_start)
  );

  perform crm._advance_to_trial_booked_stage(new.organization_id, v_lead.id);

  return new;
end;
$function$
;


