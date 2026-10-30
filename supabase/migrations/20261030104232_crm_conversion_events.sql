
  create table "crm"."lead_event_mappings" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "trigger_type" text not null,
    "trigger_status" text,
    "trigger_stage_id" uuid,
    "meta_event_name" text not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."lead_event_mappings" enable row level security;


  create table "crm"."outbox_events" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "lead_id" uuid not null,
    "organization_address" text not null,
    "event_name" text not null,
    "event_time" timestamp with time zone not null,
    "value" numeric,
    "currency" text,
    "ctwa_clid" text not null,
    "processed_at" timestamp with time zone,
    "processing_error" text,
    "attempts" integer not null default 0,
    "last_attempt_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."outbox_events" enable row level security;

CREATE UNIQUE INDEX lead_event_mappings_pkey ON crm.lead_event_mappings USING btree (id);

CREATE UNIQUE INDEX lead_event_mappings_stage_key ON crm.lead_event_mappings USING btree (organization_id, trigger_stage_id) WHERE (trigger_type = 'stage'::text);

CREATE UNIQUE INDEX lead_event_mappings_status_key ON crm.lead_event_mappings USING btree (organization_id, trigger_status) WHERE (trigger_type = 'status'::text);

CREATE INDEX outbox_events_lead_id_idx ON crm.outbox_events USING btree (organization_id, lead_id);

CREATE INDEX outbox_events_pending_idx ON crm.outbox_events USING btree (organization_id, created_at) WHERE ((processed_at IS NULL) AND (attempts < 5));

CREATE UNIQUE INDEX outbox_events_pkey ON crm.outbox_events USING btree (id);

alter table "crm"."lead_event_mappings" add constraint "lead_event_mappings_pkey" PRIMARY KEY using index "lead_event_mappings_pkey";

alter table "crm"."outbox_events" add constraint "outbox_events_pkey" PRIMARY KEY using index "outbox_events_pkey";

alter table "crm"."lead_event_mappings" add constraint "lead_event_mappings_meta_event_name_check" CHECK (((length(TRIM(BOTH FROM meta_event_name)) >= 1) AND (length(TRIM(BOTH FROM meta_event_name)) <= 40))) not valid;

alter table "crm"."lead_event_mappings" validate constraint "lead_event_mappings_meta_event_name_check";

alter table "crm"."lead_event_mappings" add constraint "lead_event_mappings_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."lead_event_mappings" validate constraint "lead_event_mappings_organization_id_fkey";

alter table "crm"."lead_event_mappings" add constraint "lead_event_mappings_stage_fkey" FOREIGN KEY (organization_id, trigger_stage_id) REFERENCES crm.lead_stages(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."lead_event_mappings" validate constraint "lead_event_mappings_stage_fkey";

alter table "crm"."lead_event_mappings" add constraint "lead_event_mappings_trigger_stage_check" CHECK (((trigger_type = 'stage'::text) = (trigger_stage_id IS NOT NULL))) not valid;

alter table "crm"."lead_event_mappings" validate constraint "lead_event_mappings_trigger_stage_check";

alter table "crm"."lead_event_mappings" add constraint "lead_event_mappings_trigger_status_check" CHECK (((trigger_type = 'status'::text) = (trigger_status IS NOT NULL))) not valid;

alter table "crm"."lead_event_mappings" validate constraint "lead_event_mappings_trigger_status_check";

alter table "crm"."lead_event_mappings" add constraint "lead_event_mappings_trigger_status_value_check" CHECK (((trigger_status IS NULL) OR (trigger_status = ANY (ARRAY['open'::text, 'qualified'::text, 'unqualified'::text, 'converted'::text, 'dropped'::text])))) not valid;

alter table "crm"."lead_event_mappings" validate constraint "lead_event_mappings_trigger_status_value_check";

alter table "crm"."lead_event_mappings" add constraint "lead_event_mappings_trigger_type_check" CHECK ((trigger_type = ANY (ARRAY['status'::text, 'stage'::text]))) not valid;

alter table "crm"."lead_event_mappings" validate constraint "lead_event_mappings_trigger_type_check";

alter table "crm"."outbox_events" add constraint "outbox_events_lead_fkey" FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE CASCADE not valid;

alter table "crm"."outbox_events" validate constraint "outbox_events_lead_fkey";

alter table "crm"."outbox_events" add constraint "outbox_events_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."outbox_events" validate constraint "outbox_events_organization_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._enqueue_conversion_event(p_organization_id uuid, p_lead_id uuid, p_trigger_type text, p_trigger_value text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads;
  v_ctwa_clid text;
  v_mapping crm.lead_event_mappings;
  v_peer_service public.service;
  v_peer_address text;
  v_org_address text;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found or v_lead.source not in ('ctwa_ad', 'ctwa_post') then
    return;
  end if;

  select c.first_touch_referral->>'ctwa_clid' into v_ctwa_clid
  from crm.contacts c where c.id = v_lead.contact_id;
  if v_ctwa_clid is null or v_ctwa_clid = '' then
    return;
  end if;

  if p_trigger_type = 'status' then
    select * into v_mapping from crm.lead_event_mappings
    where organization_id = p_organization_id and trigger_type = 'status' and trigger_status = p_trigger_value;
  else
    select * into v_mapping from crm.lead_event_mappings
    where organization_id = p_organization_id and trigger_type = 'stage'
      and trigger_stage_id = p_trigger_value::uuid;
  end if;
  if not found then
    return;
  end if;

  select ca.service, ca.address into v_peer_service, v_peer_address
  from crm.contact_addresses ca
  where ca.organization_id = p_organization_id and ca.contact_id = v_lead.contact_id
  order by ca.created_at desc
  limit 1;
  if not found then
    return;
  end if;

  select c.organization_address into v_org_address
  from public.conversations c
  where c.organization_id = p_organization_id and c.service = v_peer_service and c.address = v_peer_address
  order by c.last_inbound_at desc nulls last
  limit 1;
  if not found then
    return;
  end if;

  insert into crm.outbox_events (
    organization_id, lead_id, organization_address, event_name, event_time,
    value, currency, ctwa_clid
  ) values (
    p_organization_id, p_lead_id, v_org_address, v_mapping.meta_event_name, now(),
    v_lead.deal_value, case when v_lead.deal_value is not null then 'INR' else null end, v_ctwa_clid
  );

  perform crm.write_audit(
    p_organization_id, 'lead.conversion_event_enqueued', 'lead', p_lead_id::text,
    jsonb_build_object('event_name', v_mapping.meta_event_name, 'ctwa_clid', v_ctwa_clid)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.claim_outbox_event(p_id uuid)
 RETURNS TABLE(id uuid, organization_id uuid, lead_id uuid, organization_address text, event_name text, event_time timestamp with time zone, value numeric, currency text, ctwa_clid text, attempts integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  update crm.outbox_events
  set attempts = outbox_events.attempts + 1, last_attempt_at = now()
  where outbox_events.id = p_id and processed_at is null
  returning
    outbox_events.id, outbox_events.organization_id, outbox_events.lead_id,
    outbox_events.organization_address, outbox_events.event_name, outbox_events.event_time,
    outbox_events.value, outbox_events.currency, outbox_events.ctwa_clid, outbox_events.attempts;
$function$
;

CREATE OR REPLACE FUNCTION crm.delete_event_mapping(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
begin
  select organization_id into v_org from crm.lead_event_mappings where id = p_id;
  if v_org is null then
    raise exception 'mapping not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_org, 'organization.manage');

  delete from crm.lead_event_mappings where id = p_id;

  perform crm.write_audit(
    v_org, 'event_mapping.deleted', 'lead_event_mapping', p_id::text, '{}'::jsonb
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.mark_outbox_event_failed(p_id uuid, p_error text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row crm.outbox_events;
begin
  select * into v_row from crm.outbox_events where id = p_id;
  if not found then
    return;
  end if;

  update crm.outbox_events
  set processing_error = p_error
  where id = p_id;

  perform crm.write_audit(
    v_row.organization_id, 'lead.conversion_event_failed', 'lead', v_row.lead_id::text,
    jsonb_build_object(
      'outbox_id', p_id, 'event_name', v_row.event_name, 'error', p_error, 'attempts', v_row.attempts
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.mark_outbox_event_sent(p_id uuid, p_meta_event_id text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row crm.outbox_events;
begin
  select * into v_row from crm.outbox_events where id = p_id;
  if not found then
    return;
  end if;

  update crm.outbox_events
  set processed_at = now(), processing_error = null
  where id = p_id;

  perform crm.write_audit(
    v_row.organization_id, 'lead.conversion_event_sent', 'lead', v_row.lead_id::text,
    jsonb_build_object('outbox_id', p_id, 'event_name', v_row.event_name, 'meta_event_id', p_meta_event_id)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.replay_outbox_event(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_row crm.outbox_events;
begin
  select * into v_row from crm.outbox_events where id = p_id;
  if not found then
    raise exception 'event not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_row.organization_id, 'organization.manage');

  update crm.outbox_events
  set processed_at = null, attempts = 0, processing_error = null, last_attempt_at = null
  where id = p_id;

  perform crm.write_audit(
    v_row.organization_id, 'lead.conversion_event_replayed', 'lead', v_row.lead_id::text,
    jsonb_build_object('outbox_id', p_id)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.seed_default_event_mapping(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into crm.lead_event_mappings (organization_id, trigger_type, trigger_status, meta_event_name)
  values (p_organization_id, 'status', 'qualified', 'Lead')
  on conflict (organization_id, trigger_status) where trigger_type = 'status'
  do nothing;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_event_mapping(p_organization_id uuid, p_trigger_type text, p_trigger_value text, p_meta_event_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_stage_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  if p_trigger_type not in ('status', 'stage') then
    raise exception 'trigger_type must be status or stage' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_meta_event_name, ''))) = 0 then
    raise exception 'meta_event_name is required' using errcode = '22023';
  end if;

  if p_trigger_type = 'status' then
    if p_trigger_value not in ('open', 'qualified', 'unqualified', 'converted', 'dropped') then
      raise exception 'unknown lead status' using errcode = '22023';
    end if;

    insert into crm.lead_event_mappings (organization_id, trigger_type, trigger_status, meta_event_name)
    values (p_organization_id, 'status', p_trigger_value, trim(p_meta_event_name))
    on conflict (organization_id, trigger_status) where trigger_type = 'status'
      do update set meta_event_name = excluded.meta_event_name
    returning id into v_id;
  else
    v_stage_id := p_trigger_value::uuid;
    if not exists (
      select 1 from crm.lead_stages where id = v_stage_id and organization_id = p_organization_id
    ) then
      raise exception 'stage not found' using errcode = '22023';
    end if;

    insert into crm.lead_event_mappings (organization_id, trigger_type, trigger_stage_id, meta_event_name)
    values (p_organization_id, 'stage', v_stage_id, trim(p_meta_event_name))
    on conflict (organization_id, trigger_stage_id) where trigger_type = 'stage'
      do update set meta_event_name = excluded.meta_event_name
    returning id into v_id;
  end if;

  perform crm.write_audit(
    p_organization_id, 'event_mapping.set', 'lead_event_mapping', v_id::text,
    jsonb_build_object(
      'trigger_type', p_trigger_type, 'trigger_value', p_trigger_value,
      'meta_event_name', trim(p_meta_event_name)
    )
  );

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.z_enqueue_status_conversion_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm._enqueue_conversion_event(new.organization_id, new.id, 'status', new.status);
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm._set_lead_stage(p_lead_id uuid, p_organization_id uuid, p_stage_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_missing text;
begin
  if p_stage_id is not null and not exists (
    select 1 from crm.lead_stages where id = p_stage_id and organization_id = p_organization_id
  ) then
    raise exception 'stage not found' using errcode = '22023';
  end if;

  if p_stage_id is not null then
    select string_agg(d.value->'label'->>'en', ', ' order by d.sort_order)
    into v_missing
    from crm.lead_stage_required_fields rf
    join crm.organization_pack_items d on d.id = rf.field_id
    join crm.leads l on l.id = p_lead_id
    where rf.stage_id = p_stage_id
      and not coalesce((d.value->>'archived')::boolean, false)
      and not l.custom_fields ? d.item_key;
    if v_missing is not null then
      raise exception 'required for this stage: %', v_missing using errcode = '22023';
    end if;
  end if;

  update crm.leads set stage_id = p_stage_id where id = p_lead_id;

  perform crm.write_audit(
    p_organization_id, 'lead.stage_changed', 'lead', p_lead_id::text,
    jsonb_build_object('stage_id', p_stage_id)
  );

  -- [crm] P3-09: moving OUT of a stage (p_stage_id null) has nothing to
  -- report; also covers crm._advance_to_trial_booked_stage's (P3-08) own
  -- call into this same function, for free -- one choke point, every
  -- caller benefits.
  if p_stage_id is not null then
    perform crm._enqueue_conversion_event(p_organization_id, p_lead_id, 'stage', p_stage_id::text);
  end if;
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
  -- [crm] P3-09
  perform crm.seed_default_event_mapping(new.id);

  return null;
end;
$function$
;

grant select on table "crm"."lead_event_mappings" to "anon";

grant select on table "crm"."lead_event_mappings" to "authenticated";

grant delete on table "crm"."lead_event_mappings" to "service_role";

grant insert on table "crm"."lead_event_mappings" to "service_role";

grant references on table "crm"."lead_event_mappings" to "service_role";

grant select on table "crm"."lead_event_mappings" to "service_role";

grant trigger on table "crm"."lead_event_mappings" to "service_role";

grant truncate on table "crm"."lead_event_mappings" to "service_role";

grant update on table "crm"."lead_event_mappings" to "service_role";

grant select on table "crm"."outbox_events" to "anon";

grant select on table "crm"."outbox_events" to "authenticated";

grant delete on table "crm"."outbox_events" to "service_role";

grant insert on table "crm"."outbox_events" to "service_role";

grant references on table "crm"."outbox_events" to "service_role";

grant select on table "crm"."outbox_events" to "service_role";

grant trigger on table "crm"."outbox_events" to "service_role";

grant truncate on table "crm"."outbox_events" to "service_role";

grant update on table "crm"."outbox_events" to "service_role";


  create policy "members can read event mappings"
  on "crm"."lead_event_mappings"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "members can read outbox events"
  on "crm"."outbox_events"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.lead_event_mappings FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER z_enqueue_status_conversion_event AFTER UPDATE ON crm.leads FOR EACH ROW WHEN ((new.status IS DISTINCT FROM old.status)) EXECUTE FUNCTION crm.z_enqueue_status_conversion_event();


