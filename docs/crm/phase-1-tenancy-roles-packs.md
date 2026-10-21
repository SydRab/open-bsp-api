# Phase 1: tenancy, roles, invitations, vertical packs

Covers P1-01 to P1-10. Design: [ADR 0002](../adr/0002-tenancy-model.md).
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

## Business details and disclaimers (P1-07)

Schema: `10-02` (columns), `10-08_disclaimers.sql`, `10-16_disclaimers.sql`,
`10-23_disclaimer_triggers.sql`. Tests: `crm_07_disclaimers.test.sql`. UI: Settings →
Organization (business details) and Settings → Disclaimer.

- **Business details** on `crm.organization_profiles`: `legal_name`, `address`
  (line1, line2, city, state, postal_code, country), `support_email`, `support_phone`,
  `website`, `registrations` (`gstin`, `sebi_ra`, `sebi_ia`, `cin`, `udyam`, `other`). The
  validation trigger trims, uppercases registration numbers and checks official formats.
  Edited with `organization.manage`; changes are audited. Shown on public pages and receipts,
  **not** in WhatsApp messages (decided 2026-10-21; a SEBI number goes into messages only if
  legal counsel requires it).
- **Disclaimers** (`crm.disclaimer_versions`): short (10–60 characters, one line, fits a
  template footer) and full (20–1000) per language (`en`, `hi`). Every save adds a version;
  the pack's text (version 0) applies until the first save. `crm.get_disclaimers(org)`,
  `crm.set_disclaimer(org, kind, locale, text)` (`organization.manage`). Audited as
  `disclaimer.updated` with the text replaced.
- **`crm.render_with_disclaimer(org, content_type, text, locale)`** — the one function every
  sender calls; it returns the text to send and the disclaimer version used (store it with the
  message as proof).

  | Content type | Disclaimer | When |
  |---|---|---|
  | `broadcast`, `digest`, `ai_message`, `payment_confirmation` | short | per `disclaimer.attach_rules` |
  | `receipt` | full | per `disclaimer.attach_rules` (off by default) |
  | `public_page`, `disclaimer_reply` | full | always |

  Language: the one given, else the organization's, else English. Never adds the disclaimer
  twice. Refuses messages over WhatsApp's 4096 characters and content that needs a disclaimer
  the organization does not have.
- **Templates**: Meta approves a template's footer in advance. The Disclaimer page shows how
  many pack templates carry the short disclaimer as footer; re-submitting them after a change
  is P2-04.

## Contacts and custom fields (P1-06)

Schema: `10-09_contacts.sql`, `10-17_custom_fields.sql`, `10-24_contacts_triggers.sql`.
Tests: `crm_08_custom_fields.test.sql`. UI: Settings → Custom fields; contact page → Details.

- **Person-level contacts** (`crm.contacts`, `crm.contact_addresses`): one person per
  (organization, service, address), whichever of the organization's numbers they wrote to.
  Created by a trigger on `public.contacts_addresses` (named from the channel's profile name),
  backfilled by `20261021082015_crm_backfill_contacts.sql`. Internal chat (`local`) has none.
  Cross-channel merging (WhatsApp + Telegram) is P3-02 / P7-02.
- **Visibility**: `contacts.view` and at least one of the person's upstream contact rows visible
  to the caller — the check runs under the caller's own RLS on `public.contacts_addresses`, so
  number scope and personal connections apply exactly as upstream.
- **Definitions** are `organization_pack_items` of kind `custom_field`: the pack's fields plus the
  organization's own (no `pack_value`). Types: text, long_text, number, date, boolean, select,
  multi_select, email, phone, url. Managed only through `crm.create_custom_field`,
  `update_custom_field` (labels, required, options), `archive_custom_field`
  (`organization.manage`); direct edits are blocked. Keys and types never change; fields and
  options are archived, never removed. Audited as `custom_field.created/updated/archived/
  restored`. Pack upgrades keep an organization's edits (the usual customized-item rule).
- **Values**: `crm.contacts.custom_fields` (jsonb, GIN-indexed), checked by a trigger on every
  write (known field, type, option, archived rules). `crm.set_contact_fields(contact, values)`
  is the form save: `contacts.edit`, merges values (null clears), enforces **required** — only
  here, so contacts created automatically by inbound messages are never blocked (decided
  2026-10-21). Value edits are not in the audit log (the contact timeline, P3-11, will show them).
- **Filters**: `crm.filter_contacts(org, conditions)` — conditions `{field, op, value}` with
  `eq, neq, in, contains, gt, gte, lt, lte, is_empty, is_not_empty`, combined with AND; runs as
  the caller (RLS applies). The base for segments (P4-03).
- **Templates**: `crm.format_custom_field(org, entity, key, value, locale)` turns stored values
  into display text (option labels in the contact's language; Yes/No, हाँ/नहीं).

## Feature flags and plan entitlements (P1-09)

Schema: `10-18_feature_flags.sql`, `10-19_feature_resolution.sql`, `10-25_member_seats.sql`,
`10-26_feature_audit_triggers.sql`. Catalog: `20261021112530_crm_feature_catalog.sql`.
Tests: `crm_09_feature_flags.test.sql`. UI: Settings → Plan & features; locks on Rules & modules.

- **`crm.features`** is the platform catalog — today the eleven modules, same keys and labels
  as the `modules.*` settings (P1-04). Each has a **kill switch**
  (`crm.set_feature_kill_switch`, platform only, emergency off for everyone — not org-scoped,
  so not in the audit log).
- **`crm.tier_features`** maps a billing tier (`billing.subscriptions.tier_id`) to the features
  it includes. **No foreign key to `billing.tiers`**: that catalog is environment data
  (`billing.tiers`/`products`/`tiers_products` live only in `supabase/seed.sql`, confirmed by
  hand — a migration-time insert FK'd to `billing.tiers('free')` fails, since migrations run
  before seed.sql), so `crm.tier_features` works with whatever tier ids
  `billing.subscriptions` actually carries.
- **`crm.organization_features`** holds per-tenant overrides (a beta, a comp, a block), with a
  reason and an optional expiry — platform only
  (`crm.set_organization_feature`/`clear_organization_feature`), audited.
- **`crm.has_feature(org, key)`** resolves **kill switch → override → tier**; an organization
  with **no subscription at all** gets every feature (the same fallback `billing.check_limit`
  uses for usage caps). `crm.require_feature` raises "your plan does not include …".
  `crm.get_features(org)` adds `source` and, for a feature not included, the lowest tier that
  would unlock it — the resolver the UI uses.
- **Modules are plan × switch**: `crm.set_setting` refuses turning a `modules.<key>` setting on
  when `crm.has_feature(org, key)` is false; turning one off and resetting are unaffected. A
  pack can still default a module's *setting* to true regardless of tier (the Trading
  Institute pack does, for several Starter-only modules) — the feature layer is what actually
  gates it; Rules & modules shows the switch locked either way.
- **Tiers** (approved 2026-10-21): **Free** = inbox, contacts, pipeline. **Starter** adds
  broadcasts, sequences, webinars, payments, classroom, telegram. **Pro** (new
  `billing.tiers` row, level 2, no price — pricing is a business decision) adds ai_agents,
  news_digest.
- **Member seats** reuse billing's usage/cap machinery: a new `members` product (`billing.products`,
  kind `gauge`), with caps in `supabase/seed.sql` (free 3, starter 10 — same no-FK reason as
  `crm.tier_features`; Pro has no row, meaning unlimited). `crm.track_member_usage`
  (`public.agents`, mirrors `billing.update_account_usage`) keeps the gauge in step with active
  human members (`user_id` set, `deleted_at` null) and checks the cap on any new-or-revived
  active member — including revival, unlike a reconnecting WhatsApp account, since a person is
  always available to tell "no". `crm.invite_member` checks the cap early too, for a friendly
  error at invite time; the trigger is what actually enforces it. A backfill migration seeded
  correct usage for organizations that already had members.

## Super-admin console (P1-10)

Schema: `10-27_admin.sql`, `10-28_admin_resolution.sql`, `10-29_admin_triggers.sql`. Edge
function: `supabase/functions/crm-admin/`. Tests: `crm_10_admin_console.test.sql`.

- **A platform admin is a separate axis from tenant roles**: `crm.platform_admins` (global,
  not tied to any organization). Being an owner or admin of a tenant grants nothing here, and
  being a platform admin grants nothing inside a tenant beyond what this section defines.
- **Every admin action goes through `crm-admin`** (`POST /functions/v1/crm-admin`,
  `{ "action": "<name>", ... }`), never a crm function granted to `authenticated`. The function
  verifies the caller's own JWT, self-checks `crm.is_platform_admin()` with the caller's own
  client, and only then switches to the service role. A non-admin or unauthenticated caller
  never reaches a database function at all.
- **Bootstrapping the first admin is manual, on purpose** — see "Operations" below. Every admin
  after that is granted through the console by an existing one (`crm.grant_platform_admin`, by
  email). The last admin cannot be revoked.
- **Tenant list**: `crm.list_tenants(search)` — name, slug, status, tier, seat usage/cap, pack
  and its latest available version.
- **Two functions exist only because a bare service-role call fails otherwise** — confirmed by
  hand, see the comment at the top of `10-28_admin_resolution.sql`:
  `crm.require_permission` (and so `crm.get_settings`'s own `can_edit` column) ultimately calls
  `public.get_authorized_orgs`, which raises `"authentication required"` with no JWT and no
  api-key header. `crm.set_organization_tier` and `crm.admin_upgrade_organization_pack` are
  thin, admin-gated replacements for the two tenant-facing actions this console needs
  (`billing.subscriptions` has no tenant-facing setter anyway; `crm.upgrade_organization_pack`
  does, gated by `organization.manage`). Everything else the console needs
  (`crm.get_features`, `crm.apply_pack`, `suspend_organization`, `set_organization_feature`,
  `set_feature_kill_switch`, …) already tolerates a bare service-role caller.
- **Time-limited, logged support-access grants** (`crm.support_access_grants`, 1 hour to 1
  week): `crm.grant_support_access`/`revoke_support_access`. While active, an admin may call
  `crm.admin_get_tenant_config` (profile, resolved settings, roles and their permissions,
  feature status, pack items) and `crm.admin_get_audit_log` for that one organization —
  **deliberately never message or contact content**. The organization can see grants made
  against it (`crm.support_access_grants` RLS) and the grant/revoke in its own audit log.
- **`crm.platform_audit_log`** is a second, separate append-only log (not organization-scoped,
  so it is not `crm.audit_log`) for actions with no single tenant — admin grants/revokes, the
  kill switch — and also records which admin did something to one organization (tier changes,
  pack upgrades, suspensions, feature overrides), alongside that organization's own entry.

## Operations

| Task | How |
|---|---|
| **Bootstrap the first platform admin** | One-time, by hand, as a human running SQL against the target environment (never a migration, never a UI action): `insert into crm.platform_admins (user_id) values ((select id from auth.users where email = '<your email>'));` |
| Everything else admin-console-related | Through the console (`crm-admin`), once signed in as a platform admin: list tenants, suspend/reactivate, grant/clear a feature override, flip the kill switch, change an organization's tier, upgrade its pack, grant/revoke support access, read a supported organization's configuration and audit log, grant/revoke another platform admin. |
| Suspend / reactivate a tenant without the console | `select crm.suspend_organization('<org>', 'reason');` / `crm.reactivate_organization('<org>')` as service_role. |
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
8. **Seed the billing catalog** (`billing.tiers`, `products`, `tiers_products`, `plans`):
   today it exists only in `supabase/seed.sql`, which production never runs. Without it, every
   organization resolves as "no subscription" — unrestricted features, no seat cap.
9. **Bootstrap the first platform admin**: `insert into crm.platform_admins (user_id) values
   ((select id from auth.users where email = '<your email>'));` — by hand, once, as whoever is
   setting up the environment. Every admin after that is granted through the console.

## Known gaps

- **2FA**: the database gate (`require_mfa_for_admins`) is done and tested; there is no
  enrollment UI yet, so the setting is not exposed in the UI (P1-11).
- **Batch scope**: "batch assignment" waits for the batches table (Phase 6).
- **Audit**: there is no retention limit and no per-person redaction yet. Erasing one person
  (DPDP, later phase) must also blank their email in invitation entries, which needs a second
  controlled exception to append-only, like the purge's.
- **Pack items** are stored generically; pipeline stages, qualification questions and
  templates are read from `organization_pack_items` by the pipeline and template phases.
- **Billing catalog**: `billing.tiers`/`products`/`tiers_products`/`plans` exist only in
  `supabase/seed.sql` (dev data) except the rows P1-09 added by migration (`pro` tier,
  `members` product). Staging/production need this catalog seeded out of band before tier
  assignment or seat caps mean anything there; until then every organization resolves as
  "no subscription" (every feature unrestricted, no seat cap).
- **Support access is configuration/audit-only**: a grant does not unlock message or contact
  content; reading actual conversations for support is a separate, later decision (noted
  2026-10-21 when P1-09's "configuration and audit log, never content" scope was approved).
- **No way yet to downgrade a module an organization already turned on** when its tier changes:
  a pack-defaulted module that was true stays true in its own setting row even after
  `crm.set_organization_tier` moves the organization to a plan that no longer includes it;
  `crm.has_feature` already reports it as unavailable, and Rules & modules already shows it
  locked, so nothing is actually usable — but the stored `true` could confuse a future reader
  that only checks the setting, not the feature.
