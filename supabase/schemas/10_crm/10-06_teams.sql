-- Teams (P1-04). Minimal for now: a named group of members in one
-- organization. The settings engine resolves team-level settings through
-- them; lead assignment (P3-05) and the "team" lead scope build on them later.
-- Managed through crm.create_team & co. (10-15), never written directly.

create table crm.teams (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  name text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.teams
add constraint teams_pkey primary key (id);

alter table only crm.teams
add constraint teams_organization_id_id_key unique (organization_id, id);

alter table only crm.teams
add constraint teams_organization_id_name_key unique (organization_id, name);

alter table only crm.teams
add constraint teams_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.teams
add constraint teams_name_check
check (length(trim(name)) between 1 and 60);

create table crm.team_members (
  team_id uuid not null,
  organization_id uuid not null,
  agent_id uuid not null,
  created_at timestamp with time zone default now() not null
);

alter table only crm.team_members
add constraint team_members_pkey primary key (team_id, agent_id);

alter table only crm.team_members
add constraint team_members_team_fkey
foreign key (organization_id, team_id)
references crm.teams(organization_id, id) on delete cascade;

alter table only crm.team_members
add constraint team_members_agent_fkey
foreign key (organization_id, agent_id)
references public.agents(organization_id, id) on delete cascade;

create index team_members_organization_id_idx
on crm.team_members (organization_id);

create index team_members_agent_id_idx
on crm.team_members (agent_id);
