-- [crm] P4-04: campaign builder. A campaign ties a WhatsApp template (P2-04,
-- crm.templates) to a segment (P4-03, crm.segments) and a variable mapping
-- (which contact field, or a fixed literal, fills each {{n}} placeholder).
-- P4-06 (the fan-out send engine) does not exist yet, and P4-05 (the
-- approval workflow) sits between building and sending -- so a campaign
-- here only ever reaches 'draft' or 'scheduled'. Nothing in this file ever
-- sends to a campaign's real audience; the only real WhatsApp send is
-- crm.send_test_campaign_message, a single message to the calling member's
-- OWN connected number (crm.member_roles.whatsapp_address, the self-service
-- field P3-07d built), through the exact same insert-into-messages path
-- every other send uses -- so it still passes every compliance gate
-- (_shared/send_policy.ts), deliberately not bypassed for being "just a
-- test."
--
-- Meta's templates have independently-numbered {{n}} placeholders per
-- component (header's {{1}} and body's {{1}} are different slots) --
-- confirmed against ui/ui's own TemplatePreview.tsx, which already
-- substitutes per-component this same way. variable_mapping is therefore a
-- flat array of {component: 'header'|'body', index: int, type: 'fixed'|
-- 'field', value: text} -- value is a literal string for 'fixed', or a
-- contact field key ('display_name' or a contact custom field key) for
-- 'field'.
create table crm.campaigns (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  name text not null,
  -- organizations_addresses.address -- the one connected WhatsApp number
  -- this campaign sends through (service is always 'whatsapp' here, same
  -- reasoning crm.templates' own organization_address column gives).
  organization_address text not null,
  -- Identifies the crm.templates row by its own natural key, not a foreign
  -- key to its uuid id -- a template can be re-synced (new id) without
  -- orphaning a campaign that was built against its (name, language).
  template_name text not null,
  template_language text not null,
  segment_id uuid not null,
  variable_mapping jsonb default '[]'::jsonb not null,
  status text default 'draft'::text not null,
  -- UTC, converted server-side from the organization's own local wall-clock
  -- time (crm.schedule_campaign) -- CLAUDE.md: "store UTC; ... scheduling
  -- uses the tenant timezone." Null for a draft; set only by
  -- schedule_campaign/cleared only by unschedule_campaign, never a plain
  -- update, so "scheduled" always means "has a real scheduled_at."
  scheduled_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.campaigns add constraint campaigns_pkey primary key (id);

alter table only crm.campaigns
add constraint campaigns_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

-- No ON DELETE here, deliberately -- a segment still referenced by a
-- campaign should not vanish out from under it; crm.delete_segment simply
-- fails with a foreign_key_violation (23503) until the campaign is deleted
-- or repointed first.
alter table only crm.campaigns
add constraint campaigns_segment_id_fkey
foreign key (segment_id) references crm.segments(id);

alter table only crm.campaigns
add constraint campaigns_status_check
check (status in ('draft', 'scheduled'));

alter table only crm.campaigns
add constraint campaigns_name_check
check (length(trim(name)) > 0 and length(name) <= 100);

create index campaigns_organization_id_idx on crm.campaigns (organization_id);

create trigger set_updated_at
before update
on crm.campaigns
for each row
execute function public.moddatetime('updated_at');

-- Variable-mapping validation -------------------------------------------------------------

-- The highest {{n}} found in one component's text, or 0 if it has none/no
-- variables. Meta template placeholders are always positional integers
-- starting at 1 (confirmed against ui/ui's TemplateEditor.tsx, which
-- numbers them the same way when a template is authored).
create function crm._template_placeholder_count(p_text text) returns int
language sql
immutable
set search_path to ''
as $$
  select coalesce(max((m[1])::int), 0)
  from regexp_matches(coalesce(p_text, ''), '\{\{(\d+)\}\}', 'g') m;
$$;

-- Raises unless p_mapping covers EXACTLY the placeholders p_components'
-- own header/body text actually has -- no slot missing, none extra, no
-- duplicate, and every 'field' entry names a real field ('display_name' or
-- an existing contact custom field). Shared by create_campaign and
-- update_campaign (the second real caller, same "factor out before it
-- forks" practice as crm._send_internal_whatsapp_alert).
create function crm._validate_campaign_variable_mapping(
  p_organization_id uuid,
  p_components jsonb,
  p_mapping jsonb
) returns void
language plpgsql
stable
set search_path to ''
as $$
declare
  v_header_text text;
  v_body_text text;
  v_header_n int;
  v_body_n int;
  v_entry jsonb;
  v_component text;
  v_type text;
  v_field_key text;
begin
  select c->>'text' into v_header_text
  from jsonb_array_elements(p_components) c where c->>'type' = 'HEADER';
  select c->>'text' into v_body_text
  from jsonb_array_elements(p_components) c where c->>'type' = 'BODY';

  v_header_n := crm._template_placeholder_count(v_header_text);
  v_body_n := crm._template_placeholder_count(v_body_text);

  if (
    select coalesce(array_agg((e->>'index')::int order by (e->>'index')::int), '{}')
    from jsonb_array_elements(p_mapping) e where e->>'component' = 'header'
  ) <> (select coalesce(array_agg(g), '{}') from generate_series(1, v_header_n) g) then
    raise exception 'variable_mapping must cover exactly the header''s % placeholder(s), no more, no fewer', v_header_n
      using errcode = '22023';
  end if;

  if (
    select coalesce(array_agg((e->>'index')::int order by (e->>'index')::int), '{}')
    from jsonb_array_elements(p_mapping) e where e->>'component' = 'body'
  ) <> (select coalesce(array_agg(g), '{}') from generate_series(1, v_body_n) g) then
    raise exception 'variable_mapping must cover exactly the body''s % placeholder(s), no more, no fewer', v_body_n
      using errcode = '22023';
  end if;

  for v_entry in select * from jsonb_array_elements(p_mapping)
  loop
    v_component := v_entry->>'component';
    v_type := v_entry->>'type';

    if v_component not in ('header', 'body') then
      raise exception 'variable_mapping component must be header or body' using errcode = '22023';
    end if;
    if v_type not in ('fixed', 'field') then
      raise exception 'variable_mapping entry type must be fixed or field' using errcode = '22023';
    end if;

    if v_type = 'field' then
      v_field_key := v_entry->>'value';
      if v_field_key is distinct from 'display_name'
        and crm.custom_field_definition(p_organization_id, 'contact', v_field_key) is null then
        raise exception 'unknown contact field %', v_field_key using errcode = '22023';
      end if;
    end if;
  end loop;
end;
$$;

-- CRUD ---------------------------------------------------------------------------------------

create function crm.create_campaign(
  p_organization_id uuid,
  p_name text,
  p_organization_address text,
  p_template_name text,
  p_template_language text,
  p_segment_id uuid,
  p_variable_mapping jsonb default '[]'::jsonb
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
  v_components jsonb;
  v_segment_org uuid;
begin
  perform crm.require_permission(p_organization_id, 'broadcasts.create');

  select components into v_components
  from crm.templates
  where organization_id = p_organization_id
    and organization_address = p_organization_address
    and name = p_template_name
    and language = p_template_language;

  if v_components is null then
    raise exception 'template not found for this number' using errcode = 'P0002';
  end if;

  select organization_id into v_segment_org from crm.segments where id = p_segment_id;
  if v_segment_org is distinct from p_organization_id then
    raise exception 'segment not found' using errcode = 'P0002';
  end if;

  perform crm._validate_campaign_variable_mapping(p_organization_id, v_components, p_variable_mapping);

  insert into crm.campaigns (
    organization_id, name, organization_address, template_name, template_language,
    segment_id, variable_mapping
  )
  values (
    p_organization_id, trim(p_name), p_organization_address, p_template_name, p_template_language,
    p_segment_id, p_variable_mapping
  )
  returning id into v_id;

  perform crm.write_audit(
    p_organization_id, 'campaign.created', 'campaign', v_id::text,
    jsonb_build_object('name', trim(p_name), 'template_name', p_template_name)
  );

  return v_id;
end;
$$;

-- Name, segment and variable mapping only -- the template a campaign is
-- built against (and the number it sends through) never changes after
-- creation, same "pick it once" precedent CustomFieldForm's entity field
-- already established; swapping templates is a new campaign.
create function crm.update_campaign(
  p_campaign_id uuid,
  p_name text,
  p_segment_id uuid,
  p_variable_mapping jsonb
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_campaign crm.campaigns;
  v_components jsonb;
  v_segment_org uuid;
begin
  select * into v_campaign from crm.campaigns where id = p_campaign_id;
  if not found then
    raise exception 'campaign not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_campaign.organization_id, 'broadcasts.create');

  select organization_id into v_segment_org from crm.segments where id = p_segment_id;
  if v_segment_org is distinct from v_campaign.organization_id then
    raise exception 'segment not found' using errcode = 'P0002';
  end if;

  select components into v_components
  from crm.templates
  where organization_id = v_campaign.organization_id
    and organization_address = v_campaign.organization_address
    and name = v_campaign.template_name
    and language = v_campaign.template_language;

  perform crm._validate_campaign_variable_mapping(v_campaign.organization_id, v_components, p_variable_mapping);

  update crm.campaigns
  set name = trim(p_name), segment_id = p_segment_id, variable_mapping = p_variable_mapping
  where id = p_campaign_id;

  perform crm.write_audit(
    v_campaign.organization_id, 'campaign.updated', 'campaign', p_campaign_id::text,
    jsonb_build_object('name', trim(p_name))
  );
end;
$$;

create function crm.delete_campaign(p_campaign_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_organization_id uuid;
begin
  select organization_id into v_organization_id from crm.campaigns where id = p_campaign_id;
  if v_organization_id is null then
    raise exception 'campaign not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_organization_id, 'broadcasts.create');

  delete from crm.campaigns where id = p_campaign_id;

  perform crm.write_audit(
    v_organization_id, 'campaign.deleted', 'campaign', p_campaign_id::text, '{}'::jsonb
  );
end;
$$;

-- Scheduling, in the tenant's own timezone ---------------------------------------------------

-- p_local_date/p_local_time are wall-clock in the organization's own
-- timezone -- same `(date || time)::timestamp at time zone tz` conversion
-- crm.upcoming_trial_slots (P3-08) already uses, converted here instead of
-- client-side since the UI has no reliable way to know the tenant's own
-- timezone rules (DST etc.) the way Postgres's tz database does.
create function crm.schedule_campaign(
  p_campaign_id uuid,
  p_local_date date,
  p_local_time text
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_organization_id uuid;
  v_tz text;
  v_scheduled_at timestamp with time zone;
begin
  select organization_id into v_organization_id from crm.campaigns where id = p_campaign_id;
  if v_organization_id is null then
    raise exception 'campaign not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_organization_id, 'broadcasts.create');

  select coalesce(timezone, 'Asia/Kolkata') into v_tz
  from crm.organization_profiles where organization_id = v_organization_id;

  v_scheduled_at := (p_local_date::text || ' ' || p_local_time)::timestamp at time zone v_tz;

  if v_scheduled_at <= now() then
    raise exception 'scheduled time must be in the future' using errcode = '22023';
  end if;

  update crm.campaigns
  set status = 'scheduled', scheduled_at = v_scheduled_at
  where id = p_campaign_id;

  perform crm.write_audit(
    v_organization_id, 'campaign.scheduled', 'campaign', p_campaign_id::text,
    jsonb_build_object('scheduled_at', v_scheduled_at)
  );
end;
$$;

create function crm.unschedule_campaign(p_campaign_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_organization_id uuid;
begin
  select organization_id into v_organization_id from crm.campaigns where id = p_campaign_id;
  if v_organization_id is null then
    raise exception 'campaign not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_organization_id, 'broadcasts.create');

  update crm.campaigns
  set status = 'draft', scheduled_at = null
  where id = p_campaign_id;

  perform crm.write_audit(
    v_organization_id, 'campaign.unscheduled', 'campaign', p_campaign_id::text, '{}'::jsonb
  );
end;
$$;

-- Cost estimate -------------------------------------------------------------------------------

-- billing.costs (upstream OpenBSP's own rate table, seeded but unused by
-- any function anywhere until now -- same "reserved, never consumed"
-- pattern this project keeps finding in its own catalogs) keys WhatsApp
-- rows as (provider: 'whatsapp', product: '<category>/<country>'). Reads
-- the row with the latest effective_at that has already passed, same
-- "pick the current rate" semantics billing's own cost tables are seeded
-- to support (see e.g. the google gemini-3.8-flash two-tier seed). India
-- rows are seeded by this task's own migration (20261102.../crm_campaigns),
-- sourced from third-party research, not Meta's own authoritative rate
-- card file (unreachable at build time) -- flagged there, not assumed
-- exact.
create function crm.estimate_campaign_cost(p_campaign_id uuid)
returns table (
  audience_count bigint,
  opted_in_count bigint,
  rate numeric,
  currency text,
  estimated_total numeric
)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_campaign crm.campaigns;
  v_category text;
  v_rate numeric;
begin
  select * into v_campaign from crm.campaigns where id = p_campaign_id;
  if not found then
    raise exception 'campaign not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_campaign.organization_id, 'broadcasts.create');

  select lower(t.category) into v_category
  from crm.templates t
  where t.organization_id = v_campaign.organization_id
    and t.organization_address = v_campaign.organization_address
    and t.name = v_campaign.template_name
    and t.language = v_campaign.template_language;

  if v_category is not null then
    select (c.pricing->>'price')::numeric into v_rate
    from billing.costs c
    where c.provider = 'whatsapp'
      and c.product = v_category || '/in'
      and c.effective_at <= now()
    order by c.effective_at desc
    limit 1;
  end if;

  return query
  select
    p.total_count,
    p.opted_in_count,
    v_rate,
    'INR'::text,
    case when v_rate is null then null else round(p.opted_in_count * v_rate, 4) end
  from crm.preview_segment_count(
    v_campaign.organization_id,
    (select criteria from crm.segments where id = v_campaign.segment_id)
  ) p;
end;
$$;

-- Test send -----------------------------------------------------------------------------------

-- Builds one component's `parameters` array for the real Meta template
-- send shape -- {type: 'text', text: <value>} per slot, 1..p_count. A
-- 'fixed' mapping entry uses its own literal value; a 'field' entry falls
-- back to the template's own Meta-approved example text, since a test send
-- has no real recipient to pull a contact field from (that only happens
-- once P4-06 fans out to a segment's real members). A slot with no mapping
-- entry (should not happen -- validated at save time) renders as empty
-- rather than failing the whole test send.
create function crm._render_campaign_component_params(
  p_variable_mapping jsonb,
  p_component text,
  p_count int,
  p_example_values text[]
) returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare
  v_params jsonb := '[]'::jsonb;
  v_i int;
  v_entry jsonb;
  v_value text;
begin
  for v_i in 1..p_count loop
    select e into v_entry from jsonb_array_elements(p_variable_mapping) e
    where e->>'component' = p_component and (e->>'index')::int = v_i;

    if v_entry is null then
      v_value := '';
    elsif v_entry->>'type' = 'fixed' then
      v_value := v_entry->>'value';
    else
      v_value := coalesce(p_example_values[v_i], '');
    end if;

    v_params := v_params || jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_value));
  end loop;

  return v_params;
end;
$$;

-- Sends ONE real WhatsApp template message to the calling member's own
-- connected number (crm.member_roles.whatsapp_address), through the exact
-- same public.messages insert _shared/whatsapp_webhook_processing.ts's
-- STOP/START confirmations and crm._send_internal_whatsapp_alert already
-- use -- so the DB webhook that fires whatsapp-dispatcher picks it up and
-- checkSendPolicy runs on it like any other send. Deliberately NOT
-- exempted from the marketing opt-in gate: if the caller's own number has
-- no recorded opt-in and the template is MARKETING, this fails exactly the
-- way a real recipient without opt-in would -- that is the whole point of
-- a compliance preview, not a bug to work around.
create function crm.send_test_campaign_message(p_campaign_id uuid) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_campaign crm.campaigns;
  v_components jsonb;
  v_user_id uuid := auth.uid();
  v_agent_id uuid;
  v_whatsapp_address text;
  v_header_text text;
  v_body_text text;
  v_header_n int;
  v_body_n int;
  v_examples_header text[];
  v_examples_body text[];
  v_message_components jsonb := '[]'::jsonb;
  v_conversation_id uuid;
  v_message_id uuid;
begin
  select * into v_campaign from crm.campaigns where id = p_campaign_id;
  if not found then
    raise exception 'campaign not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_campaign.organization_id, 'broadcasts.create');

  if v_user_id is null then
    raise exception 'a signed-in member is required to send a test' using errcode = '42501';
  end if;

  select a.id into v_agent_id from public.agents a
  where a.organization_id = v_campaign.organization_id and a.user_id = v_user_id;

  select mr.whatsapp_address into v_whatsapp_address
  from crm.member_roles mr where mr.agent_id = v_agent_id;

  if v_whatsapp_address is null then
    raise exception 'set your own WhatsApp number first, under Settings > Members' using errcode = 'P0001';
  end if;

  select components into v_components
  from crm.templates
  where organization_id = v_campaign.organization_id
    and organization_address = v_campaign.organization_address
    and name = v_campaign.template_name
    and language = v_campaign.template_language;

  if v_components is null then
    raise exception 'template not found for this number' using errcode = 'P0002';
  end if;

  select c->>'text' into v_header_text from jsonb_array_elements(v_components) c where c->>'type' = 'HEADER';
  select c->>'text' into v_body_text from jsonb_array_elements(v_components) c where c->>'type' = 'BODY';
  v_header_n := crm._template_placeholder_count(v_header_text);
  v_body_n := crm._template_placeholder_count(v_body_text);

  select array(select jsonb_array_elements_text(c->'example'->'header_text'))
  into v_examples_header
  from jsonb_array_elements(v_components) c where c->>'type' = 'HEADER';

  select array(select jsonb_array_elements_text(c->'example'->'body_text'->0))
  into v_examples_body
  from jsonb_array_elements(v_components) c where c->>'type' = 'BODY';

  if v_header_n > 0 then
    v_message_components := v_message_components || jsonb_build_array(
      jsonb_build_object(
        'type', 'header',
        'parameters', crm._render_campaign_component_params(
          v_campaign.variable_mapping, 'header', v_header_n, v_examples_header
        )
      )
    );
  end if;

  if v_body_n > 0 then
    v_message_components := v_message_components || jsonb_build_array(
      jsonb_build_object(
        'type', 'body',
        'parameters', crm._render_campaign_component_params(
          v_campaign.variable_mapping, 'body', v_body_n, v_examples_body
        )
      )
    );
  end if;

  insert into public.conversations (organization_id, service, organization_address, address)
  values (v_campaign.organization_id, 'whatsapp', v_campaign.organization_address, v_whatsapp_address)
  on conflict (organization_id, organization_address, service, address) do nothing;

  select c.id into v_conversation_id from public.conversations c
  where c.organization_id = v_campaign.organization_id
    and c.organization_address = v_campaign.organization_address
    and c.service = 'whatsapp' and c.address = v_whatsapp_address;

  insert into public.messages (
    organization_id, conversation_id, service, organization_address, conversation_address, content
  )
  values (
    v_campaign.organization_id, v_conversation_id, 'whatsapp', v_campaign.organization_address, v_whatsapp_address,
    jsonb_build_object(
      'version', '1', 'type', 'data', 'kind', 'template',
      'data', jsonb_build_object(
        'name', v_campaign.template_name,
        'language', jsonb_build_object('code', v_campaign.template_language, 'policy', 'deterministic'),
        'components', v_message_components
      )
    )
  )
  returning id into v_message_id;

  perform crm.write_audit(
    v_campaign.organization_id, 'campaign.test_sent', 'campaign', p_campaign_id::text,
    jsonb_build_object('message_id', v_message_id)
  );

  return v_message_id;
end;
$$;
