-- Row level security for every crm table. Tenant tables are readable by the
-- organization's members (through upstream get_authorized_orgs, so a
-- suspended or deleted organization reads as empty) and writable only where a
-- policy below says so; everything else goes through the functions in 10-1x.
-- Catalog tables are readable by any signed-in caller.

-- Catalog ---------------------------------------------------------------------

alter table crm.permissions enable row level security;
alter table crm.preset_roles enable row level security;
alter table crm.preset_role_permissions enable row level security;
alter table crm.vertical_packs enable row level security;
alter table crm.pack_versions enable row level security;

create policy "signed-in users can read the permission catalog"
on crm.permissions for select to authenticated, anon
using (true);

create policy "signed-in users can read preset roles"
on crm.preset_roles for select to authenticated, anon
using (true);

create policy "signed-in users can read preset role permissions"
on crm.preset_role_permissions for select to authenticated, anon
using (true);

create policy "signed-in users can read vertical packs"
on crm.vertical_packs for select to authenticated, anon
using (true);

create policy "signed-in users can read pack versions"
on crm.pack_versions for select to authenticated, anon
using (true);

-- Tenant tables ---------------------------------------------------------------

alter table crm.organization_profiles enable row level security;
alter table crm.roles enable row level security;
alter table crm.role_permissions enable row level security;
alter table crm.member_roles enable row level security;
alter table crm.member_permission_overrides enable row level security;
alter table crm.member_address_access enable row level security;
alter table crm.invitation_roles enable row level security;
alter table crm.organization_packs enable row level security;
alter table crm.organization_pack_items enable row level security;

create policy "members can read their orgs profile"
on crm.organization_profiles for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Column grants (10-40) limit this to slug, timezone and locale.
create policy "managers can update their orgs profile"
on crm.organization_profiles for update to authenticated
using (organization_id in (select crm.get_permitted_orgs('organization.manage')))
with check (organization_id in (select crm.get_permitted_orgs('organization.manage')));

create policy "members can read their orgs roles"
on crm.roles for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

create policy "members can read their orgs role permissions"
on crm.role_permissions for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

create policy "members can read their orgs member roles"
on crm.member_roles for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Overrides and number scopes are management data: the member themselves and
-- whoever manages members.
create policy "members can read their own overrides, managers all"
on crm.member_permission_overrides for select to authenticated, anon
using (
  agent_id in (select public.get_own_agents())
  or organization_id in (select crm.get_permitted_orgs('members.manage'))
);

create policy "members can read their own number access, managers all"
on crm.member_address_access for select to authenticated, anon
using (
  agent_id in (select public.get_own_agents())
  or organization_id in (select crm.get_permitted_orgs('members.manage'))
);

create policy "members can read their orgs invitation roles"
on crm.invitation_roles for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- The invitee, who is not a member yet, sees the role they are offered.
create policy "invitees can read their invitation role"
on crm.invitation_roles for select to authenticated
using (
  invitation_id in (
    select i.id from public.invitations i
    where i.status = 'pending'
      and lower(i.email) = lower((select auth.jwt()->>'email'))
  )
);

create policy "members can read their orgs pack"
on crm.organization_packs for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

create policy "members can read their orgs pack items"
on crm.organization_pack_items for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Column grants (10-40) limit this to `value`. Compliance and module items
-- are the pack layer of settings (P1-04): tenants change those through
-- crm.set_setting, so a pack upgrade never meets a tenant edit there.
-- Custom fields change through crm.update_custom_field (P1-06), which checks
-- the definition.
create policy "managers can edit their orgs pack items"
on crm.organization_pack_items for update to authenticated
using (
  organization_id in (select crm.get_permitted_orgs('organization.manage'))
  and kind not in ('compliance', 'module', 'custom_field')
)
with check (
  organization_id in (select crm.get_permitted_orgs('organization.manage'))
  and kind not in ('compliance', 'module', 'custom_field')
);

-- Audit log (P1-08) -----------------------------------------------------------

alter table crm.audit_log enable row level security;

-- Signed-in members holding audit.view (Owner and Admin by default). Not API
-- keys: the table is granted to authenticated only (10-40). There are no
-- write policies; crm.write_audit is the only writer.
create policy "audit viewers can read their orgs audit log"
on crm.audit_log for select to authenticated
using (organization_id in (select crm.get_permitted_orgs('audit.view')));

-- Teams and settings (P1-04) ---------------------------------------------------

alter table crm.teams enable row level security;
alter table crm.team_members enable row level security;
alter table crm.setting_definitions enable row level security;
alter table crm.setting_values enable row level security;

create policy "members can read their orgs teams"
on crm.teams for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

create policy "members can read their orgs team members"
on crm.team_members for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

create policy "signed-in users can read the settings catalog"
on crm.setting_definitions for select to authenticated, anon
using (true);

-- Organization and team values: every member. A member's own values: that
-- member and whoever manages members. Writes go through crm.set_setting.
create policy "members can read their orgs settings"
on crm.setting_values for select to authenticated, anon
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and (
    scope <> 'user'
    or agent_id in (select public.get_own_agents())
    or organization_id in (select crm.get_permitted_orgs('members.manage'))
  )
);

-- Disclaimers (P1-07) ------------------------------------------------------------

alter table crm.disclaimer_versions enable row level security;

-- Every member reads the history; versions are written by crm.set_disclaimer.
create policy "members can read their orgs disclaimer versions"
on crm.disclaimer_versions for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Contacts and custom field values (P1-06) ---------------------------------------

alter table crm.contacts enable row level security;
alter table crm.contact_addresses enable row level security;

-- A contact is visible when the caller holds contacts.view AND can see at
-- least one of the person's upstream contact rows. That subquery runs under
-- the caller's own row level security on public.contacts_addresses, so
-- number scope (crm.member_address_access) and personal connections apply
-- exactly as they do upstream.
create policy "members can read contacts they can see"
on crm.contacts for select to authenticated, anon
using (
  organization_id in (select crm.get_permitted_orgs('contacts.view'))
  and exists (
    select 1
    from crm.contact_addresses ca
    join public.contacts_addresses c
      on c.organization_id = ca.organization_id
     and c.service = ca.service
     and c.address = ca.address
    where ca.contact_id = contacts.id
  )
);

-- Column grants (10-40) limit this to custom_fields; values are checked by
-- crm.before_write_on_contacts.
create policy "editors can update contacts they can see"
on crm.contacts for update to authenticated
using (
  organization_id in (select crm.get_permitted_orgs('contacts.edit'))
  and exists (
    select 1
    from crm.contact_addresses ca
    join public.contacts_addresses c
      on c.organization_id = ca.organization_id
     and c.service = ca.service
     and c.address = ca.address
    where ca.contact_id = contacts.id
  )
)
with check (organization_id in (select crm.get_permitted_orgs('contacts.edit')));

create policy "members can read the addresses of contacts they can see"
on crm.contact_addresses for select to authenticated, anon
using (
  organization_id in (select crm.get_permitted_orgs('contacts.view'))
  and exists (
    select 1 from public.contacts_addresses c
    where c.organization_id = contact_addresses.organization_id
      and c.service = contact_addresses.service
      and c.address = contact_addresses.address
  )
);

-- Feature flags and plan entitlements (P1-09) ------------------------------------

alter table crm.features enable row level security;
alter table crm.tier_features enable row level security;
alter table crm.organization_features enable row level security;

create policy "signed-in users can read the feature catalog"
on crm.features for select to authenticated, anon
using (true);

create policy "signed-in users can read tier entitlements"
on crm.tier_features for select to authenticated, anon
using (true);

create policy "members can read their orgs feature overrides"
on crm.organization_features for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Super-admin console (P1-10) ---------------------------------------------------

alter table crm.platform_admins enable row level security;
alter table crm.platform_audit_log enable row level security;
alter table crm.support_access_grants enable row level security;

-- Deliberately no select policy for anon/authenticated on platform_admins or
-- platform_audit_log: who the platform admins are, and what they have done,
-- is platform-internal. Only service_role (the crm-admin edge function,
-- after checking crm.is_platform_admin) reads them.

-- The organization can see grants made against it: who looked, when, why.
create policy "org managers can see support-access grants against their org"
on crm.support_access_grants for select to authenticated, anon
using (organization_id in (select crm.get_permitted_orgs('organization.manage')));

-- Webhook hardening (P2-01) -------------------------------------------------------

alter table crm.webhook_events enable row level security;

-- Deliberately no select policy for anon/authenticated: raw webhook payloads
-- can span several tenants at once and are platform infrastructure, not
-- tenant-readable data. Only service_role (the webhook handler and
-- whatsapp-webhook-processor) reads or writes them.
