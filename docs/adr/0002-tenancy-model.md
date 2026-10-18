# ADR 0002 — Tenancy model: extend OpenBSP organizations

| | |
|---|---|
| Status | **Accepted** (2026-10-18). The suspension check, permission policies, delegated invites and 2FA gate were approved for Phase 1. |
| Date | 2026-10-18 |
| Task | P0-03 (unblocks P1-01, P1-02, P1-03, P1-12) |
| Inputs | [audit.md](../audit.md) §3, §5, §7; ROADMAP §1 (Tenancy, Roles), §5, Phase 1 |

## Context

The roadmap needs strict tenant isolation, eight preset roles with per-tenant toggles and
resource scopes, vertical packs, layered settings, a tenant timezone and a suspend state. It
prefers extending what exists unless the audit shows it blocks roles or packs.

The "draft migration written earlier in chat" named in P0-03 is **not in either repo**. This
ADR does not depend on it. If you still have it, I'll compare it against this proposal before
P1-01.

What OpenBSP already has (audit §3):

- `organizations` is the tenant. **Every** tenant-owned table carries `organization_id`: the
  other 11 public tables and the per-org billing tables.
- Isolation is enforced by RLS: almost all of the 53 policies (46 calls) go through one helper,
  `get_authorized_orgs(role)`. It resolves orgs from the user's JWT (via `agents`) or from an
  `api-key` header (via `api_keys`).
- Membership is the `agents` row: one per user per org, soft-deleted, protected by
  last-owner and owner-erasure triggers, with invitations in their own table. AI agents are
  `agents` rows with no `user_id`.
- Roles are a 3-value enum `owner > admin > member`, compared as ordinals. It is used by
  `get_authorized_orgs`, `api_keys.role`, `invitations.role`, `agents.role`, the edge-function
  middleware `requireRoles()` and the UI.
- `billing.subscriptions/usage/ledger` are keyed by `organization_id`.
- The UI already has an active-organization switcher.

## Options

### A. Extend `organizations` as the tenant (recommended)

`organizations` **is** the tenant. Our tables use `organization_id` as the tenant key. Phase 1
adds our own tables beside the upstream ones. Upstream policies keep working unchanged; our
own policies use a new permission helper.

### B. New `tenants` table beside `organizations`

A `tenants` table, plus a mapping from organizations to tenants or one-to-one sync triggers.
This creates two sources of truth for membership and isolation. Every upstream policy would
still check `organization_id`, so the new table would add a join and a second place for
isolation bugs, and would give us nothing the org table can't hold.

### C. Rename `organization_id` to `tenant_id` (or alias it with views)

A rename touches every upstream schema file, every future generated migration, `db_types.ts`,
every edge function and the UI. That breaks every upstream merge. Views or generated
columns named `tenant_id` add a layer that RLS and PostgREST writes don't map onto cleanly.

| | A. Extend | B. New table | C. Rename / alias |
|---|---|---|---|
| Upstream merge cost | Low | Medium | **Very high** |
| Isolation sources of truth | 1 | **2** | 1 |
| Reuses members, invitations, last-owner guard, billing, UI switcher | Yes | Partly | Yes, after rewrite |
| Blocks roles/packs? | No (see below) | No | No |
| Phase 1 effort | Lowest | Medium | Highest |

**Does the existing model block roles or packs?** No, but the role enum can't express the
eight roles. The ordinal enum is fine as a coarse **access tier**. Fine-grained permissions
go in our own tables and a separate helper, so the enum doesn't need replacing.

## Decision (proposed): Option A

1. **The tenant is `public.organizations`.** In our code and docs, "tenant" means
   organization and the tenant key is the column `organization_id`. Every new tenant-owned
   table we add has `organization_id uuid not null references public.organizations(id)`, RLS
   enabled, and a cross-tenant test.
   - This conflicts with the CLAUDE.md wording "every tenant-owned table has `tenant_id`".
     **Proposed CLAUDE.md amendment** (not made; needs your approval): "every tenant-owned
     table has `organization_id` (our tenant key)…".
2. **Tenant profile and lifecycle (P1-01).** New 1:1 table (name to be finalised in P1-01,
   e.g. `crm.organization_profiles`): `slug` (unique), `timezone` (default `Asia/Kolkata`),
   `locale`, `status` (`active | suspended | pending_deletion`), `suspended_at`,
   `deletion_requested_at`, pack reference. It is created by our own trigger on organization
   insert (no edit to the upstream trigger).
3. **Suspension must cut access everywhere.** The one place that sees every request is
   `get_authorized_orgs`. Proposal: **one small upstream edit** there, adding a "not
   suspended" filter, logged in `docs/upstream-edits.md`. The alternative (adding the check to
   46 policies) is worse for merges. Platform super-admins bypass it via a separate path
   (P1-10).
4. **Membership stays `agents`.** A member is an `agents` row with `user_id` set and
   `deleted_at` null. AI agents stay `agents` rows with `user_id` null. Invitations reuse
   `public.invitations` and `accept_invitation()`.
5. **Roles and permissions (P1-02), in our own schema.**
   - `permissions` (catalog), `roles` (eight presets + per-tenant copies), `role_permissions`,
     `member_roles` (agent → role), `member_permission_overrides`, `member_scopes` (numbers =
     `organizations_addresses`, batches, own vs team leads).
   - Helper `has_permission(org_id uuid, perm text) returns boolean`: `security definer`,
     `stable`, `search_path ''`. It resolves the caller through `get_own_agents()` (or the API
     key) and is used by every **new** policy.
   - **Tier mapping keeps upstream policies correct.** A trigger sets the upstream
     `agents.role` from the preset role: Owner → `owner`, Admin → `admin`, all others
     (Sales Manager, Sales Rep, Marketing, Teacher, Finance, Viewer) → `member`. Upstream
     tables (conversations, messages, contacts…) then behave as today. Their finer rules
     (e.g. a Viewer must not send messages, a Rep sees only assigned conversations) are
     added as **extra restrictive policies** in our own schema files, not by editing upstream
     policies. Postgres combines `as restrictive` policies with AND.
   - The upstream `role` enum is **not** replaced or removed (removing it would break merges).
     P1-02's "replace any placeholder role enum" means our earlier drafts' enum, not this
     one.
   - Edge functions: our `crm-*` functions check `has_permission`. Upstream `requireRoles()`
     keeps working on the tier.
6. **API keys.** Keep `api_keys` for upstream compatibility; it maps to the tier. Scoped,
   hashed agent and API keys come in P9-01 as our own table. Until then, keys are issued only
   internally.
7. **Packs and settings (P1-04, P1-05)** hang off `organization_id` in our own tables.
   Nothing upstream blocks them. `organizations.extra` is **not** used for our settings
   (it's untyped, and upstream merges into it with `merge_update`).
8. **Where our schema lives.** Declarative files in `supabase/schemas/10_crm/**` (after
   upstream's `06_billing`). Our tables go in a dedicated `crm` schema, exposed to PostgREST
   only where the UI needs them. Migrations are generated with `supabase db diff` and named
   `<timestamp>_crm_<topic>.sql`. The exact schema exposure is decided in P1-01.
9. **Platform super-admin (P1-10)** is not an organization role. It's a separate
   `platform_admins` table and helper, with time-limited, logged support-access grants. It is
   never implemented by giving someone `owner` in a tenant.

## Consequences

**Good**
- One source of truth for isolation. The 53 existing policies and the upstream triggers
  (last-owner, soft delete, identity freeze) keep protecting us.
- Upstream merges stay cheap: one planned edit (`get_authorized_orgs`) plus additive files.
- Billing, the UI org switcher and invitations work for us from day one.

**Costs and risks**
- Two authorisation layers (upstream tier + our permissions). Each permission needs a
  documented tier floor, and P1-12 must test both layers together.
- The naming differs from the roadmap's `tenant_id`, so docs and CLAUDE.md must say so clearly.
- Mapping six roles to `member` means an upstream table is only as tight as our restrictive
  policies make it. Each upstream table needs a review in P1-02 for what `member` can do
  (e.g. `contacts_addresses` insert, `local` conversations from `anon`, per the upstream
  TODO).
- `get_authorized_orgs` grows by one join; measure it in P11-02.

**Follow-ups**
- [ ] Your approval of this ADR and of the CLAUDE.md wording change
- [ ] P1-01: profile table, lifecycle, the `get_authorized_orgs` suspension edit (+ `docs/upstream-edits.md`)
- [ ] P1-02: permission tables, `has_permission`, tier-mapping trigger, restrictive policies per upstream table
- [ ] P1-12: RLS test suite covering both layers, starting with the 12 upstream public tables
- [ ] P2-03 (security, before any external tenant): move tokens out of `organizations_addresses.extra` (audit §1)
