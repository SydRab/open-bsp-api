-- Contacts and custom fields triggers (P1-06).

-- A new upstream contact row (someone writes to, or is added on, one of the
-- organization's numbers) → the person behind it. The same (service,
-- address) on another of the organization's numbers is the same person.
-- Internal chat (service 'local') has no contacts.
create function crm.after_insert_on_contacts_addresses() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

create trigger crm_link_contact
after insert
on public.contacts_addresses
for each row
execute function crm.after_insert_on_contacts_addresses();

-- Every write to custom_fields: cleared fields dropped, each changed value
-- checked against its definition. Unchanged values pass even if their field
-- or option has since been archived.
create function crm.before_write_on_contacts() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

create trigger validate_custom_fields
before insert or update of custom_fields
on crm.contacts
for each row
execute function crm.before_write_on_contacts();

create trigger set_updated_at
before update
on crm.contacts
for each row
execute function public.moddatetime('updated_at');
