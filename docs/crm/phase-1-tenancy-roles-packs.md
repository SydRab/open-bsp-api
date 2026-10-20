# Phase 1: tenancy, roles, invitations, vertical packs

Covers P1-01, P1-02, P1-03 and P1-05. Design: [ADR 0002](../adr/0002-tenancy-model.md).
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
3. **Configure SMTP** (Auth → SMTP) with the transactional email domain; the built-in
   mailer is rate-limited and not for production.
4. **Review `20261020180900_crm_purge_organizations_cron.sql`**: it schedules irreversible
   deletion of organizations whose owners requested it 30+ days earlier.
5. Existing organizations are backfilled by `20261020180800_…`: owners become Owner,
   admins Admin, and plain members **Sales Rep**, so nobody loses what they could do
   before. Owners should then narrow roles (e.g. Viewer, Finance) where needed.
6. Legal review of the pack's disclaimer text, banned phrases, quiet hours (21:00–09:00)
   and the marketing frequency cap before the first tenant uses them.

## Known gaps

- **2FA**: the database gate (`require_mfa_for_admins`) is done and tested; there is no
  enrollment UI yet, so the setting is not exposed in the UI (P1-11).
- **Batch scope**: "batch assignment" waits for the batches table (Phase 6).
- **Audit**: role changes, invitations and profile edits are not audited yet (P1-08).
- **Pack items** are stored generically; the settings engine (P1-04), custom fields
  (P1-06), pipeline and template phases read their kind from `organization_pack_items`.
- **Invite email**: the `crm-invitations` function passes its unit tests, and the database
  side is covered by pgTAP. The full send-an-email run against the local stack was not
  completed (Docker stopped when C: ran out of space).
