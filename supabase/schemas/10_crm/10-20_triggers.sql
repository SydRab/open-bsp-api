-- Hooks into upstream tables. All additive: our own triggers on upstream
-- tables, no edits to upstream trigger functions.

-- New organization → profile, preset roles, default pack.
--
-- Named `crm_…` so it fires BEFORE upstream's `handle_new_organization`
-- (same timing, triggers fire in name order): the roles must exist when the
-- upstream trigger inserts the creator's owner agent, which
-- crm.after_agent_change then maps to the Owner role.
create function crm.after_insert_on_organizations() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into crm.organization_profiles (organization_id, slug)
  values (new.id, crm.generate_slug(new.name));

  perform crm.create_preset_roles(new.id);
  perform crm.apply_default_pack(new.id);
  -- [crm] P3-02
  perform crm.seed_lead_catalogs(new.id);

  return null;
end;
$$;

create trigger crm_handle_new_organization
after insert
on public.organizations
for each row
execute function crm.after_insert_on_organizations();

-- Keeps every human member's crm role consistent with the upstream tier.
--
--   * A member joining by invitation gets the invitation's crm role.
--   * Otherwise, when the tier changes under them (the upstream role editor,
--     seed data, an invitation made without crm.invite_member), they move to
--     the default preset for the new tier — unless their current role already
--     has that tier, which is also what stops the ping-pong with
--     crm.after_member_role_change below.
create function crm.after_agent_change() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_role_id uuid;
  v_current_tier public.role;
begin
  if new.user_id is null or new.deleted_at is not null then
    return null;
  end if;

  -- Joining (insert) or coming back (revival) via accept_invitation, which
  -- runs as the invitee, before it marks the invitation accepted.
  if (tg_op = 'INSERT' or old.deleted_at is not null)
    and new.user_id = auth.uid() then
    select ir.role_id into v_role_id
    from crm.invitation_roles ir
    join public.invitations i on i.id = ir.invitation_id
    where i.organization_id = new.organization_id
      and i.status = 'pending'
      and lower(i.email) = lower(auth.jwt()->>'email')
    order by i.created_at desc
    limit 1;
  end if;

  if v_role_id is null then
    select r.tier into v_current_tier
    from crm.member_roles mr
    join crm.roles r on r.id = mr.role_id
    where mr.agent_id = new.id;

    if v_current_tier = new.role then
      return null;
    end if;

    select r.id into v_role_id
    from crm.roles r
    where r.organization_id = new.organization_id
      and r.key = crm.default_role_key(new.role);

    if v_role_id is null then
      return null;
    end if;
  end if;

  insert into crm.member_roles (agent_id, organization_id, role_id)
  values (new.id, new.organization_id, v_role_id)
  on conflict (agent_id) do update
    set role_id = excluded.role_id,
        updated_at = now()
    where crm.member_roles.role_id is distinct from excluded.role_id;

  return null;
end;
$$;

create trigger crm_sync_member_role
after insert or update of role, deleted_at
on public.agents
for each row
execute function crm.after_agent_change();

-- The crm role decides the upstream tier. The update fires the upstream
-- last-owner guard, so demoting the last owner fails here too.
create function crm.after_member_role_change() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  update public.agents a
  set role = r.tier
  from crm.roles r
  where r.id = new.role_id
    and a.id = new.agent_id
    and a.role is distinct from r.tier;

  return null;
end;
$$;

create trigger sync_agent_tier
after insert or update of role_id
on crm.member_roles
for each row
execute function crm.after_member_role_change();

-- Profile validation the check constraints cannot express.
create function crm.before_write_on_organization_profiles() returns trigger
language plpgsql
-- Owner rights: it calls crm.validate_setting_value, which API roles cannot
-- execute. It only checks and tidies the row being written.
security definer
set search_path to ''
as $$
declare
  v_error text;
  v_registration jsonb;
  v_pattern text;
begin
  new.slug := lower(new.slug);

  if not exists (
    select 1 from pg_catalog.pg_timezone_names where name = new.timezone
  ) then
    raise exception 'unknown timezone %', new.timezone
      using errcode = '22023';
  end if;

  -- Business details (P1-07). Blank strings count as not given.
  new.legal_name := nullif(trim(new.legal_name), '');
  new.support_email := nullif(lower(trim(new.support_email)), '');
  new.support_phone := nullif(trim(new.support_phone), '');
  new.website := nullif(trim(new.website), '');

  if length(new.legal_name) > 200 then
    raise exception 'legal name is too long' using errcode = '22023';
  end if;
  if new.support_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid support email' using errcode = '22023';
  end if;
  if new.support_phone !~ '^\+?[0-9][0-9 ()-]{6,19}$' then
    raise exception 'invalid support phone' using errcode = '22023';
  end if;
  if new.website !~ '^https?://[^\s]{3,200}$' then
    raise exception 'website must start with http:// or https://' using errcode = '22023';
  end if;

  if new.address is not null then
    v_error := crm.validate_setting_value(
      '{"type": "object", "additionalProperties": false,
        "properties": {
          "line1": {"type": "string", "maxLength": 200},
          "line2": {"type": "string", "maxLength": 200},
          "city": {"type": "string", "maxLength": 100},
          "state": {"type": "string", "maxLength": 100},
          "postal_code": {"type": "string", "pattern": "^[0-9A-Za-z -]{3,12}$"},
          "country": {"type": "string", "pattern": "^[A-Z]{2}$"}}}',
      new.address,
      'address'
    );
    if v_error is not null then
      raise exception '%', v_error using errcode = '22023';
    end if;
  end if;

  v_error := crm.validate_setting_value(
    '{"type": "array", "maxItems": 10, "items": {
       "type": "object", "required": ["type", "number"], "additionalProperties": false,
       "properties": {
         "type": {"type": "string", "enum": ["gstin", "sebi_ra", "sebi_ia", "cin", "udyam", "other"]},
         "number": {"type": "string", "minLength": 2, "maxLength": 50}}}}',
    new.registrations,
    'registrations'
  );
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023';
  end if;

  -- Official formats, uppercase.
  new.registrations := coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', r->>'type', 'number', upper(trim(r->>'number'))
    ))
    from jsonb_array_elements(new.registrations) r
  ), '[]'::jsonb);
  for v_registration in select * from jsonb_array_elements(new.registrations) loop
    v_pattern := case v_registration->>'type'
      when 'gstin' then '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'
      when 'sebi_ra' then '^INH[0-9]{9}$'
      when 'sebi_ia' then '^INA[0-9]{9}$'
      when 'cin' then '^[LU][0-9]{5}[A-Z]{2}[0-9]{4}[A-Z]{3}[0-9]{6}$'
      when 'udyam' then '^UDYAM-[A-Z]{2}-[0-9]{2}-[0-9]{7}$'
    end;
    if v_pattern is not null and (v_registration->>'number') !~ v_pattern then
      raise exception 'invalid % number', upper(replace(v_registration->>'type', '_', ' '))
        using errcode = '22023';
    end if;
  end loop;

  return new;
end;
$$;

create trigger validate_profile
before insert or update
on crm.organization_profiles
for each row
execute function crm.before_write_on_organization_profiles();

-- An item is customized exactly when the tenant's value differs from the
-- pack's (see 10-04).
create function crm.before_write_on_organization_pack_items() returns trigger
language plpgsql
set search_path to ''
as $$
begin
  new.is_customized := new.value is distinct from new.pack_value;
  return new;
end;
$$;

create trigger track_customization
before insert or update
on crm.organization_pack_items
for each row
execute function crm.before_write_on_organization_pack_items();

create trigger set_updated_at
before update
on crm.organization_profiles
for each row
execute function public.moddatetime('updated_at');

create trigger set_updated_at
before update
on crm.roles
for each row
execute function public.moddatetime('updated_at');

create trigger set_updated_at
before update
on crm.organization_pack_items
for each row
execute function public.moddatetime('updated_at');
