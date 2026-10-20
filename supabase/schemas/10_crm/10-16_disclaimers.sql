-- Disclaimers (P1-07). Table: 10-08. Audit trigger: 10-23.

-- Why a disclaimer text is not acceptable, or null.
--   short: 10–60 characters (a WhatsApp template footer holds 60), one line;
--   full:  20–1000 characters.
-- Neither may contain template placeholders ({{1}}).
-- Footer limit: https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates/components
create function crm.disclaimer_text_error(p_kind text, p_text text)
returns text
language sql
immutable
set search_path to ''
as $$
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
$$;

-- The disclaimer in force: the organization's latest version, else the
-- pack's text (version 0). Internal.
create function crm.current_disclaimer(
  p_organization_id uuid,
  p_kind text,
  p_locale text
) returns table (text text, version int, source text)
language sql
stable
security definer
set search_path to ''
as $$
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
$$;

-- The four disclaimers in force (short/full × en/hi) for the settings page.
-- Readable by members and API keys of an active organization.
create function crm.get_disclaimers(p_organization_id uuid)
returns table (kind text, locale text, text text, version int, source text)
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  perform crm.assert_can_read_settings(p_organization_id);

  return query
  select k.kind, l.locale, d.text, d.version, d.source
  from (values ('short', 1), ('full', 2)) k(kind, ord)
  cross join (values ('en', 1), ('hi', 2)) l(locale, ord)
  left join lateral crm.current_disclaimer(p_organization_id, k.kind, l.locale) d on true
  order by k.ord, l.ord;
end;
$$;

-- Saves a new version (organization.manage). Returns the version in force
-- afterwards; saving the text already in force adds nothing.
create function crm.set_disclaimer(
  p_organization_id uuid,
  p_kind text,
  p_locale text,
  p_text text
) returns int
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- THE way automatic content gets its disclaimer. Every sender (broadcasts,
-- digests, AI replies, receipts, public pages) calls this and sends what it
-- returns, keeping disclaimer_version as proof of the wording used.
--
-- Content types and which disclaimer they carry (decided 2026-10-21):
--   broadcast, digest, ai_message, payment_confirmation → short, when the
--     organization's attach rules (setting disclaimer.attach_rules) say so;
--   receipt → full, when the attach rules say so;
--   public_page, disclaimer_reply → full, always.
-- The language is p_locale, else the organization's, falling back to English
-- when there is no text in that language. A text that already contains the
-- disclaimer is returned unchanged. Messages are limited to 4096 characters
-- (WhatsApp text body):
-- https://developers.facebook.com/docs/whatsapp/cloud-api/messages/text-messages
create function crm.render_with_disclaimer(
  p_organization_id uuid,
  p_content_type text,
  p_text text,
  p_locale text default null
) returns table (
  text text,
  attached boolean,
  disclaimer_kind text,
  disclaimer_locale text,
  disclaimer_version int
)
language plpgsql
stable
security definer
set search_path to ''
as $$
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
$$;
