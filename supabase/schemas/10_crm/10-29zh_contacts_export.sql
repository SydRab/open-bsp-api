-- [crm] P3-11b: CSV export (the UI formats the CSV itself -- this just
-- returns the rows, same "a SQL function returning rows, no new edge
-- function" shape as every P3-10 report). Gated on `contacts.export`
-- ("Export contacts," P1-02) -- another permission that sat in the
-- catalog unused since the very start of the project, same discovery as
-- P3-10a's `reports.view`.
--
-- Consent status is resolved through crm.get_consent_status (P2-05,
-- service-role only -- "no execute grant to anon/authenticated," by
-- design) by calling it from INSIDE this security-definer function, not
-- by widening its own grant: the same "one more internal caller, no
-- grant change" shape crm._enqueue_conversion_event (P3-09) already used
-- for crm.write_audit and the dispatcher's own send path.
create function crm.export_contacts(
  p_organization_id uuid,
  p_from timestamp with time zone default null,
  p_to timestamp with time zone default null
) returns table (
  contact_id uuid,
  display_name text,
  service public.service,
  address text,
  consent_status text,
  tags text,
  lead_status text,
  lead_stage text,
  deal_value numeric,
  created_at timestamp with time zone
)
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(p_organization_id, 'contacts.export');

  return query
  select
    c.id,
    c.display_name,
    ca.service,
    ca.address,
    case
      when ca.address is null then null
      else crm.get_consent_status(p_organization_id, conv.organization_address, ca.service, ca.address)
    end,
    (
      select string_agg(t.name, ', ' order by t.name)
      from crm.contact_tags ct
      join crm.tags t on t.id = ct.tag_id
      where ct.contact_id = c.id
    ),
    l.status,
    s.name,
    l.deal_value,
    c.created_at
  from crm.contacts c
  left join lateral (
    select ca2.service, ca2.address
    from crm.contact_addresses ca2
    where ca2.contact_id = c.id and ca2.organization_id = p_organization_id
    order by ca2.created_at desc
    limit 1
  ) ca on true
  left join lateral (
    select conv2.organization_address
    from public.conversations conv2
    where conv2.organization_id = p_organization_id
      and conv2.service = ca.service and conv2.address = ca.address
    order by conv2.last_inbound_at desc nulls last
    limit 1
  ) conv on true
  left join crm.leads l on l.organization_id = p_organization_id and l.contact_id = c.id
  left join crm.lead_stages s on s.id = l.stage_id
  where c.organization_id = p_organization_id
    and (p_from is null or c.created_at >= p_from)
    and (p_to is null or c.created_at < p_to)
  order by c.created_at desc;
end;
$$;
