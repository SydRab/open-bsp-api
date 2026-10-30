-- [crm] P3-09: conversion-event mapping CRUD (organization.manage, same
-- bar P1-04's settings and P3-02's catalogs use for "configure org
-- behavior"), the enqueue choke point, and the outbox's claim/mark/replay
-- functions mirroring crm.webhook_events' own shape (10-29a).

create function crm.set_event_mapping(
  p_organization_id uuid,
  p_trigger_type text,
  p_trigger_value text,
  p_meta_event_name text
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

create function crm.delete_event_mapping(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- Seeded on org creation so "qualified leads report to Meta" works with
-- no setup, confirmed with the user -- same "defaults with no setup"
-- reasoning as P3-07d/P3-08's seeded templates. Fully editable/removable
-- afterwards; this is data, not a locked platform default.
create function crm.seed_default_event_mapping(p_organization_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into crm.lead_event_mappings (organization_id, trigger_type, trigger_status, meta_event_name)
  values (p_organization_id, 'status', 'qualified', 'Lead')
  on conflict (organization_id, trigger_status) where trigger_type = 'status'
  do nothing;
end;
$$;

-- The single enqueue choke point, called from crm._set_lead_stage and
-- crm.set_lead_status (10-29n) right after their own audit write -- same
-- "one place every caller benefits from" shape as crm._send_qualification_
-- question's public.messages insert. Unchecked/internal: both call sites
-- already did their own permission check before reaching here.
--
-- Only ad-sourced leads with a captured ctwa_clid get an outbox row --
-- an organic/manual lead was never attributed to an ad click, so there is
-- nothing for Meta to match the event against. p_trigger_value is a
-- status string (p_trigger_type = 'status') or a stage id as text
-- (p_trigger_type = 'stage').
create function crm._enqueue_conversion_event(
  p_organization_id uuid,
  p_lead_id uuid,
  p_trigger_type text,
  p_trigger_value text
) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- A trigger, not a call inside crm.set_lead_status, because status can
-- also change via a raw UPDATE that bypasses that function entirely --
-- crm._score_and_complete_qualification (P3-04) sets status directly.
-- Same "one trigger covers every path uniformly" lesson crm.
-- z_assign_on_qualified (P3-05) already established for the qualified
-- transition specifically; this generalizes it to every status value,
-- since trigger_type='status' mappings aren't limited to 'qualified'.
create function crm.z_enqueue_status_conversion_event() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm._enqueue_conversion_event(new.organization_id, new.id, 'status', new.status);
  return new;
end;
$$;

create trigger z_enqueue_status_conversion_event
after update
on crm.leads
for each row
when (new.status is distinct from old.status)
execute function crm.z_enqueue_status_conversion_event();

-- Atomic claim, same shape as crm.claim_webhook_event.
create function crm.claim_outbox_event(p_id uuid)
returns table (
  id uuid, organization_id uuid, lead_id uuid, organization_address text,
  event_name text, event_time timestamp with time zone, value numeric,
  currency text, ctwa_clid text, attempts int
)
language sql
security definer
set search_path to ''
as $$
  update crm.outbox_events
  set attempts = outbox_events.attempts + 1, last_attempt_at = now()
  where outbox_events.id = p_id and processed_at is null
  returning
    outbox_events.id, outbox_events.organization_id, outbox_events.lead_id,
    outbox_events.organization_address, outbox_events.event_name, outbox_events.event_time,
    outbox_events.value, outbox_events.currency, outbox_events.ctwa_clid, outbox_events.attempts;
$$;

create function crm.mark_outbox_event_sent(p_id uuid, p_meta_event_id text default null) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

create function crm.mark_outbox_event_failed(p_id uuid, p_error text) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- The replay tool (organization.manage): clears processed/attempt state
-- so the next cron tick picks it up again, same "no separate direct-
-- invoke path" shape as crm.replay_webhook_event -- except this one DOES
-- have a tenant-facing UI from day one (the roadmap's own "delivery log
-- and manual replay" line), unlike webhook_events' service-role-only tool.
create function crm.replay_outbox_event(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;
