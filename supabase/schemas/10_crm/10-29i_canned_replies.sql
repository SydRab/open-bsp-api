-- Canned replies (P2-09e). Upstream once had almost exactly this
-- (`public.quick_replies`: org-scoped name+content, admins manage/members
-- read), dropped in a later refactor (`20260729192414_conversation_is_a_
-- channel.sql`) along with unrelated cleanup -- confirmed gone from the
-- current schema, not something to resurrect, so this is a fresh `crm`
-- table rather than reviving the old one. The admin-manage/member-read
-- split that migration's dropped policies show is kept: writes go through
-- crm.create_canned_reply & co. (10-29j), gated on 'templates.manage';
-- reading is open to any org member, same as using a tag.
create table crm.canned_replies (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  name text not null,
  content text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.canned_replies
add constraint canned_replies_pkey primary key (id);

alter table only crm.canned_replies
add constraint canned_replies_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.canned_replies
add constraint canned_replies_organization_id_name_key unique (organization_id, name);

alter table only crm.canned_replies
add constraint canned_replies_name_check
check (length(trim(name)) between 1 and 80);

alter table only crm.canned_replies
add constraint canned_replies_content_check
check (length(trim(content)) between 1 and 4096);

create index canned_replies_organization_id_idx
on crm.canned_replies (organization_id);

create trigger set_updated_at
before update
on crm.canned_replies
for each row
execute function public.moddatetime('updated_at');
