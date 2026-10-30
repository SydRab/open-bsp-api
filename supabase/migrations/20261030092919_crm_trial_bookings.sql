alter table "crm"."notifications" drop constraint "notifications_kind_check";


  create table "crm"."trial_bookings" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "lead_id" uuid not null,
    "slot_start" timestamp with time zone not null,
    "slot_end" timestamp with time zone not null,
    "status" text not null default 'booked'::text,
    "confirmed_at" timestamp with time zone not null default now(),
    "cancelled_at" timestamp with time zone,
    "reminder_sent_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."trial_bookings" enable row level security;

CREATE INDEX trial_bookings_lead_id_idx ON crm.trial_bookings USING btree (organization_id, lead_id);

CREATE UNIQUE INDEX trial_bookings_pkey ON crm.trial_bookings USING btree (id);

CREATE INDEX trial_bookings_slot_idx ON crm.trial_bookings USING btree (organization_id, slot_start) WHERE (status = 'booked'::text);

alter table "crm"."trial_bookings" add constraint "trial_bookings_pkey" PRIMARY KEY using index "trial_bookings_pkey";

alter table "crm"."trial_bookings" add constraint "trial_bookings_cancelled_at_check" CHECK (((status = 'cancelled'::text) = (cancelled_at IS NOT NULL))) not valid;

alter table "crm"."trial_bookings" validate constraint "trial_bookings_cancelled_at_check";

alter table "crm"."trial_bookings" add constraint "trial_bookings_lead_fkey" FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE CASCADE not valid;

alter table "crm"."trial_bookings" validate constraint "trial_bookings_lead_fkey";

alter table "crm"."trial_bookings" add constraint "trial_bookings_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."trial_bookings" validate constraint "trial_bookings_organization_id_fkey";

alter table "crm"."trial_bookings" add constraint "trial_bookings_status_check" CHECK ((status = ANY (ARRAY['booked'::text, 'cancelled'::text, 'completed'::text]))) not valid;

alter table "crm"."trial_bookings" validate constraint "trial_bookings_status_check";

alter table "crm"."notifications" add constraint "notifications_kind_check" CHECK ((kind = ANY (ARRAY['lead_sla_breached'::text, 'lead_escalated_to_manager'::text, 'lead_auto_reassigned'::text, 'task_due'::text, 'trial_booked'::text]))) not valid;

alter table "crm"."notifications" validate constraint "notifications_kind_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._send_trial_slot_offer(p_organization_id uuid, p_lead_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm._upcoming_trial_slots(p_organization_id uuid, p_limit integer DEFAULT 10)
 RETURNS TABLE(slot_start timestamp with time zone, slot_end timestamp with time zone, seats_left integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.cancel_trial_booking(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.list_upcoming_trial_slots(p_organization_id uuid)
 RETURNS TABLE(slot_start timestamp with time zone, slot_end timestamp with time zone, seats_left integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(p_organization_id, 'deals.edit');
  return query select * from crm._upcoming_trial_slots(p_organization_id, 10);
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

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.seed_trial_reminder_template(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.sweep_trial_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.z_offer_trial_on_qualified()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.after_insert_on_organizations()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into crm.organization_profiles (organization_id, slug)
  values (new.id, crm.generate_slug(new.name));

  perform crm.create_preset_roles(new.id);
  perform crm.apply_default_pack(new.id);
  -- [crm] P3-02
  perform crm.seed_lead_catalogs(new.id);
  -- [crm] P3-04: after seed_lead_catalogs, so crm.lead_qualities already
  -- has rows for seed_qualification_scoring to resolve quality_key against.
  perform crm.seed_qualification_scoring(new.id);
  -- [crm] P3-07d
  perform crm.seed_task_reminder_template(new.id);
  -- [crm] P3-08
  perform crm.seed_trial_reminder_template(new.id);

  return null;
end;
$function$
;

grant select on table "crm"."trial_bookings" to "anon";

grant select on table "crm"."trial_bookings" to "authenticated";

grant delete on table "crm"."trial_bookings" to "service_role";

grant insert on table "crm"."trial_bookings" to "service_role";

grant references on table "crm"."trial_bookings" to "service_role";

grant select on table "crm"."trial_bookings" to "service_role";

grant trigger on table "crm"."trial_bookings" to "service_role";

grant truncate on table "crm"."trial_bookings" to "service_role";

grant update on table "crm"."trial_bookings" to "service_role";


  create policy "members can read trial bookings on leads they can see"
  on "crm"."trial_bookings"
  as permissive
  for select
  to authenticated, anon
using (((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)) AND crm._lead_visible_to_caller(lead_id)));


CREATE TRIGGER z_offer_trial_on_qualified AFTER UPDATE ON crm.leads FOR EACH ROW WHEN (((new.status = 'qualified'::text) AND (old.status IS DISTINCT FROM 'qualified'::text))) EXECUTE FUNCTION crm.z_offer_trial_on_qualified();

CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.trial_bookings FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER z_handle_trial_slot_reply AFTER INSERT ON public.messages FOR EACH ROW WHEN ((new.sender_address IS NOT NULL)) EXECUTE FUNCTION crm.z_handle_trial_slot_reply();


