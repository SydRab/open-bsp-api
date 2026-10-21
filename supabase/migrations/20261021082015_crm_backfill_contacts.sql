-- Person-level contacts for upstream contact rows that existed before P1-06
-- (new rows get theirs from crm.after_insert_on_contacts_addresses). One
-- person per (organization, service, address), named from the first row that
-- has a name. Idempotent: addresses already linked are skipped.

do $backfill$
declare
  v_row record;
  v_contact uuid;
begin
  for v_row in
    select distinct on (c.organization_id, c.service, c.address)
      c.organization_id, c.service, c.address,
      nullif(trim(coalesce(c.extra->>'name', c.extra->'synced'->>'name')), '') as name
    from public.contacts_addresses c
    where c.service <> 'local'
      and not exists (
        select 1 from crm.contact_addresses ca
        where ca.organization_id = c.organization_id
          and ca.service = c.service
          and ca.address = c.address
      )
    order by c.organization_id, c.service, c.address,
      (coalesce(c.extra->>'name', c.extra->'synced'->>'name') is null), c.created_at
  loop
    insert into crm.contacts (organization_id, display_name)
    values (v_row.organization_id, v_row.name)
    returning id into v_contact;

    insert into crm.contact_addresses (organization_id, service, address, contact_id)
    values (v_row.organization_id, v_row.service, v_row.address, v_contact);
  end loop;
end;
$backfill$;
