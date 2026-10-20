
  create table "crm"."disclaimer_versions" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "kind" text not null,
    "locale" text not null,
    "version" integer not null,
    "text" text not null,
    "created_by" uuid,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."disclaimer_versions" enable row level security;

alter table "crm"."organization_profiles" add column "address" jsonb;

alter table "crm"."organization_profiles" add column "legal_name" text;

alter table "crm"."organization_profiles" add column "registrations" jsonb not null default '[]'::jsonb;

alter table "crm"."organization_profiles" add column "support_email" text;

alter table "crm"."organization_profiles" add column "support_phone" text;

alter table "crm"."organization_profiles" add column "website" text;

CREATE UNIQUE INDEX disclaimer_versions_pkey ON crm.disclaimer_versions USING btree (id);

CREATE UNIQUE INDEX disclaimer_versions_version_key ON crm.disclaimer_versions USING btree (organization_id, kind, locale, version);

alter table "crm"."disclaimer_versions" add constraint "disclaimer_versions_pkey" PRIMARY KEY using index "disclaimer_versions_pkey";

alter table "crm"."disclaimer_versions" add constraint "disclaimer_versions_kind_check" CHECK ((kind = ANY (ARRAY['short'::text, 'full'::text]))) not valid;

alter table "crm"."disclaimer_versions" validate constraint "disclaimer_versions_kind_check";

alter table "crm"."disclaimer_versions" add constraint "disclaimer_versions_locale_check" CHECK ((locale = ANY (ARRAY['en'::text, 'hi'::text]))) not valid;

alter table "crm"."disclaimer_versions" validate constraint "disclaimer_versions_locale_check";

alter table "crm"."disclaimer_versions" add constraint "disclaimer_versions_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."disclaimer_versions" validate constraint "disclaimer_versions_organization_id_fkey";

alter table "crm"."disclaimer_versions" add constraint "disclaimer_versions_version_check" CHECK ((version > 0)) not valid;

alter table "crm"."disclaimer_versions" validate constraint "disclaimer_versions_version_check";

alter table "crm"."disclaimer_versions" add constraint "disclaimer_versions_version_key" UNIQUE using index "disclaimer_versions_version_key";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.audit_disclaimer_versions()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_before text;
begin
  select v.text into v_before
  from crm.disclaimer_versions v
  where v.organization_id = new.organization_id
    and v.kind = new.kind
    and v.locale = new.locale
    and v.version = new.version - 1;

  if v_before is null then
    select i.pack_value->>new.locale into v_before
    from crm.organization_pack_items i
    where i.organization_id = new.organization_id
      and i.kind = 'compliance'
      and i.item_key = 'disclaimer_' || new.kind;
  end if;

  perform crm.write_audit(
    new.organization_id, 'disclaimer.updated', 'disclaimer',
    new.kind || ':' || new.locale,
    jsonb_strip_nulls(jsonb_build_object(
      'kind', new.kind,
      'locale', new.locale,
      'version', new.version,
      'before', v_before,
      'after', new.text
    ))
  );

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.current_disclaimer(p_organization_id uuid, p_kind text, p_locale text)
 RETURNS TABLE(text text, version integer, source text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select * from (
    select v.text, v.version, 'tenant'::text
    from crm.disclaimer_versions v
    where v.organization_id = p_organization_id
      and v.kind = p_kind
      and v.locale = p_locale
    order by v.version desc
    limit 1
  ) tenant
  union all
  select * from (
    select i.pack_value->>p_locale, 0, 'pack'::text
    from crm.organization_pack_items i
    where i.organization_id = p_organization_id
      and i.kind = 'compliance'
      and i.item_key = 'disclaimer_' || p_kind
      and i.pack_value->>p_locale is not null
      and not exists (
        select 1 from crm.disclaimer_versions v
        where v.organization_id = p_organization_id
          and v.kind = p_kind
          and v.locale = p_locale
      )
  ) pack;
$function$
;

CREATE OR REPLACE FUNCTION crm.disclaimer_text_error(p_kind text, p_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case
    when p_text is null or length(trim(p_text)) = 0 then 'the disclaimer is empty'
    when p_text like '%{{%' then 'the disclaimer cannot contain placeholders like {{1}}'
    when p_kind = 'short' and length(trim(p_text)) > 60
      then format('the short disclaimer is %s characters; the maximum is 60', length(trim(p_text)))
    when p_kind = 'short' and length(trim(p_text)) < 10 then 'the short disclaimer must have at least 10 characters'
    when p_kind = 'short' and trim(p_text) ~ '[\r\n]' then 'the short disclaimer must be one line'
    when p_kind = 'full' and length(trim(p_text)) > 1000
      then format('the full disclaimer is %s characters; the maximum is 1000', length(trim(p_text)))
    when p_kind = 'full' and length(trim(p_text)) < 20 then 'the full disclaimer must have at least 20 characters'
    when p_kind not in ('short', 'full') then 'unknown disclaimer kind'
  end;
$function$
;

CREATE OR REPLACE FUNCTION crm.get_disclaimers(p_organization_id uuid)
 RETURNS TABLE(kind text, locale text, text text, version integer, source text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.assert_can_read_settings(p_organization_id);

  return query
  select k.kind, l.locale, d.text, d.version, d.source
  from (values ('short', 1), ('full', 2)) k(kind, ord)
  cross join (values ('en', 1), ('hi', 2)) l(locale, ord)
  left join lateral crm.current_disclaimer(p_organization_id, k.kind, l.locale) d on true
  order by k.ord, l.ord;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.render_with_disclaimer(p_organization_id uuid, p_content_type text, p_text text, p_locale text DEFAULT NULL::text)
 RETURNS TABLE(text text, attached boolean, disclaimer_kind text, disclaimer_locale text, disclaimer_version integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_kind text;
  v_attach boolean;
  v_locale text;
  v_disclaimer record;
  v_out text;
begin
  perform crm.assert_can_read_settings(p_organization_id);

  if p_text is null or length(trim(p_text)) = 0 then
    raise exception 'nothing to send' using errcode = '22023';
  end if;

  case
    when p_content_type in ('public_page', 'disclaimer_reply') then
      v_kind := 'full';
      v_attach := true;
    when p_content_type in ('broadcast', 'digest', 'ai_message', 'payment_confirmation', 'receipt') then
      v_kind := case when p_content_type = 'receipt' then 'full' else 'short' end;
      v_attach := coalesce((
        select (r.value->>p_content_type)::boolean
        from crm.resolve_setting(p_organization_id, 'disclaimer.attach_rules') r
      ), true);
    else
      raise exception 'unknown content type %', p_content_type using errcode = '22023';
  end case;

  if not v_attach then
    return query select p_text, false, null::text, null::text, null::int;
    return;
  end if;

  v_locale := coalesce(
    nullif(p_locale, ''),
    (select p.locale from crm.organization_profiles p where p.organization_id = p_organization_id),
    'en'
  );

  select * into v_disclaimer
  from crm.current_disclaimer(p_organization_id, v_kind, v_locale);
  if not found and v_locale <> 'en' then
    v_locale := 'en';
    select * into v_disclaimer
    from crm.current_disclaimer(p_organization_id, v_kind, v_locale);
  end if;
  if not found then
    -- Never send automatic content without the disclaimer it needs.
    raise exception 'the organization has no % disclaimer', v_kind
      using errcode = '22023';
  end if;

  if strpos(p_text, v_disclaimer.text) > 0 then
    v_out := p_text;
  else
    v_out := rtrim(p_text) || E'\n\n' || v_disclaimer.text;
  end if;

  if p_content_type <> 'public_page' and length(v_out) > 4096 then
    raise exception 'the message is too long once the disclaimer is added (% of 4096 characters)', length(v_out)
      using errcode = '22023';
  end if;

  return query select v_out, true, v_kind, v_locale, v_disclaimer.version;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_disclaimer(p_organization_id uuid, p_kind text, p_locale text, p_text text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_text text := trim(p_text);
  v_error text := crm.disclaimer_text_error(p_kind, p_text);
  v_current record;
  v_version int;
begin
  if auth.role() <> 'service_role' then
    perform crm.assert_can_read_settings(p_organization_id);
    perform crm.require_permission(p_organization_id, 'organization.manage');
  end if;

  if p_locale not in ('en', 'hi') then
    raise exception 'unknown language %', p_locale using errcode = '22023';
  end if;
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023';
  end if;

  select * into v_current
  from crm.current_disclaimer(p_organization_id, p_kind, p_locale);
  if v_current.text = v_text then
    return v_current.version;
  end if;

  select coalesce(max(v.version), 0) + 1 into v_version
  from crm.disclaimer_versions v
  where v.organization_id = p_organization_id
    and v.kind = p_kind
    and v.locale = p_locale;

  insert into crm.disclaimer_versions (
    organization_id, kind, locale, version, text, created_by
  ) values (
    p_organization_id, p_kind, p_locale, v_version, v_text,
    (crm.caller_agent(p_organization_id)).id
  );

  return v_version;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_organization_profiles()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_before jsonb := '{}'::jsonb;
  v_after jsonb := '{}'::jsonb;
  v_field text;
begin
  if tg_op = 'INSERT' then
    perform crm.write_audit(
      new.organization_id, 'organization.created', 'organization',
      new.organization_id::text,
      jsonb_build_object(
        'slug', new.slug, 'timezone', new.timezone, 'locale', new.locale
      )
    );
    return null;
  end if;

  if new.status is distinct from old.status then
    perform crm.write_audit(
      new.organization_id,
      case
        when new.status = 'suspended' then 'organization.suspended'
        when new.status = 'pending_deletion' then 'organization.deletion_requested'
        when old.status = 'suspended' then 'organization.reactivated'
        else 'organization.deletion_cancelled'
      end,
      'organization',
      new.organization_id::text,
      jsonb_strip_nulls(jsonb_build_object(
        'reason', new.suspended_reason,
        'purge_after', new.purge_after
      ))
    );
  end if;

  -- The fields a tenant edits: profile (P1-01) and business details (P1-07).
  for v_field in select unnest(array[
    'slug', 'timezone', 'locale', 'legal_name', 'address', 'support_email',
    'support_phone', 'website', 'registrations'
  ]) loop
    if to_jsonb(new)->v_field is distinct from to_jsonb(old)->v_field then
      v_before := v_before || jsonb_build_object(v_field, to_jsonb(old)->v_field);
      v_after := v_after || jsonb_build_object(v_field, to_jsonb(new)->v_field);
    end if;
  end loop;

  if v_after <> '{}'::jsonb then
    perform crm.write_audit(
      new.organization_id, 'organization.profile_updated', 'organization',
      new.organization_id::text,
      jsonb_build_object('before', v_before, 'after', v_after)
    );
  end if;

  if new.require_mfa_for_admins is distinct from old.require_mfa_for_admins then
    perform crm.write_audit(
      new.organization_id, 'organization.mfa_requirement_changed',
      'organization', new.organization_id::text,
      jsonb_build_object('required', new.require_mfa_for_admins)
    );
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.before_write_on_organization_profiles()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

grant select on table "crm"."disclaimer_versions" to "anon";

grant select on table "crm"."disclaimer_versions" to "authenticated";

grant delete on table "crm"."disclaimer_versions" to "service_role";

grant insert on table "crm"."disclaimer_versions" to "service_role";

grant references on table "crm"."disclaimer_versions" to "service_role";

grant select on table "crm"."disclaimer_versions" to "service_role";

grant trigger on table "crm"."disclaimer_versions" to "service_role";

grant truncate on table "crm"."disclaimer_versions" to "service_role";

grant update on table "crm"."disclaimer_versions" to "service_role";


  create policy "members can read their orgs disclaimer versions"
  on "crm"."disclaimer_versions"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));


CREATE TRIGGER audit AFTER INSERT ON crm.disclaimer_versions FOR EACH ROW EXECUTE FUNCTION crm.audit_disclaimer_versions();


