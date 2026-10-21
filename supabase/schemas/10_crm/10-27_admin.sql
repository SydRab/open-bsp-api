-- Super-admin console skeleton (P1-10). A platform admin is a separate
-- authorization axis from tenant roles (crm.permissions): being an owner or
-- admin of an organization grants nothing here, and being a platform admin
-- grants nothing inside a tenant beyond what this file defines.
--
-- Every admin action is reached through the crm-admin edge function, never
-- through a crm function granted to `authenticated`: the function checks
-- crm.is_platform_admin() on the caller's own JWT, then uses the service
-- role to act. Functions here (10-28) stay service_role-only (the blanket
-- grant in 10-40), except crm.is_platform_admin, which the UI also calls
-- directly to decide whether to show the console at all.
--
-- Bootstrapping the first admin is a documented, one-time manual insert
-- (docs/crm/phase-1-tenancy-roles-packs.md) — never a migration (that would
-- grant a hardcoded user admin rights in every environment) and never a UI
-- action (no admin yet exists to click it).

create table crm.platform_admins (
  user_id uuid not null,
  granted_at timestamp with time zone default now() not null,
  -- Null for the first, manually-bootstrapped admin.
  granted_by uuid
);

alter table only crm.platform_admins
add constraint platform_admins_pkey primary key (user_id);

alter table only crm.platform_admins
add constraint platform_admins_user_id_fkey
foreign key (user_id) references auth.users(id) on delete cascade;

alter table only crm.platform_admins
add constraint platform_admins_granted_by_fkey
foreign key (granted_by) references auth.users(id);

-- Platform-wide actions with no single organization to log them against
-- (crm.audit_log.organization_id is not null): admin grants/revokes, the
-- kill switch. Action targeting one organization (suspend, tier change,
-- pack upgrade, support-access grants) is written here too, for "which
-- admin did this" — and separately into that organization's own audit log
-- by the functions and triggers that already do, so a tenant sees it too.
create table crm.platform_audit_log (
  id bigint generated always as identity not null,
  created_at timestamp with time zone default now() not null,
  actor_user_id uuid not null,
  action text not null,
  target_type text,
  target_id text,
  details jsonb default '{}'::jsonb not null
);

alter table only crm.platform_audit_log
add constraint platform_audit_log_pkey primary key (id);

alter table only crm.platform_audit_log
add constraint platform_audit_log_actor_user_id_fkey
foreign key (actor_user_id) references auth.users(id);

alter table only crm.platform_audit_log
add constraint platform_audit_log_action_check
check (action ~ '^[a-z_]+\.[a-z_]+$');

create index platform_audit_log_id_idx
on crm.platform_audit_log (id desc);

-- A time-limited grant for one admin to read one organization's
-- configuration and audit log for support — never message or contact
-- content (crm.admin_get_tenant_config / admin_get_audit_log, 10-28). The
-- organization can see its own grants (10-30): who looked, when, and why.
create table crm.support_access_grants (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  admin_id uuid not null,
  reason text not null,
  granted_at timestamp with time zone default now() not null,
  expires_at timestamp with time zone not null,
  revoked_at timestamp with time zone
);

alter table only crm.support_access_grants
add constraint support_access_grants_pkey primary key (id);

alter table only crm.support_access_grants
add constraint support_access_grants_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.support_access_grants
add constraint support_access_grants_admin_id_fkey
foreign key (admin_id) references auth.users(id);

alter table only crm.support_access_grants
add constraint support_access_grants_reason_check
check (length(trim(reason)) >= 3);

create index support_access_grants_organization_id_idx
on crm.support_access_grants (organization_id);

create index support_access_grants_admin_id_org_idx
on crm.support_access_grants (admin_id, organization_id);
