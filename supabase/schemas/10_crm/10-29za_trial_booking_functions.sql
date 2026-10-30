-- [crm] P3-08: trial booking. Three moving parts, each mirroring an
-- existing P3-04/06/07d pattern rather than inventing a new one:
--   1. offer  -- crm.z_offer_trial_on_qualified (a sibling of P3-05's
--      z_assign_on_qualified, same transition, same opt-in-setting guard)
--      sends an interactive list of open slots computed from the
--      trial.schedule tenant setting.
--   2. booking -- crm.z_handle_trial_slot_reply (same shape as P3-04's
--      z_run_qualification_engine) recognizes the list reply and books it.
--   3. reminder -- crm.sweep_trial_reminders (same idempotent-sweep shape
--      as crm.sweep_task_reminders, P3-07d), WhatsApp-template-delivered
--      since the 24h window is usually closed by reminder time.
--
-- Tenant isolation (CLAUDE.md non-negotiable): the reminder sender is
-- always this org's own connected number (notifications.whatsapp_sender_
-- address if set, else the org's first connected WhatsApp number), same
-- resolution crm.sweep_task_reminders already uses -- never a global
-- credential.
--
-- Telemetry (CLAUDE.md non-negotiable): every offer/booking/reschedule/
-- cancel/reminder writes to crm.audit_log regardless of whether a
-- WhatsApp send was actually attempted or possible.

-- Unset trial.schedule = trial booking not configured for this org, with
-- no fallback to a platform default -- same reasoning crm._pick_assignee
-- (10-29s) uses for assignment.working_hours: there is no universally
-- sensible default schedule, so this reads crm.setting_values directly
-- rather than going through crm.resolve_setting's usual fallback chain.
create function crm._upcoming_trial_slots(
  p_organization_id uuid,
  p_limit int default 10
) returns table (
  slot_start timestamp with time zone,
  slot_end timestamp with time zone,
  seats_left int
)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_schedule jsonb;
  v_tz text;
  v_duration int;
  v_capacity int;
  v_day date;
  v_day_name text;
  v_time text;
  v_candidate timestamp with time zone;
  v_booked int;
  v_found int := 0;
begin
  select value into v_schedule
  from crm.setting_values
  where organization_id = p_organization_id
    and setting_key = 'trial.schedule' and scope = 'tenant';

  if v_schedule is null then
    return;
  end if;

  select coalesce(timezone, 'Asia/Kolkata') into v_tz
  from crm.organization_profiles where organization_id = p_organization_id;

  v_duration := coalesce((v_schedule->>'slot_duration_minutes')::int, 60);
  v_capacity := coalesce((v_schedule->>'capacity_per_slot')::int, 1);

  -- A two-week lookahead -- plenty of runway for a 10-row list (Meta's
  -- own cap) without an extra "how far ahead" setting nobody asked for.
  for v_day in
    select generate_series(current_date, current_date + 13, interval '1 day')::date
  loop
    v_day_name := lower(to_char(v_day, 'dy'));
    if v_schedule->'days' @> to_jsonb(v_day_name) then
      for v_time in select jsonb_array_elements_text(v_schedule->'times') order by 1
      loop
        v_candidate := (v_day::text || ' ' || v_time)::timestamp at time zone v_tz;
        if v_candidate > now() then
          select count(*) into v_booked
          from crm.trial_bookings b
          where b.organization_id = p_organization_id
            and b.slot_start = v_candidate and b.status = 'booked';

          if v_booked < v_capacity then
            slot_start := v_candidate;
            slot_end := v_candidate + make_interval(mins => v_duration);
            seats_left := v_capacity - v_booked;
            v_found := v_found + 1;
            return next;
            if v_found >= p_limit then
              return;
            end if;
          end if;
        end if;
      end loop;
    end if;
  end loop;
end;
$$;

-- The staff-facing read (deals.edit): the reschedule UI's own slot picker.
create function crm.list_upcoming_trial_slots(p_organization_id uuid) returns table (
  slot_start timestamp with time zone,
  slot_end timestamp with time zone,
  seats_left int
)
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(p_organization_id, 'deals.edit');
  return query select * from crm._upcoming_trial_slots(p_organization_id, 10);
end;
$$;

-- Sends the slot list to whichever conversation this lead's contact most
-- recently messaged from -- same lookup crm._send_nudge (10-29q) already
-- uses. A plain (non-template) interactive_list, same choke-point trick
-- as every other automated send in this project: a public.messages insert
-- that flows through _shared/send_policy.ts automatically. If the window
-- happens to be closed (e.g. a lead qualified by manual override long
-- after its last reply), send_policy marks the message accordingly --
-- still a durable, queryable record, never a silent gap.
create function crm._send_trial_slot_offer(
  p_organization_id uuid,
  p_lead_id uuid
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_lead crm.leads;
  v_address crm.contact_addresses;
  v_conversation public.conversations;
  v_locale text;
  v_rows jsonb;
  v_body text;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found then
    return;
  end if;

  select * into v_address from crm.contact_addresses
  where organization_id = p_organization_id and contact_id = v_lead.contact_id
  order by created_at desc
  limit 1;
  if not found then
    return;
  end if;

  select * into v_conversation from public.conversations
  where organization_id = p_organization_id
    and service = v_address.service and address = v_address.address
  order by last_inbound_at desc nulls last
  limit 1;
  if not found then
    return;
  end if;

  select coalesce(c.locale, 'en') into v_locale from crm.contacts c where c.id = v_lead.contact_id;

  select jsonb_agg(jsonb_build_object(
    'id', 'trial_slot::' || to_char(s.slot_start, 'YYYY-MM-DD"T"HH24:MI:SSOF'),
    'title', to_char(s.slot_start, 'Dy DD Mon, HH12:MI AM'),
    'description', case when v_locale = 'hi'
      then s.seats_left || ' सीटें उपलब्ध'
      else s.seats_left || ' seats left' end
  ))
  into v_rows
  from crm._upcoming_trial_slots(p_organization_id, 10) s;

  -- No schedule configured, or every upcoming slot is full -- nothing to
  -- offer. Graceful no-op, not an error: a rep can still book manually.
  if v_rows is null or jsonb_array_length(v_rows) = 0 then
    return;
  end if;

  v_body := case when v_locale = 'hi'
    then 'बढ़िया! आइए आपकी ट्रायल क्लास बुक करते हैं। एक समय चुनें:'
    else 'Great! Let''s book your trial class. Pick a time:' end;

  insert into public.messages (
    organization_id, conversation_id, service, organization_address,
    conversation_address, content
  ) values (
    p_organization_id, v_conversation.id, v_address.service,
    v_conversation.organization_address, v_address.address,
    jsonb_build_object(
      'version', '1', 'type', 'data', 'kind', 'interactive_list',
      'data', jsonb_build_object(
        'body', v_body,
        'button', case when v_locale = 'hi' then 'चुनें' else 'Choose' end,
        'sections', jsonb_build_array(jsonb_build_object(
          'title', case when v_locale = 'hi' then 'उपलब्ध समय' else 'Available times' end,
          'rows', v_rows
        ))
      )
    )
  );

  perform crm.write_audit(
    p_organization_id, 'lead.trial_offered', 'lead', p_lead_id::text,
    jsonb_build_object('slot_count', jsonb_array_length(v_rows))
  );
end;
$$;

-- Opt-in auto-offer (trial.auto_offer), same opt-in-setting shape as
-- assignment.auto_assign and qualification.auto_start -- an org must
-- deliberately turn this on, same "don't automate lead-facing sends
-- nobody asked for" reasoning as those two.
create function crm.z_offer_trial_on_qualified() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_auto_offer boolean;
begin
  v_auto_offer := coalesce(
    ((select r.value from crm.resolve_setting(new.organization_id, 'trial.auto_offer') r) #>> '{}')::boolean,
    false
  );

  if v_auto_offer then
    perform crm._send_trial_slot_offer(new.organization_id, new.id);
  end if;

  return new;
end;
$$;

create trigger z_offer_trial_on_qualified
after update
on crm.leads
for each row
when (new.status = 'qualified' and old.status is distinct from 'qualified')
execute function crm.z_offer_trial_on_qualified();

-- Moves a lead forward into this org's own "Trial Booked" pipeline stage
-- (the trading_institute pack ships one, preset key 'trial_booked',
-- crm.preset_lead_stages) the moment a trial is actually booked -- a
-- lead can rename or even delete that stage (P3-07b catalog admin), so
-- this resolves it by key, not id, and is a graceful no-op if it's gone.
-- Never moves a lead BACKWARD (e.g. already at a later stage like "Paid
-- Student"), and never fails the booking itself: a required-field gate
-- on that stage (crm._set_lead_stage) is caught and swallowed here --
-- the booking is the thing that must succeed, the stage move is a bonus.
create function crm._advance_to_trial_booked_stage(
  p_organization_id uuid,
  p_lead_id uuid
) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- Recognizes a tap on one of the offered slots (list_reply id prefixed
-- 'trial_slot::', the same '<key>::<value>' row-id convention P3-04's
-- qualification engine already established) and books it. A stale tap
-- (the slot has since passed or filled) re-offers a fresh list rather
-- than silently dropping the reply -- same recovery shape as the
-- qualification engine's "unrecognized reply -> nudge."
create function crm.z_handle_trial_slot_reply() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

create trigger z_handle_trial_slot_reply
after insert
on public.messages
for each row
when (new.sender_address is not null)
execute function crm.z_handle_trial_slot_reply();

-- Staff-driven booking/reschedule (deals.edit + lead visibility). Doubles
-- as "book manually" when the lead has no active booking yet -- the
-- cancel-then-insert is a no-op on the cancel side if there is nothing to
-- cancel. v1 scope, confirmed with the user: reschedule is staff-only,
-- from the lead card; a lead's own self-service "reschedule" reply is a
-- fast-follow, not built here.
create function crm.reschedule_trial_booking(
  p_lead_id uuid,
  p_slot_start timestamp with time zone
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

create function crm.cancel_trial_booking(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_booking crm.trial_bookings;
begin
  select * into v_booking from crm.trial_bookings where id = p_id;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_booking.organization_id, 'deals.edit');

  if not crm._lead_visible_to_caller(v_booking.lead_id) then
    raise exception 'booking not found' using errcode = 'P0002';
  end if;

  if v_booking.status <> 'booked' then
    raise exception 'booking is not active' using errcode = '22023';
  end if;

  update crm.trial_bookings
  set status = 'cancelled', cancelled_at = now()
  where id = p_id;

  perform crm.write_audit(
    v_booking.organization_id, 'lead.trial_cancelled', 'lead', v_booking.lead_id::text,
    jsonb_build_object('booking_id', p_id)
  );
end;
$$;

-- The platform-level, vertical-neutral customer-facing reminder template
-- -- same "seed directly, no vertical-pack-version bump" trick as P3-07d's
-- internal_task_reminder (no trading-specific wording, so it isn't
-- trading_institute pack content). pack_version 0 signals "not from a
-- vertical pack version," same convention.
create function crm.seed_trial_reminder_template(p_organization_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into crm.organization_pack_items (
    organization_id, kind, item_key, value, pack_version, sort_order
  )
  values (
    p_organization_id, 'message_template', 'trial_class_reminder',
    jsonb_build_object(
      'name', 'trial_class_reminder',
      'category', 'UTILITY',
      'purpose', 'Remind a lead of their upcoming trial class',
      'attach_disclaimer', false,
      'languages', jsonb_build_object(
        'en', jsonb_build_object(
          'body', 'Reminder: your trial class is coming up on {{1}}. See you there!',
          'examples', jsonb_build_array('Mon 03 Nov, 10:00 AM')
        ),
        'hi', jsonb_build_object(
          'body', 'याद दिलाना: आपकी ट्रायल क्लास {{1}} को है। वहाँ मिलते हैं!',
          'examples', jsonb_build_array('03 नवं, सुबह 10:00')
        )
      )
    ),
    0, 0
  )
  on conflict (organization_id, kind, item_key) do nothing;
end;
$$;

-- The reminder sweep. Always writes 'lead.trial_reminder_sent' to
-- crm.audit_log regardless of channel outcome (CLAUDE.md telemetry
-- mandate). WhatsApp only fires when the lead has a WhatsApp address AND
-- an APPROVED 'trial_class_reminder' template exists for the resolved
-- sender -- both missing is a graceful no-op, same as crm.
-- sweep_task_reminders.
create function crm.sweep_trial_reminders() returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_booking crm.trial_bookings;
  v_lead crm.leads;
  v_hours int;
  v_address crm.contact_addresses;
  v_sender_address text;
  v_template_lang text;
  v_conversation_id uuid;
  v_locale text;
  v_message_id uuid;
begin
  for v_booking in
    select * from crm.trial_bookings where status = 'booked' and reminder_sent_at is null
  loop
    v_hours := coalesce(
      ((select r.value from crm.resolve_setting(v_booking.organization_id, 'trial.reminder_hours_before') r) #>> '{}')::int,
      3
    );

    if v_booking.slot_start > now() + make_interval(hours => v_hours) then
      continue;
    end if;

    if v_booking.slot_start <= now() then
      -- Already past due with no reminder sent (e.g. the cron was down)
      -- -- mark it so the sweep stops retrying, but don't remind someone
      -- about a class that's already happened.
      update crm.trial_bookings set reminder_sent_at = now() where id = v_booking.id;
      perform crm.write_audit(
        v_booking.organization_id, 'lead.trial_reminder_sent', 'lead', v_booking.lead_id::text,
        jsonb_build_object('booking_id', v_booking.id, 'channel', 'skipped_past_due')
      );
      continue;
    end if;

    select * into v_lead from crm.leads where id = v_booking.lead_id;

    v_sender_address := null;
    v_template_lang := null;
    v_conversation_id := null;
    v_message_id := null;

    select * into v_address from crm.contact_addresses
    where organization_id = v_booking.organization_id and contact_id = v_lead.contact_id
      and service = 'whatsapp'
    order by created_at desc
    limit 1;

    if found then
      select ((select r.value from crm.resolve_setting(
        v_booking.organization_id, 'notifications.whatsapp_sender_address'
      ) r) #>> '{}')
      into v_sender_address;

      if v_sender_address is null or v_sender_address = '' then
        select oa.address into v_sender_address
        from public.organizations_addresses oa
        where oa.organization_id = v_booking.organization_id
          and oa.service = 'whatsapp' and oa.status = 'connected'
        order by oa.created_at asc
        limit 1;
      end if;

      if v_sender_address is not null then
        select coalesce(c.locale, 'en') into v_locale from crm.contacts c where c.id = v_lead.contact_id;

        select t.language into v_template_lang
        from crm.templates t
        where t.organization_id = v_booking.organization_id
          and t.organization_address = v_sender_address
          and t.name = 'trial_class_reminder'
          and t.status = 'APPROVED'
        order by (t.language = v_locale) desc, t.language
        limit 1;
      end if;
    end if;

    if v_template_lang is not null then
      insert into public.conversations (organization_id, service, organization_address, address)
      values (v_booking.organization_id, 'whatsapp', v_sender_address, v_address.address)
      on conflict (organization_id, organization_address, service, address) do nothing;

      select c.id into v_conversation_id from public.conversations c
      where c.organization_id = v_booking.organization_id
        and c.organization_address = v_sender_address
        and c.service = 'whatsapp' and c.address = v_address.address;

      insert into public.messages (
        organization_id, conversation_id, service, organization_address,
        conversation_address, content
      )
      values (
        v_booking.organization_id, v_conversation_id, 'whatsapp', v_sender_address,
        v_address.address,
        jsonb_build_object(
          'version', '1', 'type', 'data', 'kind', 'template',
          'data', jsonb_build_object(
            'name', 'trial_class_reminder',
            'language', jsonb_build_object('code', v_template_lang, 'policy', 'deterministic'),
            'components', jsonb_build_array(
              jsonb_build_object(
                'type', 'body',
                'parameters', jsonb_build_array(
                  jsonb_build_object(
                    'type', 'text',
                    'text', to_char(v_booking.slot_start, 'Dy DD Mon, HH12:MI AM')
                  )
                )
              )
            )
          )
        )
      )
      returning id into v_message_id;
    end if;

    update crm.trial_bookings set reminder_sent_at = now() where id = v_booking.id;

    perform crm.write_audit(
      v_booking.organization_id, 'lead.trial_reminder_sent', 'lead', v_booking.lead_id::text,
      jsonb_build_object(
        'booking_id', v_booking.id,
        'channel', case when v_message_id is not null then 'whatsapp' else 'none' end,
        'message_id', v_message_id
      )
    );
  end loop;
end;
$$;
