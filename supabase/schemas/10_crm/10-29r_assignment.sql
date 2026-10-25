-- [crm] P3-05: assignment engine. Routes a qualified lead to a crm.teams
-- team (reusing the existing flat team/team_members shape as the
-- distribution "pool" -- no new pool concept needed), then picks a member
-- within that team by weighted round robin, respecting working hours and
-- a capacity cap. crm.leads.assigned_to/assigned_at (10-29m) hold the
-- current owner; there is no separate assignment-history table -- like
-- every other lead mutation, crm.audit_log carries the trail.
--
-- Rules are an ordered, admin-editable list (organization.manage): each
-- one matches on language/source/campaign-or-ad-ref (all optional --
-- null means "any"), first match wins. No match, or an exhausted pool
-- (everyone over capacity or off-hours), leaves the lead unassigned for
-- manual pickup -- confirmed with the user: no guessing fallback that
-- could route a Hindi-speaking lead to an English-only rep.
create table crm.assignment_rules (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  team_id uuid not null,
  -- All three are optional match conditions (null = wildcard, matches any).
  match_language text,
  match_source text,
  -- crm.contacts.first_touch_referral->>'source_id' (P3-01): a specific
  -- ad or post id, for "route this specific campaign's leads to X."
  match_campaign_ref text,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.assignment_rules
add constraint assignment_rules_pkey primary key (id);

alter table only crm.assignment_rules
add constraint assignment_rules_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.assignment_rules
add constraint assignment_rules_team_fkey
foreign key (organization_id, team_id)
references crm.teams(organization_id, id) on delete cascade;

alter table only crm.assignment_rules
add constraint assignment_rules_match_language_check
check (match_language is null or match_language in ('en', 'hi'));

alter table only crm.assignment_rules
add constraint assignment_rules_match_source_check
check (match_source is null or match_source in ('ctwa_ad', 'ctwa_post', 'organic', 'manual'));

create index assignment_rules_organization_id_idx
on crm.assignment_rules (organization_id);

create trigger set_updated_at
before update
on crm.assignment_rules
for each row
execute function public.moddatetime('updated_at');
