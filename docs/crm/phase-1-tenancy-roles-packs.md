# Phase 1: tenancy, roles, invitations, vertical packs

Covers P1-01, P1-02, P1-03, P1-04, P1-05 and P1-08. Design: [ADR 0002](../adr/0002-tenancy-model.md).
Schema: `supabase/schemas/10_crm/`. Tests: `supabase/tests/database/crm_*.test.sql`
(`npx supabase test db`) and `scripts/crm/pack_test.ts` (`deno test --allow-read scripts/crm`).

## Model in one page

- **Tenant** = `public.organizations`. Every crm tenant table has `organization_id`,
  RLS on, and a cross-tenant test.
- **Profile and lifecycle** (`crm.organization_profiles`): slug, timezone (default
  `Asia/Kolkata`), locale (`en`/`hi`), `status` = `active | suspended | pending_deletion`.
  Any non-active status removes the organization from `public.get_authorized_orgs`, so
  every API path (JWT and API key) loses access at once. Members learn why through
  `crm.get_my_organization_statuses()` (the UI banner).
- **Roles**: each organization gets its own copy of the eight presets (Owner, Admin,
  Sales Manager, Sales Rep, Marketing, Teacher, Finance, Viewer) in `crm.roles` +
  `crm.role_permissions`. Owner is locked and always holds every permission.
- **Members** stay upstream `public.agents` rows. `crm.member_roles` holds each member's
  crm role and is the source of truth; a trigger copies the role's tier onto
  `agents.role` (Owner → owner, Admin → admin, the rest → member), so upstream policies
  and the upstream last-owner guard keep working.
- **Permissions**: `crm.has_permission(org, perm)` / `crm.get_permitted_orgs(perm)`.
  Resolution: active membership → active organization → optional 2FA gate (owner/admin
  tiers need an `aal2` session when the org requires it) → member override, else role.
  API keys are tier-only until scoped keys (P9-01).
- **Enforcement on upstream tables** (`10-50_upstream_policies.sql`, all `as restrictive`):
  reading conversations/messages needs `conversations.view`, sending needs
  `messages.send`, contacts need `contacts.view`/`contacts.edit`, renaming the org needs
  `organization.manage`, and deleting an organization through the API is blocked (use the
  deletion request). Number-scoped members (`crm.member_address_access`) see only their
  numbers. Internal `local` chat is exempt.
- **Lead scope** (`own | team | all`) is stored on roles and members; the pipeline phase
  enforces it.
- **Packs**: definitions in `packs/<key>/v<n>.json`, validated by `scripts/crm/pack.ts`
  and published by a generated migration. A new organization gets the default pack's
  latest version. Items live in `crm.organization_pack_items`; an item is customized
  when the tenant's `value` differs from `pack_value`, and upgrades never overwrite
  customized items.

## Rules the member functions enforce

`crm.invite_member`, `crm.set_member_role`, `crm.deactivate_member`,
`crm.set_role_permission`, `crm.reset_role_permissions`, `crm.set_member_*`:

- the caller needs the permission (`members.invite`, `members.manage`, `roles.manage`);
- nobody acts above their own tier (an admin cannot invite, change or deactivate an owner,
  or grant the Owner role); only owners edit a role at their own tier;
- nobody grants a permission they do not hold, and no permission goes below its
  `min_tier`;
- the last owner cannot be demoted (upstream guard).

## Audit log (P1-08)

`crm.audit_log` records who changed what, per organization. Schema: `10-05_audit_log.sql`,
`10-14_audit.sql`, `10-21_audit_triggers.sql`. Tests: `crm_05_audit.test.sql`.

- **What is logged** (by triggers, so every path is covered: crm functions, upstream screens,
  API keys, the platform): organization created / profile changed / suspended / reactivated /
  deletion requested or cancelled / 2FA requirement; members joining, deactivated, reactivated,
  role and lead-scope changes, permission overrides, number access; role permission toggles;
  invitations created, accepted, rejected, revoked; pack applied, upgraded, items edited or reset.
  Actions are named `area.verb` (`member.role_changed`); the full list is at the top of
  `10-21_audit_triggers.sql`.
- **Who acted**: `crm.write_audit` works it out from the request: a signed-in member (`user`, with
  their agent id), an API key (`api_key`, the key's id, never the key), the platform
  (`service`), or nothing (`system`: seeds, migrations, SQL console).
- **What is stored**: ids, keys and the changed fields (before/after). Never message text, contact
  phone numbers or tokens. Invitation entries keep the invitee's email; number-access entries keep
  the organization's own business number.
- **Append-only**: API roles hold `select` only; a trigger refuses update, delete and truncate even
  for the table owner. `crm.purge_organizations` is the one exception: a purged organization's
  entries go with it (DPDP erasure). Deleting an organization any other way fails while it has
  entries.
- **Reading**: members holding `audit.view` (Owner and Admin by default) through RLS, or
  `crm.get_audit_log(org, before_id, limit, area, actor, from, to)`, which pages and adds names.
  API keys cannot read it. UI: Settings → Activity log.
- **Writing from later phases**: database changes get a trigger in `10-21`; events the database
  cannot see (token connects, exports) call `crm.write_audit(org, action, target_type, target_id,
  details)` from an edge function with the service role. Members and API keys cannot call it.
- Setting up a new organization's preset roles is not logged permission by permission
  (`crm.audit_suppress`); the organization's creation is one entry.

## Settings engine and teams (P1-04)

Schema: `10-06_teams.sql`, `10-07_settings.sql`, `10-15_settings.sql`,
`10-22_settings_triggers.sql`. Catalog: `20261020220553_crm_settings_catalog.sql`. Tests:
`crm_06_settings.test.sql`. UI: Settings → Rules & modules.

- **Layers**: a setting's effective value comes from the most specific layer that has one:
  **user → team → organization → pack → platform default**. A **locked** setting always uses
  the platform default.
- **Catalog** (`crm.setting_definitions`): key, category, label, a JSON Schema subset for valid
  values (`crm.validate_setting_value`: type, enum, min/max, lengths, pattern, items,
  properties, required, `additionalProperties: false`, and our `mustContain`), platform
  default, allowed scopes, lock, edit permission, and the pack item (and path inside it) that
  is its pack layer.
- **Pack layer**: read from `organization_pack_items.pack_value`, so a pack upgrade changes the
  pack layer and never an organization's own value. A pack value that fails the schema is
  ignored (the platform default applies). Compliance and module pack items can no longer be
  edited directly; organizations change them through settings.
- **Locked compliance minimums** (approved 2026-10-21): marketing needs recorded opt-in; AI and
  news content need approval; STOP and UNSUBSCRIBE are always opt-out keywords (organizations
  may add more).
- **Teams** (`crm.teams`, `crm.team_members`; `crm.create_team`, `rename_team`, `delete_team`,
  `set_team_member`, all needing `members.manage`). A member in several teams that set
  different values gets the organization value, and `get_settings` reports `team_conflict`.
- **Reading**: `crm.get_setting(org, key)` for members and API keys of an active organization
  (with their own team/user layers); the platform (service role) may pass the member to
  resolve for: `crm.get_setting(org, key, agent_id)`. This is what the send path will call.
  `crm.get_settings(org)` lists everything with value, source and `can_edit` for the screen.
- **Writing**: `crm.set_setting(org, key, value, scope = 'tenant', target = null)` and
  `crm.reset_setting(...)`. Organization and team values need the setting's
  `edit_permission`; members set their own user values freely. Every change is audited
  (`setting.changed` / `setting.reset`, with before and after).
- **Adding a setting**: a new migration inserting into `crm.setting_definitions`. The first
  catalog has organization-level settings only; team/user scopes are tested with a test-only
  definition.

## Operations

| Task | How |
|---|---|
| Suspend / reactivate a tenant | `select crm.suspend_organization('<org>', 'reason');` / `crm.reactivate_organization('<org>')` as service_role (super-admin console in P1-10). |
| Hard delete | Owners request it in the UI (`crm.request_organization_deletion`); after 30 days the daily cron `crm-purge-deleted-organizations` runs `crm.purge_organizations()`. |
| Add a permission | New migration: insert into `crm.permissions`, into `crm.preset_role_permissions` for presets that should have it, and into `crm.role_permissions` for every org's `owner` role (snippet at the top of `20261020180500_crm_permission_catalog.sql`). |
| Publish a pack version | Add `packs/<key>/v<n+1>.json`, run `deno run --allow-read --allow-write scripts/crm/pack-to-sql.ts packs/<key>/v<n+1>.json`. Tenants upgrade with `crm.upgrade_organization_pack`. Never edit a published file: the migration refuses a changed checksum. |

## Before deploying to staging or production

1. **Expose the `crm` schema** in the dashboard (Settings → API → Exposed schemas). CI
   deploys migrations, not `config.toml`.
2. **Set `CRM_APP_URL`** (the UI's URL) for the `crm-invitations` function; it is the
   invite email's redirect and must be in Auth → URL Configuration → Redirect URLs.
3. **Email templates**: paste `supabase/templates/invite.html` and `magic_link.html` into
   Auth → Email Templates (Invite user, Magic Link), with the subjects from `config.toml`.
   Their links go to `<Site URL>/auth/confirm`, so the Site URL must be the UI's URL.
   Without them, invite links land on the login page instead of signing people in.
4. **Configure SMTP** (Auth → SMTP) with the transactional email domain; the built-in
   mailer is rate-limited and not for production.
5. **Review `20261020180900_crm_purge_organizations_cron.sql`**: it schedules irreversible
   deletion of organizations whose owners requested it 30+ days earlier.
6. Existing organizations are backfilled by `20261020180800_…`: owners become Owner,
   admins Admin, and plain members **Sales Rep**, so nobody loses what they could do
   before. Owners should then narrow roles (e.g. Viewer, Finance) where needed.
7. Legal review of the pack's disclaimer text, banned phrases, quiet hours (21:00–09:00)
   and the marketing frequency cap before the first tenant uses them.

## Known gaps

- **2FA**: the database gate (`require_mfa_for_admins`) is done and tested; there is no
  enrollment UI yet, so the setting is not exposed in the UI (P1-11).
- **Batch scope**: "batch assignment" waits for the batches table (Phase 6).
- **Audit**: there is no retention limit and no per-person redaction yet. Erasing one person
  (DPDP, later phase) must also blank their email in invitation entries, which needs a second
  controlled exception to append-only, like the purge's.
- **Pack items** are stored generically; custom fields
  (P1-06), pipeline and template phases read their kind from `organization_pack_items`.
