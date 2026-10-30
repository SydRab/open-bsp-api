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

-- [crm] P3-07b: replace-all setter for a stage's required deal-entity
-- fields (crm.lead_stage_required_fields, 10-29m) -- simpler than
-- individual add/remove functions for a plain multi-select picker.
create function crm.set_stage_required_fields(p_stage_id uuid, p_field_ids uuid[])
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_org uuid;
begin
  select organization_id into v_org from crm.lead_stages where id = p_stage_id;
  if v_org is null then
    raise exception 'stage not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_org, 'organization.manage');

  if exists (
    select 1 from unnest(coalesce(p_field_ids, '{}'::uuid[])) f(id)
    where not exists (
      select 1 from crm.organization_pack_items d
      where d.id = f.id and d.organization_id = v_org
        and d.kind = 'custom_field' and d.value->>'entity' = 'deal'
    )
  ) then
    raise exception 'one or more fields were not found' using errcode = '22023';
  end if;

  delete from crm.lead_stage_required_fields where stage_id = p_stage_id;

  insert into crm.lead_stage_required_fields (organization_id, stage_id, field_id)
  select v_org, p_stage_id, f.id from unnest(coalesce(p_field_ids, '{}'::uuid[])) f(id);

  perform crm.write_audit(
    v_org, 'lead_stage.required_fields_changed', 'lead_stage', p_stage_id::text,
    jsonb_build_object('field_ids', to_jsonb(p_field_ids))
  );
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

-- The dedupe/reopen/create core, no permission check -- P3-03's instant-
-- welcome trigger (10-29o) calls this directly, since a trigger has no
-- member/JWT context for crm.require_permission to check (same reasoning
-- crm.after_insert_on_contacts_addresses skips a permission check
-- entirely: it's a system side effect, not a user action). The public,
-- permission-checked crm.find_or_create_lead below is for a future human-
-- facing caller (e.g. a manual "add lead" action) and just wraps this.
create function crm._ensure_lead(
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

-- Member-facing wrapper: same dedupe/reopen/create, gated on deals.edit.
create function crm.find_or_create_lead(
  p_organization_id uuid,
  p_contact_id uuid,
  p_source text
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(p_organization_id, 'deals.edit');

  return crm._ensure_lead(p_organization_id, p_contact_id, p_source);
end;
$$;

-- [crm] P3-07b: the move itself, including the required-fields check
-- (crm.lead_stage_required_fields, 10-29m) -- shared by crm.set_lead_stage
-- (one lead) and crm.bulk_set_lead_stage (many) so the rule can't be
-- bypassed by hitting only one of the two call sites. Unchecked -- callers
-- check deals.edit once, before the (possible) loop.
create function crm._set_lead_stage(
  p_lead_id uuid,
  p_organization_id uuid,
  p_stage_id uuid
) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
  perform crm._set_lead_stage(p_lead_id, v_org, p_stage_id);
end;
$$;

-- [crm] P3-07b: the kanban board's bulk move. One permission check, then
-- the same per-lead logic set_lead_stage uses (including the
-- required-fields check) -- if any lead in the batch fails, the whole
-- call rolls back rather than moving some and silently skipping others.
-- All leads must belong to the same org as the first one (always true in
-- practice -- the board only ever selects from one org's view).
create function crm.bulk_set_lead_stage(p_lead_ids uuid[], p_stage_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_org uuid;
  v_lead_id uuid;
begin
  if p_lead_ids is null or array_length(p_lead_ids, 1) is null then
    raise exception 'no leads given' using errcode = '22023';
  end if;

  select organization_id into v_org from crm.leads where id = p_lead_ids[1];
  if v_org is null then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if (select count(*) from crm.leads where id = any(p_lead_ids) and organization_id = v_org)
     <> array_length(p_lead_ids, 1) then
    raise exception 'one or more leads were not found in this organization'
      using errcode = '22023';
  end if;

  foreach v_lead_id in array p_lead_ids loop
    perform crm._set_lead_stage(v_lead_id, v_org, p_stage_id);
  end loop;
end;
$$;

-- [crm] P3-07b: same idea as crm.set_contact_fields (10-17_custom_fields.sql)
-- for the 'deal' entity -- enforces each field definition's own global
-- "required" flag (crm.field_definition_error's 'required', independent
-- of crm.lead_stage_required_fields' per-stage rule, checked separately
-- inside crm._set_lead_stage). Lives here rather than 10-17 since that
-- file is applied before crm.leads (10-29m) exists. Unlike
-- set_contact_fields (which runs as the caller, relying on crm.contacts'
-- own UPDATE RLS policy), crm.leads has no such policy -- every other
-- lead-mutating function uses an explicit permission check instead, so
-- this does too, security definer like its siblings.
create function crm.set_lead_fields(p_lead_id uuid, p_values jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_lead crm.leads;
  v_merged jsonb;
  v_missing text;
begin
  select * into v_lead from crm.leads l where l.id = p_lead_id;
  if not found then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;
  if not crm.has_permission(v_lead.organization_id, 'deals.edit') then
    raise exception 'permission deals.edit required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_values) is distinct from 'object' then
    raise exception 'values must be an object' using errcode = '22023';
  end if;

  v_merged := crm.clean_custom_fields(v_lead.custom_fields || p_values);

  select string_agg(d.value->'label'->>'en', ', ' order by d.sort_order)
  into v_missing
  from crm.organization_pack_items d
  where d.organization_id = v_lead.organization_id
    and d.kind = 'custom_field'
    and d.value->>'entity' = 'deal'
    and coalesce((d.value->>'required')::boolean, false)
    and not coalesce((d.value->>'archived')::boolean, false)
    and not v_merged ? d.item_key;
  if v_missing is not null then
    raise exception 'required: %', v_missing using errcode = '22023';
  end if;

  update crm.leads set custom_fields = v_merged
  where id = p_lead_id
  returning * into v_lead;
  if not found then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  return v_lead.custom_fields;
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

create function crm.set_lead_deal_value(p_lead_id uuid, p_value numeric) returns void
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

  if p_value is not null and p_value < 0 then
    raise exception 'deal value cannot be negative' using errcode = '22023';
  end if;

  update crm.leads set deal_value = p_value where id = p_lead_id;

  perform crm.write_audit(
    v_org, 'lead.deal_value_changed', 'lead', p_lead_id::text,
    jsonb_build_object('deal_value', p_value)
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

-- [crm] P3-07c: a lead's own history timeline. Gated on deals.edit, not
-- audit.view (crm.get_audit_log, 10-14) -- audit.view is admin/owner-only
-- today, which would hide this from sales_rep/sales_manager, the people
-- who actually work leads. Being SECURITY DEFINER bypasses crm.audit_log's
-- own audit.view-gated RLS (10-30), so lead visibility is re-checked here
-- with the same lead_scope predicate crm.leads' own RLS policy uses --
-- duplicated rather than shared, same as crm._lead_escalation_managers
-- (P3-06) duplicates team-membership logic rather than factoring it out.
-- "lead not found" covers both "doesn't exist" and "not visible to you,"
-- deliberately, so this can't be used to probe for another rep's leads.
create function crm.get_lead_history(p_lead_id uuid) returns table (
  id bigint,
  created_at timestamp with time zone,
  actor_type text,
  actor_agent_id uuid,
  actor_name text,
  action text,
  details jsonb
)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_org uuid;
begin
  select l.organization_id into v_org from crm.leads l where l.id = p_lead_id;
  if v_org is null then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if not exists (
    select 1 from crm.leads l
    where l.id = p_lead_id
      and (
        crm.resolve_lead_scope(l.organization_id) = 'all'
        or (
          crm.resolve_lead_scope(l.organization_id) = 'team'
          and l.assigned_to in (
            select tm2.agent_id
            from crm.team_members tm1
            join crm.team_members tm2 on tm2.team_id = tm1.team_id
            where tm1.agent_id = (crm.caller_agent(l.organization_id)).id
          )
        )
        or (
          crm.resolve_lead_scope(l.organization_id) = 'own'
          and l.assigned_to = (crm.caller_agent(l.organization_id)).id
        )
      )
  ) then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  return query
  select
    l.id,
    l.created_at,
    l.actor_type,
    l.actor_agent_id,
    coalesce(actor.name, ak.name),
    l.action,
    l.details
  from crm.audit_log l
  left join public.agents actor on actor.id = l.actor_agent_id
  left join public.api_keys ak on ak.id = l.actor_api_key_id
  where l.organization_id = v_org
    and l.target_type = 'lead'
    and l.target_id = p_lead_id::text
  order by l.id desc
  limit 200;
end;
$$;
