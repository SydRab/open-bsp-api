-- Disclaimer audit (P1-07): every new version is logged with the text it
-- replaces (the previous version, or the pack's text for the first one).

create function crm.audit_disclaimer_versions() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

create trigger audit
after insert
on crm.disclaimer_versions
for each row
execute function crm.audit_disclaimer_versions();
