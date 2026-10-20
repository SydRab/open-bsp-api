-- Tenant profile and lifecycle (P1-01). One row per organization, created by
-- crm.after_insert_on_organizations (10-20) — no edit to the upstream
-- organization trigger.
--
-- Lifecycle:
--   active ──suspend──▶ suspended ──reactivate──▶ active        (platform)
--   active ──request deletion──▶ pending_deletion ──cancel──▶ active (owner)
--   pending_deletion ──purge_after passed──▶ row deleted (crm.purge_organizations)
--
-- Anything but `active` removes the organization from
-- public.get_authorized_orgs (one upstream edit, see docs/upstream-edits.md),
-- which is what cuts API access everywhere at once.
create table crm.organization_profiles (
  organization_id uuid not null,
  slug text not null,
  timezone text not null default 'Asia/Kolkata',
  locale text not null default 'en',
  status text not null default 'active',
  suspended_at timestamp with time zone,
  -- Shown to the tenant's members on the suspended banner. Platform-written.
  suspended_reason text,
  deletion_requested_at timestamp with time zone,
  deletion_requested_by uuid,
  -- When the soft delete becomes a hard delete.
  purge_after timestamp with time zone,
  -- Optional 2FA gate (P1-03): when true, owner- and admin-tier members get
  -- no crm permission until their session is aal2.
  require_mfa_for_admins boolean not null default false,
  -- Business details (P1-07), shown on public pages and receipts. The
  -- business's own contact details, not a person's. Checked by
  -- crm.before_write_on_organization_profiles (10-20).
  legal_name text,
  -- {line1, line2, city, state, postal_code, country}
  address jsonb,
  support_email text,
  support_phone text,
  website text,
  -- [{type: gstin | sebi_ra | sebi_ia | cin | udyam | other, number}]
  registrations jsonb not null default '[]'::jsonb,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.organization_profiles
add constraint organization_profiles_pkey primary key (organization_id);

alter table only crm.organization_profiles
add constraint organization_profiles_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.organization_profiles
add constraint organization_profiles_slug_key unique (slug);

-- Lowercase letters, digits and inner hyphens, 3 to 48 characters: safe in a
-- subdomain label and a URL path.
alter table only crm.organization_profiles
add constraint organization_profiles_slug_format
check (slug ~ '^[a-z0-9][a-z0-9-]{1,46}[a-z0-9]$');

alter table only crm.organization_profiles
add constraint organization_profiles_locale_check
check (locale in ('en', 'hi'));

alter table only crm.organization_profiles
add constraint organization_profiles_status_check
check (status in ('active', 'suspended', 'pending_deletion'));

alter table only crm.organization_profiles
add constraint organization_profiles_status_fields_check
check (
  (status <> 'suspended' or suspended_at is not null)
  and (status <> 'pending_deletion'
    or (deletion_requested_at is not null and purge_after is not null))
);

create index organization_profiles_purge_idx
on crm.organization_profiles (purge_after)
where status = 'pending_deletion';
