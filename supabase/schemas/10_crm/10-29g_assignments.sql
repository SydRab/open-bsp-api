-- Conversation assignment (P2-09c). Who is currently working a conversation.
-- One row per conversation -- not many-to-many like tags/teams -- because
-- "assigned" means a single current owner: a second crm.assign_conversation
-- call for the same conversation is a TRANSFER (it replaces the row's
-- agent_id), not an addition. Unassigning deletes the row; an unassigned
-- conversation has none.
--
-- Deliberately not public.conversations_agents: that table's writes are
-- locked to service_role on every service but `local` (05-12) because it
-- encodes real external membership/visibility (a Slack channel's members, a
-- local chat's roster) -- reusing it for a workflow concept members write
-- themselves would either require loosening that lock (a visibility risk) or
-- silently add a "membership" row that implies visibility it doesn't have.
-- Assignment grants no visibility here: a WhatsApp conversation is already
-- org-wide (shared inbox, see 04-02_visibility_helpers.sql) whether or not
-- anyone is assigned to it.
create table crm.conversation_assignments (
  conversation_id uuid not null,
  organization_id uuid not null,
  agent_id uuid not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.conversation_assignments
add constraint conversation_assignments_pkey primary key (conversation_id);

alter table only crm.conversation_assignments
add constraint conversation_assignments_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.conversation_assignments
add constraint conversation_assignments_conversation_fkey
foreign key (organization_id, conversation_id)
references public.conversations(organization_id, id) on delete cascade;

alter table only crm.conversation_assignments
add constraint conversation_assignments_agent_fkey
foreign key (organization_id, agent_id)
references public.agents(organization_id, id) on delete cascade;

create index conversation_assignments_organization_id_idx
on crm.conversation_assignments (organization_id);

-- "Conversations assigned to agent X" -- the lookup a future per-agent queue
-- view would run.
create index conversation_assignments_agent_id_idx
on crm.conversation_assignments (agent_id);

create trigger set_updated_at
before update
on crm.conversation_assignments
for each row
execute function public.moddatetime('updated_at');
