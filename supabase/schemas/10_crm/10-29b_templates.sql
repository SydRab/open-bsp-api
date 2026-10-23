-- WhatsApp message templates (P2-04). A local cache of each connected
-- number's Meta templates, kept current by:
--   - whatsapp-management's list/create calls (upsert on every call)
--   - the message_template_status_update / _quality_update webhook handlers
--     (crm.webhook_events -> whatsapp-webhook-processor), which previously
--     only logged these events (P2-01) and now also write here
-- All writes are service-role (the edge functions above); there is no
-- SECURITY DEFINER write function because nothing here is a secret -- unlike
-- crm.webhook_events / crm.set_whatsapp_access_token, a plain insert/update
-- through the unsecure client is enough.
create table crm.templates (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  -- organizations_addresses.address (service is always 'whatsapp' here, so
  -- not worth a column -- see 10-01_catalog's `service` enum for why it's
  -- part of that table's own key but every row we touch here is WhatsApp).
  organization_address text not null,
  -- Meta's template id. Nullable only in the brief window before a create
  -- call's response is known; the REST API returns ids as strings, the
  -- webhook's message_template_id as a number -- always cast to text here.
  meta_id text,
  name text not null,
  category text not null,
  language text not null,
  status text default 'PENDING'::text not null,
  quality_score text,
  components jsonb not null,
  rejection_reason text,
  -- organization_pack_items.item_key this was submitted from, or null for a
  -- manually-created template (see crm.organization_pack_items, kind =
  -- 'message_template').
  pack_item_key text,
  synced_at timestamp with time zone default now() not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

-- A template is unique by (number, name, language) on Meta's side -- this
-- is the upsert key every sync path writes through.
alter table only crm.templates
add constraint templates_pkey primary key (id);

alter table only crm.templates
add constraint templates_organization_id_fkey
foreign key (organization_id)
references public.organizations(id)
on delete cascade;

alter table only crm.templates
add constraint templates_org_address_name_language_key
unique (organization_id, organization_address, name, language);

alter table only crm.templates
add constraint templates_category_check
check (category in ('MARKETING', 'UTILITY'));

create trigger set_updated_at
before update
on crm.templates
for each row
execute function public.moddatetime('updated_at');

create index templates_meta_id_idx
on crm.templates (meta_id)
where meta_id is not null;
