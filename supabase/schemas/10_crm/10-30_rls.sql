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

-- Templates (P2-04) -----------------------------------------------------------------

alter table crm.templates enable row level security;

-- Writes are service-role only (list/create sync, the status/quality
-- webhooks, pack-template submission) -- no policy allows a member write.
create policy "members can read their orgs templates"
on crm.templates for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Outbound send policy (P2-05) -----------------------------------------------------

alter table crm.contacts_consent enable row level security;

-- Writes are service-role only (the inbound STOP handler, and any future
-- admin opt-in/opt-out action) -- no policy allows a member write.
create policy "members can read their orgs consent events"
on crm.contacts_consent for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

alter table crm.send_rate_buckets enable row level security;

-- Pure send-path infrastructure (token-bucket state for the dispatcher's
-- pacing check) -- no current UI reads this, but every organization_id
-- table gets a real policy (P1-12's structural check), not a blanket deny.
create policy "members can read their orgs send rate buckets"
on crm.send_rate_buckets for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Tags (P2-09b) -----------------------------------------------------------------

alter table crm.tags enable row level security;
alter table crm.conversation_tags enable row level security;

-- Writes go through crm.create_tag & co. (10-29f) -- same split as teams.
create policy "members can read their orgs tags"
on crm.tags for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

create policy "members can read their orgs conversation tags"
on crm.conversation_tags for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Assignments (P2-09c) ------------------------------------------------------------

alter table crm.conversation_assignments enable row level security;

-- Writes go through crm.assign_conversation / crm.unassign_conversation
-- (10-29h) -- same split as tags.
create policy "members can read their orgs conversation assignments"
on crm.conversation_assignments for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Canned replies (P2-09e) -----------------------------------------------------------

alter table crm.canned_replies enable row level security;

-- Writes go through crm.create_canned_reply & co. (10-29j), gated on
-- templates.manage; reading is open to any org member, same as tags.
create policy "members can read their orgs canned replies"
on crm.canned_replies for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Lead model (P3-02) ---------------------------------------------------------------

alter table crm.lead_stages enable row level security;
alter table crm.lead_qualities enable row level security;
alter table crm.lead_drop_reasons enable row level security;
alter table crm.leads enable row level security;

-- Writes go through crm.create_lead_stage & co. (10-29n), gated on
-- organization.manage; reading the catalogs is open to any org member,
-- same bar as tags (everyone needs to see the options to use them).
create policy "members can read their orgs lead stages"
on crm.lead_stages for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

create policy "members can read their orgs lead qualities"
on crm.lead_qualities for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

create policy "members can read their orgs lead drop reasons"
on crm.lead_drop_reasons for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- [crm] P3-07b: writes go through crm.set_stage_required_fields (10-29n),
-- gated on organization.manage; reading is open to any org member, same
-- bar as the other lead catalogs above.
alter table crm.lead_stage_required_fields enable row level security;

create policy "members can read their orgs stage required fields"
on crm.lead_stage_required_fields for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- [crm] P3-07d: writes go through crm.create_task & co. (10-29w), gated
-- on deals.edit; reads additionally re-check lead_scope visibility (the
-- same predicate crm.leads' own RLS policy uses), since a task is only
-- ever meaningful in the context of a lead the caller can already see.
alter table crm.tasks enable row level security;

create policy "members can read tasks on leads they can see"
on crm.tasks for select to authenticated, anon
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and crm._lead_visible_to_caller(lead_id)
);

-- [crm] P3-07e: writes go through crm.create_lead_note & co. (10-29y),
-- gated on deals.edit; reads re-check lead_scope visibility the same way
-- crm.tasks does, above.
alter table crm.lead_notes enable row level security;

create policy "members can read notes on leads they can see"
on crm.lead_notes for select to authenticated, anon
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and crm._lead_visible_to_caller(lead_id)
);

-- Writes go through crm.find_or_create_lead & co., gated on deals.edit.
-- [crm] P3-07a: lead_scope ('own'/'team'/'all', crm.resolve_lead_scope,
-- 10-10) enforced here -- this is the "pipeline UI" phase the deferral
-- comment above used to point to. 'own' sees only leads assigned to the
-- caller; 'team' sees leads assigned to anyone on the caller's own
-- team(s), but never an unassigned lead -- manually picking one up is a
-- manager/admin action, and those roles already default to lead_scope=
-- 'all'; 'all' sees every lead in the org, assigned or not.
create policy "members can read leads within their lead_scope"
on crm.leads for select to authenticated, anon
using (
  crm.leads.organization_id in (select public.get_authorized_orgs('member'))
  and (
    crm.resolve_lead_scope(crm.leads.organization_id) = 'all'
    or (
      crm.resolve_lead_scope(crm.leads.organization_id) = 'team'
      and crm.leads.assigned_to in (
        select tm2.agent_id
        from crm.team_members tm1
        join crm.team_members tm2 on tm2.team_id = tm1.team_id
        where tm1.agent_id = (crm.caller_agent(crm.leads.organization_id)).id
      )
    )
    or (
      crm.resolve_lead_scope(crm.leads.organization_id) = 'own'
      and crm.leads.assigned_to = (crm.caller_agent(crm.leads.organization_id)).id
    )
  )
);

-- Qualification engine (P3-04) --------------------------------------------------------

alter table crm.lead_qualification_state enable row level security;
alter table crm.qualification_question_scores enable row level security;
alter table crm.qualification_score_thresholds enable row level security;

-- Writes are entirely trigger/system-driven (crm.z_run_qualification_engine,
-- crm._send_nudge) -- no member-facing write function exists for this
-- table, so it is read-only to members, same bar as the lead catalogs.
create policy "members can read their orgs qualification state"
on crm.lead_qualification_state for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Writes go through crm.set_qualification_question_score & co., gated on
-- organization.manage; reading the catalog is open to any member, same bar
-- as the other lead catalogs.
create policy "members can read their orgs qualification question scores"
on crm.qualification_question_scores for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

create policy "members can read their orgs qualification score thresholds"
on crm.qualification_score_thresholds for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Assignment engine (P3-05) ------------------------------------------------------------

alter table crm.assignment_rules enable row level security;

-- Writes go through crm.set_assignment_rule & co., gated on
-- organization.manage; reading the rules is open to any member, same bar
-- as the other lead catalogs.
create policy "members can read their orgs assignment rules"
on crm.assignment_rules for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

-- Speed-to-lead (P3-06) -----------------------------------------------------------------

alter table crm.notifications enable row level security;

-- Writes are entirely system-driven (crm._create_notification, called
-- from crm.sweep_speed_to_lead_escalation) -- a member only ever reads
-- their OWN notifications (not every member's, unlike the lead catalogs
-- above), and marks them read via crm.mark_notification_read & co.
create policy "members can read their own notifications"
on crm.notifications for select to authenticated
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and exists (
    select 1 from public.agents a
    where a.id = agent_id and a.user_id = auth.uid() and a.deleted_at is null
  )
);
