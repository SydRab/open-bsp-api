
  create table "crm"."contact_tags" (
    "contact_id" uuid not null,
    "tag_id" uuid not null,
    "organization_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."contact_tags" enable row level security;

CREATE INDEX contact_tags_organization_id_idx ON crm.contact_tags USING btree (organization_id);

CREATE UNIQUE INDEX contact_tags_pkey ON crm.contact_tags USING btree (contact_id, tag_id);

CREATE INDEX contact_tags_tag_id_idx ON crm.contact_tags USING btree (tag_id);

alter table "crm"."contact_tags" add constraint "contact_tags_pkey" PRIMARY KEY using index "contact_tags_pkey";

alter table "crm"."contact_tags" add constraint "contact_tags_contact_fkey" FOREIGN KEY (organization_id, contact_id) REFERENCES crm.contacts(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."contact_tags" validate constraint "contact_tags_contact_fkey";

alter table "crm"."contact_tags" add constraint "contact_tags_tag_fkey" FOREIGN KEY (organization_id, tag_id) REFERENCES crm.tags(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."contact_tags" validate constraint "contact_tags_tag_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.export_contacts(p_organization_id uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(contact_id uuid, display_name text, service public.service, address text, consent_status text, tags text, lead_status text, lead_stage text, deal_value numeric, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.set_contact_tag(p_contact_id uuid, p_tag_id uuid, p_tagged boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid := (
    select c.organization_id from crm.contacts c where c.id = p_contact_id
  );
begin
  if v_org is null then
    raise exception 'contact not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_org, 'contacts.edit');

  if not p_tagged then
    delete from crm.contact_tags
    where contact_id = p_contact_id and tag_id = p_tag_id;
    return;
  end if;

  if not exists (
    select 1 from crm.tags t where t.id = p_tag_id and t.organization_id = v_org
  ) then
    raise exception 'tag not found' using errcode = '22023';
  end if;

  insert into crm.contact_tags (organization_id, contact_id, tag_id)
  values (v_org, p_contact_id, p_tag_id)
  on conflict do nothing;
end;
$function$
;

grant select on table "crm"."contact_tags" to "anon";

grant select on table "crm"."contact_tags" to "authenticated";

grant delete on table "crm"."contact_tags" to "service_role";

grant insert on table "crm"."contact_tags" to "service_role";

grant references on table "crm"."contact_tags" to "service_role";

grant select on table "crm"."contact_tags" to "service_role";

grant trigger on table "crm"."contact_tags" to "service_role";

grant truncate on table "crm"."contact_tags" to "service_role";

grant update on table "crm"."contact_tags" to "service_role";


  create policy "members can read their orgs contact tags"
  on "crm"."contact_tags"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



