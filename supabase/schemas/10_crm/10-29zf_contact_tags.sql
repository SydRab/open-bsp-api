-- [crm] P3-11b: contact tags. The same crm.tags catalog P2-09b built for
-- conversations, applied to a second entity -- a tag is still "a named
-- group" an org defines once, this is just a second kind of "membership"
-- in it, same shape as crm.conversation_tags itself (composite PK, a
-- denormalized organization_id for the tenant-scoped FKs, no own id).
create table crm.contact_tags (
  contact_id uuid not null,
  tag_id uuid not null,
  organization_id uuid not null,
  created_at timestamp with time zone default now() not null
);

alter table only crm.contact_tags
add constraint contact_tags_pkey primary key (contact_id, tag_id);

alter table only crm.contact_tags
add constraint contact_tags_tag_fkey
foreign key (organization_id, tag_id)
references crm.tags(organization_id, id) on delete cascade;

-- crm.contacts has unique(organization_id, id) (P1-06) -- a composite FK
-- is possible here, unlike crm.leads.
alter table only crm.contact_tags
add constraint contact_tags_contact_fkey
foreign key (organization_id, contact_id)
references crm.contacts(organization_id, id) on delete cascade;

create index contact_tags_organization_id_idx
on crm.contact_tags (organization_id);

create index contact_tags_tag_id_idx
on crm.contact_tags (tag_id);
