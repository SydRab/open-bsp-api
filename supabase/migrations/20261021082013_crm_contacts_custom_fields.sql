drop policy "managers can edit their orgs pack items" on "crm"."organization_pack_items";


  create table "crm"."contact_addresses" (
    "organization_id" uuid not null,
    "service" public.service not null,
    "address" text not null,
    "contact_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."contact_addresses" enable row level security;


  create table "crm"."contacts" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "display_name" text,
    "locale" text,
    "custom_fields" jsonb not null default '{}'::jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."contacts" enable row level security;

CREATE INDEX contact_addresses_contact_id_idx ON crm.contact_addresses USING btree (contact_id);

CREATE UNIQUE INDEX contact_addresses_pkey ON crm.contact_addresses USING btree (organization_id, service, address);

CREATE INDEX contacts_custom_fields_idx ON crm.contacts USING gin (custom_fields jsonb_path_ops);

CREATE UNIQUE INDEX contacts_organization_id_id_key ON crm.contacts USING btree (organization_id, id);

CREATE INDEX contacts_organization_id_idx ON crm.contacts USING btree (organization_id);

CREATE UNIQUE INDEX contacts_pkey ON crm.contacts USING btree (id);

alter table "crm"."contact_addresses" add constraint "contact_addresses_pkey" PRIMARY KEY using index "contact_addresses_pkey";

alter table "crm"."contacts" add constraint "contacts_pkey" PRIMARY KEY using index "contacts_pkey";

alter table "crm"."contact_addresses" add constraint "contact_addresses_contact_fkey" FOREIGN KEY (organization_id, contact_id) REFERENCES crm.contacts(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."contact_addresses" validate constraint "contact_addresses_contact_fkey";

alter table "crm"."contacts" add constraint "contacts_custom_fields_check" CHECK ((jsonb_typeof(custom_fields) = 'object'::text)) not valid;

alter table "crm"."contacts" validate constraint "contacts_custom_fields_check";

alter table "crm"."contacts" add constraint "contacts_locale_check" CHECK (((locale IS NULL) OR (locale = ANY (ARRAY['en'::text, 'hi'::text])))) not valid;

alter table "crm"."contacts" validate constraint "contacts_locale_check";

alter table "crm"."contacts" add constraint "contacts_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."contacts" validate constraint "contacts_organization_id_fkey";

alter table "crm"."contacts" add constraint "contacts_organization_id_id_key" UNIQUE using index "contacts_organization_id_id_key";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.after_insert_on_contacts_addresses()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_contact uuid;
begin
  if new.service = 'local' or exists (
    select 1 from crm.contact_addresses ca
    where ca.organization_id = new.organization_id
      and ca.service = new.service
      and ca.address = new.address
  ) then
    return null;
  end if;

  insert into crm.contacts (organization_id, display_name)
  values (
    new.organization_id,
    nullif(trim(coalesce(new.extra->>'name', new.extra->'synced'->>'name')), '')
  )
  returning id into v_contact;

  insert into crm.contact_addresses (organization_id, service, address, contact_id)
  values (new.organization_id, new.service, new.address, v_contact)
  on conflict do nothing;

  -- Lost a race with a concurrent insert of the same address: drop ours.
  if not found then
    delete from crm.contacts where id = v_contact;
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.archive_custom_field(p_field_id uuid, p_archived boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_item crm.organization_pack_items;
begin
  select * into v_item from crm.organization_pack_items i
  where i.id = p_field_id and i.kind = 'custom_field';
  if not found then
    raise exception 'field not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_item.organization_id, 'organization.manage');

  if coalesce((v_item.value->>'archived')::boolean, false) = p_archived then
    return;
  end if;

  update crm.organization_pack_items
  set value = case when p_archived
    then value || '{"archived": true}'::jsonb
    else value - 'archived' end
  where id = p_field_id;
  -- Audited by the pack item trigger (custom_field.archived / restored).
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.before_write_on_contacts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_key text;
  v_value jsonb;
  v_old jsonb;
  v_def jsonb;
  v_error text;
begin
  new.custom_fields := crm.clean_custom_fields(new.custom_fields);

  for v_key, v_value in select * from jsonb_each(new.custom_fields) loop
    v_old := case when tg_op = 'UPDATE' then old.custom_fields->v_key end;
    if v_old is not null and v_old = v_value then
      continue;
    end if;

    v_def := crm.custom_field_definition(new.organization_id, 'contact', v_key);
    if v_def is null then
      raise exception 'unknown field %', v_key using errcode = '22023';
    end if;
    if coalesce((v_def->>'archived')::boolean, false) then
      raise exception 'field % is archived', v_key using errcode = '22023';
    end if;

    v_error := crm.custom_field_value_error(v_def, v_value, v_old);
    if v_error is not null then
      raise exception '%', v_error using errcode = '22023';
    end if;
  end loop;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.clean_custom_fields(p_values jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)
  from jsonb_each(coalesce(p_values, '{}'::jsonb)) as e(k, v)
  where v not in ('null'::jsonb, '""'::jsonb, '[]'::jsonb);
$function$
;

CREATE OR REPLACE FUNCTION crm.create_custom_field(p_organization_id uuid, p_entity text, p_key text, p_type text, p_label jsonb, p_options jsonb DEFAULT '[]'::jsonb, p_required boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_def jsonb := jsonb_build_object(
    'key', p_key, 'entity', p_entity, 'type', p_type, 'label', p_label,
    'required', coalesce(p_required, false)
  );
  v_error text;
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  if jsonb_array_length(coalesce(p_options, '[]')) > 0 then
    v_def := v_def || jsonb_build_object('options', p_options);
  end if;
  v_error := crm.field_definition_error(v_def);
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023';
  end if;

  if exists (
    select 1 from crm.organization_pack_items i
    where i.organization_id = p_organization_id
      and i.kind = 'custom_field'
      and i.item_key = p_key
  ) then
    raise exception 'a field with the key % already exists', p_key
      using errcode = '23505';
  end if;

  insert into crm.organization_pack_items (
    organization_id, kind, item_key, value, pack_value, pack_version, sort_order
  ) values (
    p_organization_id, 'custom_field', p_key, v_def, null,
    coalesce((select op.version from crm.organization_packs op
              where op.organization_id = p_organization_id), 0),
    coalesce((select max(i.sort_order) + 1 from crm.organization_pack_items i
              where i.organization_id = p_organization_id
                and i.kind = 'custom_field'), 1)
  )
  returning id into v_id;

  perform crm.write_audit(
    p_organization_id, 'custom_field.created', 'custom_field', p_key,
    jsonb_build_object('entity', p_entity, 'type', p_type, 'label', p_label->>'en')
  );

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.custom_field_definition(p_organization_id uuid, p_entity text, p_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select i.value
  from crm.organization_pack_items i
  where i.organization_id = p_organization_id
    and i.kind = 'custom_field'
    and i.item_key = p_key
    and i.value->>'entity' = p_entity;
$function$
;

CREATE OR REPLACE FUNCTION crm.custom_field_matches(p_values jsonb, p_condition jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v jsonb := p_values->(p_condition->>'field');
  c jsonb := p_condition->'value';
  v_op text := p_condition->>'op';
begin
  if v_op = 'is_empty' then
    return v is null;
  elsif v_op = 'is_not_empty' then
    return v is not null;
  elsif v is null then
    return v_op = 'neq';
  end if;

  case v_op
    when 'eq' then return v = c;
    when 'neq' then return v <> c;
    when 'in' then
      return case when jsonb_typeof(v) = 'array'
        then exists (select 1 from jsonb_array_elements(v) e where c @> jsonb_build_array(e))
        else c @> jsonb_build_array(v) end;
    when 'contains' then
      return case when jsonb_typeof(v) = 'array'
        then v @> jsonb_build_array(c)
        else strpos(lower(jsonb_build_array(v)->>0), lower(jsonb_build_array(c)->>0)) > 0 end;
    when 'gt', 'gte', 'lt', 'lte' then
      if jsonb_typeof(v) = 'number' and jsonb_typeof(c) = 'number' then
        return case v_op
          when 'gt' then (jsonb_build_array(v)->>0)::numeric > (jsonb_build_array(c)->>0)::numeric
          when 'gte' then (jsonb_build_array(v)->>0)::numeric >= (jsonb_build_array(c)->>0)::numeric
          when 'lt' then (jsonb_build_array(v)->>0)::numeric < (jsonb_build_array(c)->>0)::numeric
          else (jsonb_build_array(v)->>0)::numeric <= (jsonb_build_array(c)->>0)::numeric end;
      end if;
      return case v_op
        when 'gt' then (jsonb_build_array(v)->>0) > (jsonb_build_array(c)->>0)
        when 'gte' then (jsonb_build_array(v)->>0) >= (jsonb_build_array(c)->>0)
        when 'lt' then (jsonb_build_array(v)->>0) < (jsonb_build_array(c)->>0)
        else (jsonb_build_array(v)->>0) <= (jsonb_build_array(c)->>0) end;
    else
      raise exception 'unknown filter operator %', v_op using errcode = '22023';
  end case;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.custom_field_value_error(p_def jsonb, p_value jsonb, p_old jsonb DEFAULT NULL::jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_key text := p_def->>'key';
  v_kind text := jsonb_typeof(p_value);
  v_text text := jsonb_build_array(p_value)->>0;
  v_max int;
  v_choice text;
  v_active text[] := array(
    select o->>'value' from jsonb_array_elements(coalesce(p_def->'options', '[]')) o
    where not coalesce((o->>'archived')::boolean, false)
  );
  v_all text[] := array(
    select o->>'value' from jsonb_array_elements(coalesce(p_def->'options', '[]')) o
  );
begin
  case p_def->>'type'
    when 'text', 'long_text' then
      if v_kind <> 'string' then
        return format('%s must be text', v_key);
      end if;
      v_max := 500;
      if p_def->>'type' = 'long_text' then
        v_max := 5000;
      end if;
      if length(v_text) > v_max then
        return format('%s is too long', v_key);
      end if;
    when 'number' then
      if v_kind <> 'number' then
        return format('%s must be a number', v_key);
      end if;
    when 'boolean' then
      if v_kind <> 'boolean' then
        return format('%s must be yes or no', v_key);
      end if;
    when 'date' then
      if v_kind <> 'string' or v_text !~ '^\d{4}-\d{2}-\d{2}$' then
        return format('%s must be a date (YYYY-MM-DD)', v_key);
      end if;
      begin
        perform v_text::date;
      exception when others then
        return format('%s must be a date (YYYY-MM-DD)', v_key);
      end;
    when 'email' then
      if v_kind <> 'string' or v_text !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        return format('%s must be an email address', v_key);
      end if;
    when 'phone' then
      if v_kind <> 'string' or v_text !~ '^\+?[0-9][0-9 ()-]{6,19}$' then
        return format('%s must be a phone number', v_key);
      end if;
    when 'url' then
      if v_kind <> 'string' or v_text !~ '^https?://\S{3,500}$' then
        return format('%s must be a web address starting with http:// or https://', v_key);
      end if;
    when 'select' then
      if v_kind <> 'string' or not v_text = any(v_all) then
        return format('%s: unknown option %s', v_key, coalesce(v_text, ''));
      end if;
      if not v_text = any(v_active) and p_old is distinct from p_value then
        return format('%s: option %s is archived', v_key, v_text);
      end if;
    when 'multi_select' then
      if v_kind <> 'array' then
        return format('%s must be a list of options', v_key);
      end if;
      if jsonb_array_length(p_value) > (
        select count(distinct e) from jsonb_array_elements_text(p_value) e
      ) then
        return format('%s lists an option twice', v_key);
      end if;
      for v_choice in select * from jsonb_array_elements_text(p_value) loop
        if not v_choice = any(v_all) then
          return format('%s: unknown option %s', v_key, v_choice);
        end if;
        if not v_choice = any(v_active)
          and not coalesce(p_old @> to_jsonb(array[v_choice]), false) then
          return format('%s: option %s is archived', v_key, v_choice);
        end if;
      end loop;
    else
      return format('%s has an unknown type', v_key);
  end case;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.field_definition_error(p_def jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_label jsonb := '{"type": "object", "required": ["en"], "additionalProperties": false,
    "properties": {"en": {"type": "string", "minLength": 1, "maxLength": 80},
                   "hi": {"type": "string", "minLength": 1, "maxLength": 80}}}';
  v_error text;
  v_type text := p_def->>'type';
  v_options int := jsonb_array_length(coalesce(p_def->'options', '[]'));
begin
  v_error := crm.validate_setting_value(
    jsonb_build_object(
      'type', 'object',
      'required', jsonb_build_array('key', 'entity', 'type', 'label'),
      'additionalProperties', false,
      'properties', jsonb_build_object(
        'key', jsonb_build_object('type', 'string', 'pattern', '^[a-z][a-z0-9_]{1,39}$'),
        'entity', jsonb_build_object('type', 'string', 'enum', jsonb_build_array('contact', 'deal')),
        'type', jsonb_build_object('type', 'string', 'enum', jsonb_build_array(
          'text', 'long_text', 'number', 'date', 'boolean', 'select',
          'multi_select', 'email', 'phone', 'url')),
        'label', v_label,
        'required', jsonb_build_object('type', 'boolean'),
        'archived', jsonb_build_object('type', 'boolean'),
        'options', jsonb_build_object(
          'type', 'array', 'maxItems', 100,
          'items', jsonb_build_object(
            'type', 'object',
            'required', jsonb_build_array('value', 'label'),
            'additionalProperties', false,
            'properties', jsonb_build_object(
              'value', jsonb_build_object('type', 'string', 'pattern', '^[a-z0-9][a-z0-9_]{0,39}$'),
              'label', v_label,
              'archived', jsonb_build_object('type', 'boolean')))))),
    p_def,
    'field'
  );
  if v_error is not null then
    return v_error;
  end if;

  if v_type in ('select', 'multi_select') and v_options = 0 then
    return 'a choice field needs at least one option';
  end if;
  if v_type not in ('select', 'multi_select') and v_options > 0 then
    return 'only choice fields have options';
  end if;
  if v_options > (
    select count(distinct o->>'value') from jsonb_array_elements(p_def->'options') o
  ) then
    return 'option values must be unique';
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.filter_contacts(p_organization_id uuid, p_conditions jsonb DEFAULT '[]'::jsonb, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS SETOF crm.contacts
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_condition jsonb;
  v_equal jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(p_conditions) is distinct from 'array' then
    raise exception 'conditions must be a list' using errcode = '22023';
  end if;

  for v_condition in select * from jsonb_array_elements(p_conditions) loop
    if not exists (
      select 1 from crm.organization_pack_items i
      where i.organization_id = p_organization_id
        and i.kind = 'custom_field'
        and i.item_key = v_condition->>'field'
        and i.value->>'entity' = 'contact'
    ) then
      raise exception 'unknown field %', v_condition->>'field' using errcode = '22023';
    end if;
    if (v_condition->>'op') not in (
      'eq', 'neq', 'in', 'contains', 'gt', 'gte', 'lt', 'lte', 'is_empty', 'is_not_empty'
    ) then
      raise exception 'unknown filter operator %', v_condition->>'op' using errcode = '22023';
    end if;
    if v_condition->>'op' = 'eq' then
      v_equal := v_equal || jsonb_build_object(v_condition->>'field', v_condition->'value');
    end if;
  end loop;

  return query
  select c.*
  from crm.contacts c
  where c.organization_id = p_organization_id
    -- Equality conditions use the GIN index.
    and c.custom_fields @> v_equal
    and not exists (
      select 1 from jsonb_array_elements(p_conditions) cond
      where not crm.custom_field_matches(c.custom_fields, cond)
    )
  order by c.created_at desc, c.id
  limit least(greatest(coalesce(p_limit, 100), 1), 1000)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.format_custom_field(p_organization_id uuid, p_entity text, p_key text, p_value jsonb, p_locale text DEFAULT 'en'::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_def jsonb;
  v_locale text := coalesce(nullif(p_locale, ''), 'en');
begin
  if p_value is null or p_value = 'null'::jsonb then
    return '';
  end if;

  select i.value into v_def
  from crm.organization_pack_items i
  where i.organization_id = p_organization_id
    and i.kind = 'custom_field'
    and i.item_key = p_key
    and i.value->>'entity' = p_entity;

  case v_def->>'type'
    when 'select', 'multi_select' then
      return (
        select string_agg(
          coalesce(o->'label'->>v_locale, o->'label'->>'en', chosen),
          ', ' order by ord
        )
        from jsonb_array_elements_text(
          case when jsonb_typeof(p_value) = 'array' then p_value else jsonb_build_array(p_value) end
        ) with ordinality as x(chosen, ord)
        left join lateral (
          select o from jsonb_array_elements(v_def->'options') o
          where o->>'value' = chosen
        ) opt on true
      );
    when 'boolean' then
      return case
        when v_locale = 'hi' then case when p_value = 'true'::jsonb then 'हाँ' else 'नहीं' end
        else case when p_value = 'true'::jsonb then 'Yes' else 'No' end
      end;
    else
      return jsonb_build_array(p_value)->>0;
  end case;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_contact_fields(p_contact_id uuid, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_contact crm.contacts;
  v_merged jsonb;
  v_missing text;
begin
  select * into v_contact from crm.contacts c where c.id = p_contact_id;
  if not found then
    raise exception 'contact not found' using errcode = 'P0002';
  end if;
  if not crm.has_permission(v_contact.organization_id, 'contacts.edit') then
    raise exception 'permission contacts.edit required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_values) is distinct from 'object' then
    raise exception 'values must be an object' using errcode = '22023';
  end if;

  v_merged := crm.clean_custom_fields(v_contact.custom_fields || p_values);

  select string_agg(d.value->'label'->>'en', ', ' order by d.sort_order)
  into v_missing
  from crm.organization_pack_items d
  where d.organization_id = v_contact.organization_id
    and d.kind = 'custom_field'
    and d.value->>'entity' = 'contact'
    and coalesce((d.value->>'required')::boolean, false)
    and not coalesce((d.value->>'archived')::boolean, false)
    and not v_merged ? d.item_key;
  if v_missing is not null then
    raise exception 'required: %', v_missing using errcode = '22023';
  end if;

  update crm.contacts set custom_fields = v_merged
  where id = p_contact_id
  returning * into v_contact;
  if not found then
    raise exception 'contact not found' using errcode = 'P0002';
  end if;

  return v_contact.custom_fields;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.update_custom_field(p_field_id uuid, p_label jsonb, p_options jsonb, p_required boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_item crm.organization_pack_items;
  v_def jsonb;
  v_error text;
begin
  select * into v_item from crm.organization_pack_items i
  where i.id = p_field_id and i.kind = 'custom_field';
  if not found then
    raise exception 'field not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_item.organization_id, 'organization.manage');

  if exists (
    select 1 from jsonb_array_elements(coalesce(v_item.value->'options', '[]')) old_o
    where not exists (
      select 1 from jsonb_array_elements(coalesce(p_options, '[]')) new_o
      where new_o->>'value' = old_o->>'value'
    )
  ) then
    raise exception 'options cannot be removed; archive them instead'
      using errcode = '22023';
  end if;

  v_def := v_item.value - 'options'
    || jsonb_build_object('label', p_label, 'required', coalesce(p_required, false));
  if jsonb_array_length(coalesce(p_options, '[]')) > 0 then
    v_def := v_def || jsonb_build_object('options', p_options);
  end if;
  v_error := crm.field_definition_error(v_def);
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023';
  end if;

  -- Audited by the pack item trigger (custom_field.updated).
  if v_def is distinct from v_item.value then
    update crm.organization_pack_items set value = v_def where id = p_field_id;
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_organization_pack_items()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.value is not distinct from old.value
    or new.pack_value is distinct from old.pack_value then
    return null;
  end if;

  -- Custom fields (P1-06) have their own actions: edited, archived, restored.
  if new.kind = 'custom_field' then
    perform crm.write_audit(
      new.organization_id,
      case
        when coalesce((new.value->>'archived')::boolean, false)
          and not coalesce((old.value->>'archived')::boolean, false)
          then 'custom_field.archived'
        when coalesce((old.value->>'archived')::boolean, false)
          and not coalesce((new.value->>'archived')::boolean, false)
          then 'custom_field.restored'
        else 'custom_field.updated'
      end,
      'custom_field',
      new.item_key,
      jsonb_build_object('before', old.value, 'after', new.value)
    );
    return null;
  end if;

  perform crm.write_audit(
    new.organization_id,
    case
      when new.value is not distinct from new.pack_value then 'pack.item_reset'
      else 'pack.item_updated'
    end,
    'pack_item',
    new.id::text,
    jsonb_build_object(
      'kind', new.kind,
      'key', new.item_key,
      'before', old.value,
      'after', new.value
    )
  );

  return null;
end;
$function$
;

grant select on table "crm"."contact_addresses" to "anon";

grant select on table "crm"."contact_addresses" to "authenticated";

grant delete on table "crm"."contact_addresses" to "service_role";

grant insert on table "crm"."contact_addresses" to "service_role";

grant references on table "crm"."contact_addresses" to "service_role";

grant select on table "crm"."contact_addresses" to "service_role";

grant trigger on table "crm"."contact_addresses" to "service_role";

grant truncate on table "crm"."contact_addresses" to "service_role";

grant update on table "crm"."contact_addresses" to "service_role";

grant select on table "crm"."contacts" to "anon";

grant select on table "crm"."contacts" to "authenticated";

grant delete on table "crm"."contacts" to "service_role";

grant insert on table "crm"."contacts" to "service_role";

grant references on table "crm"."contacts" to "service_role";

grant select on table "crm"."contacts" to "service_role";

grant trigger on table "crm"."contacts" to "service_role";

grant truncate on table "crm"."contacts" to "service_role";

grant update on table "crm"."contacts" to "service_role";


  create policy "members can read the addresses of contacts they can see"
  on "crm"."contact_addresses"
  as permissive
  for select
  to authenticated, anon
using (((organization_id IN ( SELECT crm.get_permitted_orgs('contacts.view'::text) AS get_permitted_orgs)) AND (EXISTS ( SELECT 1
   FROM public.contacts_addresses c
  WHERE ((c.organization_id = contact_addresses.organization_id) AND (c.service = contact_addresses.service) AND (c.address = contact_addresses.address))))));



  create policy "editors can update contacts they can see"
  on "crm"."contacts"
  as permissive
  for update
  to authenticated
using (((organization_id IN ( SELECT crm.get_permitted_orgs('contacts.edit'::text) AS get_permitted_orgs)) AND (EXISTS ( SELECT 1
   FROM (crm.contact_addresses ca
     JOIN public.contacts_addresses c ON (((c.organization_id = ca.organization_id) AND (c.service = ca.service) AND (c.address = ca.address))))
  WHERE (ca.contact_id = contacts.id)))))
with check ((organization_id IN ( SELECT crm.get_permitted_orgs('contacts.edit'::text) AS get_permitted_orgs)));



  create policy "members can read contacts they can see"
  on "crm"."contacts"
  as permissive
  for select
  to authenticated, anon
using (((organization_id IN ( SELECT crm.get_permitted_orgs('contacts.view'::text) AS get_permitted_orgs)) AND (EXISTS ( SELECT 1
   FROM (crm.contact_addresses ca
     JOIN public.contacts_addresses c ON (((c.organization_id = ca.organization_id) AND (c.service = ca.service) AND (c.address = ca.address))))
  WHERE (ca.contact_id = contacts.id)))));



  create policy "managers can edit their orgs pack items"
  on "crm"."organization_pack_items"
  as permissive
  for update
  to authenticated
using (((organization_id IN ( SELECT crm.get_permitted_orgs('organization.manage'::text) AS get_permitted_orgs)) AND (kind <> ALL (ARRAY['compliance'::text, 'module'::text, 'custom_field'::text]))))
with check (((organization_id IN ( SELECT crm.get_permitted_orgs('organization.manage'::text) AS get_permitted_orgs)) AND (kind <> ALL (ARRAY['compliance'::text, 'module'::text, 'custom_field'::text]))));


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.contacts FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER validate_custom_fields BEFORE INSERT OR UPDATE OF custom_fields ON crm.contacts FOR EACH ROW EXECUTE FUNCTION crm.before_write_on_contacts();

CREATE TRIGGER crm_link_contact AFTER INSERT ON public.contacts_addresses FOR EACH ROW EXECUTE FUNCTION crm.after_insert_on_contacts_addresses();


