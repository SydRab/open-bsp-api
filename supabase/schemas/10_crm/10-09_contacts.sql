-- Person-level contacts (P1-06). Upstream public.contacts_addresses has one
-- row per (organization number × counterpart address), so one student who
-- writes to two of the organization's numbers is two upstream rows. A
-- crm.contacts row is the person; crm.contact_addresses maps each
-- (service, address) of the organization to exactly one person.
--
-- Created automatically when upstream adds a contact row (10-24), and
-- backfilled for existing ones. Merging one person across services
-- (WhatsApp + Telegram) is P3-02 / P7-02.
--
-- custom_fields holds the values of the organization's custom fields for
-- contacts (definitions: organization_pack_items, kind custom_field), checked
-- by crm.before_write_on_contacts (10-24).

create table crm.contacts (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  -- From the first channel that saw them (e.g. the WhatsApp profile name).
  display_name text,
  -- The contact's language for templates and disclaimers; null = the
  -- organization's.
  locale text,
  custom_fields jsonb default '{}'::jsonb not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.contacts
add constraint contacts_pkey primary key (id);

alter table only crm.contacts
add constraint contacts_organization_id_id_key unique (organization_id, id);

alter table only crm.contacts
add constraint contacts_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.contacts
add constraint contacts_locale_check
check (locale is null or locale in ('en', 'hi'));

alter table only crm.contacts
add constraint contacts_custom_fields_check
check (jsonb_typeof(custom_fields) = 'object');

create index contacts_organization_id_idx
on crm.contacts (organization_id);

-- Filters on field values (crm.filter_contacts) use containment.
create index contacts_custom_fields_idx
on crm.contacts using gin (custom_fields jsonb_path_ops);

create table crm.contact_addresses (
  organization_id uuid not null,
  service public.service not null,
  address text not null,
  contact_id uuid not null,
  created_at timestamp with time zone default now() not null
);

-- One person per (service, address) in an organization, whichever of the
-- organization's numbers they wrote to.
alter table only crm.contact_addresses
add constraint contact_addresses_pkey
primary key (organization_id, service, address);

alter table only crm.contact_addresses
add constraint contact_addresses_contact_fkey
foreign key (organization_id, contact_id)
references crm.contacts(organization_id, id) on delete cascade;

create index contact_addresses_contact_id_idx
on crm.contact_addresses (contact_id);
