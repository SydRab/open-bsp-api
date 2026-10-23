-- Tags (P2-09b). A named label an org defines once and applies to any
-- number of conversations -- structurally almost identical to crm.teams/
-- crm.team_members (10-06_teams.sql), mirrored deliberately: a tag is "a
-- named group," a conversation_tags row is "membership" in it, same as a
-- team and its members. Managed through crm.create_tag & co. (10-29f),
-- never written directly -- same split as teams.
create table crm.tags (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  name text not null,
  -- A small fixed palette, not a free-form hex picker: keeps the chip UI
  -- simple and every tag visually consistent across the org, at the cost
  -- of not letting an org pick an exact brand color for a tag. Revisit if
  -- that cost turns out to matter.
  color text default 'gray' not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.tags
add constraint tags_pkey primary key (id);

alter table only crm.tags
add constraint tags_organization_id_id_key unique (organization_id, id);

alter table only crm.tags
add constraint tags_organization_id_name_key unique (organization_id, name);

alter table only crm.tags
add constraint tags_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.tags
add constraint tags_name_check
check (length(trim(name)) between 1 and 40);

alter table only crm.tags
add constraint tags_color_check
check (color in ('red', 'orange', 'yellow', 'green', 'blue', 'purple', 'gray'));

create trigger set_updated_at
before update
on crm.tags
for each row
execute function public.moddatetime('updated_at');

create table crm.conversation_tags (
  conversation_id uuid not null,
  tag_id uuid not null,
  organization_id uuid not null,
  created_at timestamp with time zone default now() not null
);

alter table only crm.conversation_tags
add constraint conversation_tags_pkey primary key (conversation_id, tag_id);

alter table only crm.conversation_tags
add constraint conversation_tags_tag_fkey
foreign key (organization_id, tag_id)
references crm.tags(organization_id, id) on delete cascade;

alter table only crm.conversation_tags
add constraint conversation_tags_conversation_fkey
foreign key (organization_id, conversation_id)
references public.conversations(organization_id, id) on delete cascade;

create index conversation_tags_organization_id_idx
on crm.conversation_tags (organization_id);

create index conversation_tags_tag_id_idx
on crm.conversation_tags (tag_id);
