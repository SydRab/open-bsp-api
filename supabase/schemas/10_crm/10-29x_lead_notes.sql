-- [crm] P3-07e: lead notes, the last named item on P3-07's roadmap line.
-- A new entity, not conversation-level internal notes (P2-09a, content.
-- internal on public.messages) -- a note belongs to the lead/pursuit
-- itself (it should survive a reassignment or a second conversation on
-- the same lead), not one conversation thread, confirmed during P3-07a's
-- own scoping research.
create table crm.lead_notes (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  lead_id uuid not null,
  author_agent_id uuid not null,
  body text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.lead_notes
add constraint lead_notes_pkey primary key (id);

alter table only crm.lead_notes
add constraint lead_notes_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

-- Plain (not composite) -- crm.leads has no unique(organization_id, id),
-- same limitation hit repeatedly since P3-04.
alter table only crm.lead_notes
add constraint lead_notes_lead_fkey
foreign key (lead_id) references crm.leads(id) on delete cascade;

alter table only crm.lead_notes
add constraint lead_notes_author_fkey
foreign key (organization_id, author_agent_id)
references public.agents(organization_id, id);

alter table only crm.lead_notes
add constraint lead_notes_body_check
check (length(trim(body)) between 1 and 4000);

create index lead_notes_lead_id_idx
on crm.lead_notes (lead_id, created_at desc);

create trigger set_updated_at
before update
on crm.lead_notes
for each row
execute function public.moddatetime('updated_at');
