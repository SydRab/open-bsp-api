
  create table "crm"."campaigns" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "name" text not null,
    "organization_address" text not null,
    "template_name" text not null,
    "template_language" text not null,
    "segment_id" uuid not null,
    "variable_mapping" jsonb not null default '[]'::jsonb,
    "status" text not null default 'draft'::text,
    "scheduled_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."campaigns" enable row level security;

CREATE INDEX campaigns_organization_id_idx ON crm.campaigns USING btree (organization_id);

CREATE UNIQUE INDEX campaigns_pkey ON crm.campaigns USING btree (id);

alter table "crm"."campaigns" add constraint "campaigns_pkey" PRIMARY KEY using index "campaigns_pkey";

alter table "crm"."campaigns" add constraint "campaigns_name_check" CHECK (((length(TRIM(BOTH FROM name)) > 0) AND (length(name) <= 100))) not valid;

alter table "crm"."campaigns" validate constraint "campaigns_name_check";

alter table "crm"."campaigns" add constraint "campaigns_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."campaigns" validate constraint "campaigns_organization_id_fkey";

alter table "crm"."campaigns" add constraint "campaigns_segment_id_fkey" FOREIGN KEY (segment_id) REFERENCES crm.segments(id) not valid;

alter table "crm"."campaigns" validate constraint "campaigns_segment_id_fkey";

alter table "crm"."campaigns" add constraint "campaigns_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'scheduled'::text]))) not valid;

alter table "crm"."campaigns" validate constraint "campaigns_status_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._render_campaign_component_params(p_variable_mapping jsonb, p_component text, p_count integer, p_example_values text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm._template_placeholder_count(p_text text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select coalesce(max((m[1])::int), 0)
  from regexp_matches(coalesce(p_text, ''), '\{\{(\d+)\}\}', 'g') m;
$function$
;

CREATE OR REPLACE FUNCTION crm._validate_campaign_variable_mapping(p_organization_id uuid, p_components jsonb, p_mapping jsonb)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.create_campaign(p_organization_id uuid, p_name text, p_organization_address text, p_template_name text, p_template_language text, p_segment_id uuid, p_variable_mapping jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.delete_campaign(p_campaign_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.estimate_campaign_cost(p_campaign_id uuid)
 RETURNS TABLE(audience_count bigint, opted_in_count bigint, rate numeric, currency text, estimated_total numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.schedule_campaign(p_campaign_id uuid, p_local_date date, p_local_time text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.send_test_campaign_message(p_campaign_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.unschedule_campaign(p_campaign_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.update_campaign(p_campaign_id uuid, p_name text, p_segment_id uuid, p_variable_mapping jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

grant select on table "crm"."campaigns" to "anon";

grant select on table "crm"."campaigns" to "authenticated";

grant delete on table "crm"."campaigns" to "service_role";

grant insert on table "crm"."campaigns" to "service_role";

grant references on table "crm"."campaigns" to "service_role";

grant select on table "crm"."campaigns" to "service_role";

grant trigger on table "crm"."campaigns" to "service_role";

grant truncate on table "crm"."campaigns" to "service_role";

grant update on table "crm"."campaigns" to "service_role";


  create policy "members can read their orgs campaigns"
  on "crm"."campaigns"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.campaigns FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

-- db diff doesn't derive privilege changes for a brand-new function --
-- same known gap as every prior migration this session that added one
-- (most recently crm.segments' own migration, P4-03). The three internal
-- helpers below are never called directly over RPC (only from within the
-- security definer functions that follow), so service_role only, same
-- precedent as crm._filter_contact_rows/_send_internal_whatsapp_alert.
revoke execute on function crm._template_placeholder_count(text) from public;
grant execute on function crm._template_placeholder_count(text) to service_role;

revoke execute on function crm._validate_campaign_variable_mapping(uuid, jsonb, jsonb) from public;
grant execute on function crm._validate_campaign_variable_mapping(uuid, jsonb, jsonb) to service_role;

revoke execute on function crm._render_campaign_component_params(jsonb, text, int, text[]) from public;
grant execute on function crm._render_campaign_component_params(jsonb, text, int, text[]) to service_role;

revoke execute on function crm.create_campaign(uuid, text, text, text, text, uuid, jsonb) from public;
grant execute on function crm.create_campaign(uuid, text, text, text, text, uuid, jsonb) to authenticated;

revoke execute on function crm.update_campaign(uuid, text, uuid, jsonb) from public;
grant execute on function crm.update_campaign(uuid, text, uuid, jsonb) to authenticated;

revoke execute on function crm.delete_campaign(uuid) from public;
grant execute on function crm.delete_campaign(uuid) to authenticated;

revoke execute on function crm.schedule_campaign(uuid, date, text) from public;
grant execute on function crm.schedule_campaign(uuid, date, text) to authenticated;

revoke execute on function crm.unschedule_campaign(uuid) from public;
grant execute on function crm.unschedule_campaign(uuid) to authenticated;

revoke execute on function crm.estimate_campaign_cost(uuid) from public;
grant execute on function crm.estimate_campaign_cost(uuid) to authenticated;

revoke execute on function crm.send_test_campaign_message(uuid) from public;
grant execute on function crm.send_test_campaign_message(uuid) to authenticated;


