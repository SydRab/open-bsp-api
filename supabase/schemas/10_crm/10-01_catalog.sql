-- Platform catalog (P1-02): what can be granted, and the eight preset roles a
-- new organization starts from. Not tenant-owned — one copy for the platform.
-- Rows are data, loaded by the `crm_permission_catalog` migration.

-- The ordinal access tier from upstream (`public.role`): owner > admin >
-- member. Every crm role maps onto one tier, and the tier is what upstream
-- policies see through agents.role (ADR 0002 §5).
create function crm.tier_rank(tier public.role) returns int
language sql
immutable
set search_path to ''
as $$
  select case tier
    when 'owner' then 3
    when 'admin' then 2
    else 1
  end;
$$;

create table crm.permissions (
  key text not null,
  category text not null,
  description text not null,
  -- The lowest tier a role must have to hold this permission. It matters for
  -- permissions an UPSTREAM policy also checks by tier (e.g. upstream lets
  -- only owners manage webhooks): granting one to a member-tier role would
  -- show a toggle that does nothing. crm-only permissions use 'member'.
  min_tier public.role not null default 'member',
  sort_order int not null default 0,
  created_at timestamp with time zone default now() not null
);

alter table only crm.permissions
add constraint permissions_pkey primary key (key);

alter table only crm.permissions
add constraint permissions_key_format
check (key ~ '^[a-z_]+\.[a-z_]+$');

create table crm.preset_roles (
  key text not null,
  name text not null,
  description text not null,
  tier public.role not null,
  -- Default lead visibility for the role: 'own' (assigned to me), 'team'
  -- (my batches/teams), 'all'. Enforced by the pipeline phase.
  lead_scope text not null default 'all',
  sort_order int not null default 0
);

alter table only crm.preset_roles
add constraint preset_roles_pkey primary key (key);

alter table only crm.preset_roles
add constraint preset_roles_lead_scope_check
check (lead_scope in ('own', 'team', 'all'));

create table crm.preset_role_permissions (
  role_key text not null,
  permission text not null
);

alter table only crm.preset_role_permissions
add constraint preset_role_permissions_pkey primary key (role_key, permission);

alter table only crm.preset_role_permissions
add constraint preset_role_permissions_role_key_fkey
foreign key (role_key) references crm.preset_roles(key) on delete cascade;

alter table only crm.preset_role_permissions
add constraint preset_role_permissions_permission_fkey
foreign key (permission) references crm.permissions(key) on delete cascade;
