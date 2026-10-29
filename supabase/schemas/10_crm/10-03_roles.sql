-- Roles and permissions per tenant (P1-02), and the role an invitation
-- carries (P1-03).
--
-- Every organization gets its own copy of the eight preset roles when it is
-- created, so "per-tenant toggles" are plain rows in role_permissions. A
-- custom role builder (later) adds rows with is_preset = false.

create table crm.roles (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  key text not null,
  name text not null,
  description text,
  tier public.role not null,
  lead_scope text not null default 'all',
  is_preset boolean not null default true,
  -- The owner role always holds every permission: nobody can lock the
  -- organization out of itself by toggling.
  is_locked boolean not null default false,
  sort_order int not null default 0,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.roles
add constraint roles_pkey primary key (id);

alter table only crm.roles
add constraint roles_organization_id_key_key unique (organization_id, key);

-- Composite target so member_roles can pin role AND organization in one FK.
alter table only crm.roles
add constraint roles_organization_id_id_key unique (organization_id, id);

alter table only crm.roles
add constraint roles_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.roles
add constraint roles_lead_scope_check
check (lead_scope in ('own', 'team', 'all'));

create table crm.role_permissions (
  organization_id uuid not null,
  role_id uuid not null,
  permission text not null,
  created_at timestamp with time zone default now() not null
);

alter table only crm.role_permissions
add constraint role_permissions_pkey primary key (role_id, permission);

alter table only crm.role_permissions
add constraint role_permissions_role_fkey
foreign key (organization_id, role_id)
references crm.roles(organization_id, id) on delete cascade;

alter table only crm.role_permissions
add constraint role_permissions_permission_fkey
foreign key (permission) references crm.permissions(key) on delete cascade;

create index role_permissions_organization_id_idx
on crm.role_permissions (organization_id);

-- The crm role of a human member. Source of truth for the role: a trigger
-- copies its tier onto public.agents.role, so upstream policies and the
-- upstream last-owner guard keep working (10-20).
create table crm.member_roles (
  agent_id uuid not null,
  organization_id uuid not null,
  role_id uuid not null,
  -- Overrides the role's lead_scope for this member; null = role default.
  lead_scope text,
  -- [crm] P3-07d: where WhatsApp-delivered internal alerts (task reminders,
  -- and eventually P3-06's speed-to-lead ones) reach this member -- their
  -- own phone, set self-service (crm.set_my_whatsapp_address). Null means
  -- "not set yet," falling back to in-app-only, same graceful degradation
  -- as a missing/unapproved alert template.
  whatsapp_address text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.member_roles
add constraint member_roles_pkey primary key (agent_id);

alter table only crm.member_roles
add constraint member_roles_agent_fkey
foreign key (organization_id, agent_id)
references public.agents(organization_id, id) on delete cascade;

alter table only crm.member_roles
add constraint member_roles_role_fkey
foreign key (organization_id, role_id)
references crm.roles(organization_id, id);

alter table only crm.member_roles
add constraint member_roles_lead_scope_check
check (lead_scope is null or lead_scope in ('own', 'team', 'all'));

create index member_roles_organization_id_idx
on crm.member_roles (organization_id);

create index member_roles_role_id_idx
on crm.member_roles (role_id);

-- Per-member exceptions to the role: granted = true adds a permission the
-- role lacks, false removes one it has.
create table crm.member_permission_overrides (
  agent_id uuid not null,
  organization_id uuid not null,
  permission text not null,
  granted boolean not null,
  created_at timestamp with time zone default now() not null
);

alter table only crm.member_permission_overrides
add constraint member_permission_overrides_pkey primary key (agent_id, permission);

alter table only crm.member_permission_overrides
add constraint member_permission_overrides_agent_fkey
foreign key (organization_id, agent_id)
references public.agents(organization_id, id) on delete cascade;

alter table only crm.member_permission_overrides
add constraint member_permission_overrides_permission_fkey
foreign key (permission) references crm.permissions(key) on delete cascade;

create index member_permission_overrides_organization_id_idx
on crm.member_permission_overrides (organization_id);

-- WhatsApp number (connected account) access scope. A member with NO rows
-- here sees every shared account of the organization, as upstream does. A
-- member with rows sees only the listed accounts (local internal chat is
-- never restricted). Enforced by restrictive policies in 10-50.
create table crm.member_address_access (
  agent_id uuid not null,
  organization_id uuid not null,
  service public.service not null,
  address text not null,
  created_at timestamp with time zone default now() not null
);

alter table only crm.member_address_access
add constraint member_address_access_pkey
primary key (agent_id, service, address);

alter table only crm.member_address_access
add constraint member_address_access_agent_fkey
foreign key (organization_id, agent_id)
references public.agents(organization_id, id) on delete cascade;

alter table only crm.member_address_access
add constraint member_address_access_address_fkey
foreign key (organization_id, service, address)
references public.organizations_addresses(organization_id, service, address)
on delete cascade;

alter table only crm.member_address_access
add constraint member_address_access_not_local
check (service <> 'local');

create index member_address_access_organization_id_idx
on crm.member_address_access (organization_id);

-- The crm role an invitation grants. Beside, not inside, public.invitations
-- so the upstream table stays untouched; the upstream `role` column carries
-- the matching tier.
create table crm.invitation_roles (
  invitation_id uuid not null,
  organization_id uuid not null,
  role_id uuid not null,
  created_at timestamp with time zone default now() not null
);

alter table only crm.invitation_roles
add constraint invitation_roles_pkey primary key (invitation_id);

alter table only crm.invitation_roles
add constraint invitation_roles_invitation_fkey
foreign key (invitation_id) references public.invitations(id) on delete cascade;

alter table only crm.invitation_roles
add constraint invitation_roles_role_fkey
foreign key (organization_id, role_id)
references crm.roles(organization_id, id) on delete cascade;

create index invitation_roles_organization_id_idx
on crm.invitation_roles (organization_id);
