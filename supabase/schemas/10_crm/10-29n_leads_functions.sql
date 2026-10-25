-- [crm] P3-02: lead model functions.
--
-- Catalog management (create/update/delete a stage/quality/drop reason) is
-- gated on 'organization.manage' -- admin-tier, already exists, fits
-- "configure org settings" without a new permission or a ripple into the
-- admin console's role editor for a feature this size.
--
-- Working a lead (claiming/reopening it, moving its stage/quality/status)
-- is gated on 'deals.edit' instead -- member-tier, already granted to
-- sales_manager/sales_rep by default, and its own catalog description
-- ("Create deals and move them between stages") already describes exactly
-- this action.

-- Platform defaults -> one org's editable copy, the same shape
-- crm.create_preset_roles uses for crm.preset_roles. Called from
-- crm.after_insert_on_organizations (10-20_triggers.sql).
create function crm.seed_lead_catalogs(p_organization_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into crm.lead_stages (organization_id, key, name, is_preset, sort_order)
  select p_organization_id, key, name, true, sort_order
  from crm.preset_lead_stages
  on conflict (organization_id, key) do nothing;

  insert into crm.lead_qualities (organization_id, key, name, is_preset, sort_order)
  select p_organization_id, key, name, true, sort_order
  from crm.preset_lead_qualities
  on conflict (organization_id, key) do nothing;

  insert into crm.lead_drop_reasons (organization_id, key, name, is_preset, sort_order)
  select p_organization_id, key, name, true, sort_order
  from crm.preset_lead_drop_reasons
  on conflict (organization_id, key) do nothing;
end;
$$;

-- Lead stages ---------------------------------------------------------------------------------

create function crm.create_lead_stage(p_organization_id uuid, p_name text) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
  v_base text;
  v_key text;
  v_suffix int := 0;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  v_base := trim(both '_' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '_', 'g'));
  if v_base = '' then
    v_base := 'stage';
  end if;

  v_key := v_base;
  while exists (
    select 1 from crm.lead_stages
    where organization_id = p_organization_id and key = v_key
  ) loop
    v_suffix := v_suffix + 1;
    v_key := v_base || '_' || v_suffix;
  end loop;

  insert into crm.lead_stages (organization_id, key, name, is_preset, sort_order)
  values (
    p_organization_id, v_key, trim(p_name), false,
    coalesce(
      (select max(sort_order) + 1 from crm.lead_stages where organization_id = p_organization_id),
      0
    )
  )
  returning id into v_id;

  return v_id;
end;
$$;

create function crm.update_lead_stage(p_id uuid, p_name text, p_sort_order int) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select organization_id from crm.lead_stages where id = p_id),
    'organization.manage'
  );

  update crm.lead_stages
  set name = trim(p_name), sort_order = p_sort_order
  where id = p_id;
end;
$$;

create function crm.delete_lead_stage(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select organization_id from crm.lead_stages where id = p_id),
    'organization.manage'
  );

  delete from crm.lead_stages where id = p_id;
end;
$$;

-- Lead qualities ------------------------------------------------------------------------------

create function crm.create_lead_quality(p_organization_id uuid, p_name text) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
  v_base text;
  v_key text;
  v_suffix int := 0;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  v_base := trim(both '_' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '_', 'g'));
  if v_base = '' then
    v_base := 'quality';
  end if;

  v_key := v_base;
  while exists (
    select 1 from crm.lead_qualities
    where organization_id = p_organization_id and key = v_key
  ) loop
    v_suffix := v_suffix + 1;
    v_key := v_base || '_' || v_suffix;
  end loop;

  insert into crm.lead_qualities (organization_id, key, name, is_preset, sort_order)
  values (
    p_organization_id, v_key, trim(p_name), false,
    coalesce(
      (select max(sort_order) + 1 from crm.lead_qualities where organization_id = p_organization_id),
      0
    )
  )
  returning id into v_id;

  return v_id;
end;
$$;

create function crm.update_lead_quality(p_id uuid, p_name text, p_sort_order int) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select organization_id from crm.lead_qualities where id = p_id),
    'organization.manage'
  );

  update crm.lead_qualities
  set name = trim(p_name), sort_order = p_sort_order
  where id = p_id;
end;
$$;

create function crm.delete_lead_quality(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select organization_id from crm.lead_qualities where id = p_id),
    'organization.manage'
  );

  delete from crm.lead_qualities where id = p_id;
end;
$$;

-- Lead drop reasons ---------------------------------------------------------------------------

create function crm.create_lead_drop_reason(p_organization_id uuid, p_name text) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
  v_base text;
  v_key text;
  v_suffix int := 0;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  v_base := trim(both '_' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '_', 'g'));
  if v_base = '' then
    v_base := 'reason';
  end if;

  v_key := v_base;
  while exists (
    select 1 from crm.lead_drop_reasons
    where organization_id = p_organization_id and key = v_key
  ) loop
    v_suffix := v_suffix + 1;
    v_key := v_base || '_' || v_suffix;
  end loop;

  insert into crm.lead_drop_reasons (organization_id, key, name, is_preset, sort_order)
  values (
    p_organization_id, v_key, trim(p_name), false,
    coalesce(
      (select max(sort_order) + 1 from crm.lead_drop_reasons where organization_id = p_organization_id),
      0
    )
  )
  returning id into v_id;

  return v_id;
end;
$$;

create function crm.update_lead_drop_reason(p_id uuid, p_name text, p_sort_order int) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select organization_id from crm.lead_drop_reasons where id = p_id),
    'organization.manage'
  );

  update crm.lead_drop_reasons
  set name = trim(p_name), sort_order = p_sort_order
  where id = p_id;
end;
$$;

create function crm.delete_lead_drop_reason(p_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(
    (select organization_id from crm.lead_drop_reasons where id = p_id),
    'organization.manage'
  );

  delete from crm.lead_drop_reasons where id = p_id;
end;
$$;

-- Leads -----------------------------------------------------------------------------------------

-- The dedupe/reopen entry point. Deliberately not wired into any trigger
-- yet (scope cut, P3-02) -- whichever task first needs a lead to exist
-- (P3-03's instant welcome, P3-04's qualification engine) calls this.
create function crm.find_or_create_lead(
  p_organization_id uuid,
  p_contact_id uuid,
  p_source text
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_lead crm.leads;
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'deals.edit');

  select * into v_lead from crm.leads
  where organization_id = p_organization_id and contact_id = p_contact_id;

  if found then
    -- Reopen rule: dropped/unqualified can come back to open (a lead
    -- messaging again is still working the same pursuit). converted is
    -- terminal -- a repeat inquiry from an already-enrolled contact is a
    -- different scenario (upsell/renewal) this phase's strict
    -- one-lead-per-contact dedupe isn't designed for.
    if v_lead.status in ('dropped', 'unqualified') then
      update crm.leads
      set status = 'open', drop_reason_id = null
      where id = v_lead.id;

      perform crm.write_audit(
        p_organization_id, 'lead.reopened', 'lead', v_lead.id::text,
        jsonb_build_object('from_status', v_lead.status)
      );
    end if;

    return v_lead.id;
  end if;

  insert into crm.leads (organization_id, contact_id, source)
  values (p_organization_id, p_contact_id, p_source)
  returning id into v_id;

  perform crm.write_audit(
    p_organization_id, 'lead.created', 'lead', v_id::text,
    jsonb_build_object('source', p_source)
  );

  return v_id;
end;
$$;

create function crm.set_lead_stage(p_lead_id uuid, p_stage_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_org uuid;
begin
  select organization_id into v_org from crm.leads where id = p_lead_id;

  if v_org is null then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if p_stage_id is not null and not exists (
    select 1 from crm.lead_stages where id = p_stage_id and organization_id = v_org
  ) then
    raise exception 'stage not found' using errcode = '22023';
  end if;

  update crm.leads set stage_id = p_stage_id where id = p_lead_id;

  perform crm.write_audit(
    v_org, 'lead.stage_changed', 'lead', p_lead_id::text,
    jsonb_build_object('stage_id', p_stage_id)
  );
end;
$$;

create function crm.set_lead_quality(p_lead_id uuid, p_quality_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_org uuid;
begin
  select organization_id into v_org from crm.leads where id = p_lead_id;

  if v_org is null then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if p_quality_id is not null and not exists (
    select 1 from crm.lead_qualities where id = p_quality_id and organization_id = v_org
  ) then
    raise exception 'quality not found' using errcode = '22023';
  end if;

  update crm.leads set quality_id = p_quality_id where id = p_lead_id;

  perform crm.write_audit(
    v_org, 'lead.quality_changed', 'lead', p_lead_id::text,
    jsonb_build_object('quality_id', p_quality_id)
  );
end;
$$;

create function crm.set_lead_status(
  p_lead_id uuid,
  p_status text,
  p_drop_reason_id uuid default null
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_lead crm.leads;
begin
  select * into v_lead from crm.leads where id = p_lead_id;

  if not found then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_lead.organization_id, 'deals.edit');

  if v_lead.status = 'converted' and p_status <> 'converted' then
    raise exception 'a converted lead cannot change status' using errcode = '22023';
  end if;

  if p_status = 'dropped' then
    if p_drop_reason_id is null then
      raise exception 'a drop reason is required' using errcode = '22023';
    end if;
    if not exists (
      select 1 from crm.lead_drop_reasons
      where id = p_drop_reason_id and organization_id = v_lead.organization_id
    ) then
      raise exception 'drop reason not found' using errcode = '22023';
    end if;
  end if;

  update crm.leads
  set
    status = p_status,
    drop_reason_id = case when p_status = 'dropped' then p_drop_reason_id else null end
  where id = p_lead_id;

  perform crm.write_audit(
    v_lead.organization_id, 'lead.status_changed', 'lead', p_lead_id::text,
    jsonb_build_object('from_status', v_lead.status, 'to_status', p_status)
  );
end;
$$;
