# Edits to upstream OpenBSP files

Every change we make to a file that came from upstream OpenBSP is listed here, so upstream
merges can be resolved quickly. Our own code lives in `supabase/schemas/10_crm/`, `supabase/templates/`,
`supabase/functions/crm-*`, `supabase/tests/`, `packs/`, `scripts/crm/` and `docs/`. Those
need no entry.

| Date | File | Change | Why | Task |
|---|---|---|---|---|
| 2026-10-21 | `supabase/schemas/04_functions_post_tables/04-01_auth_helpers.sql` | `get_authorized_orgs`: both branches (JWT and API key) skip organizations whose `crm.organization_profiles.status` is not `active`. Marked `[crm]`. | One place that cuts access for suspended or pending-deletion tenants across all 53 upstream policies (ADR 0002 §3). | P1-01 |
| 2026-10-21 | `supabase/seed.sql` | Contacts block: dropped the insert into `public.contacts` and `contact_id`, added `organization_address`. | Upstream bug: the seed still used `public.contacts`, which `20260823180340_drop_contacts` removed, so `supabase start`/`db reset` failed. Worth sending upstream. | P1-01 |
| 2026-10-21 | `supabase/config.toml` | `[api] schemas` gains `crm`; new `[functions.crm-invitations]` block. | Exposes the crm schema to PostgREST; registers our function. | P1-01, P1-03 |
| 2026-10-21 | `supabase/functions/_shared/db_types.ts` | Regenerated (generated file). Now includes the `crm` schema; the CLI (2.121) emits a newer layout (`ComputedFields`). | Types for the crm schema. `deno check` passes. | P1-02 |
| 2026-10-21 | `supabase/functions/deno.lock` | Adds `jsr:@std/assert` (test-only dependency). | Unit tests for `crm-invitations`. | P1-03 |
| 2026-10-21 | `supabase/functions/_shared/db_types.ts` | Regenerated again: adds `crm.audit_log`, `get_audit_log`, `write_audit`. | Audit log types. | P1-08 |
| 2026-10-21 | `supabase/config.toml` | `[auth.email.template.invite]` and `[auth.email.template.magic_link]` point at `supabase/templates/*.html` (new, ours). | Email links go to the UI's `/auth/confirm` with a token hash; the default links' fragment tokens are rejected by the UI's PKCE client. | P1-03 |
| 2026-10-21 | `supabase/functions/_shared/db_types.ts` | Regenerated: adds `crm.get_my_invitation_roles`. | Invitation card role name. | P1-03 |
| 2026-10-21 | `supabase/functions/_shared/db_types.ts` | Regenerated: settings and teams. | Types. | P1-04 |
| 2026-10-21 | `supabase/functions/_shared/db_types.ts` | Regenerated: business details, disclaimers. | Types. | P1-07 |
| 2026-10-21 | `supabase/functions/_shared/db_types.ts` | Regenerated: contacts, custom fields. | Types. | P1-06 |
| 2026-10-21 | `supabase/seed.sql` | Adds `members` seat caps (free 3, starter 10) to the `billing.tiers_products` insert block. | Same reason as `crm.tier_features` carrying no foreign key to `billing.tiers` (10-18): those tier rows exist only here, so a migration-time insert referencing them fails. | P1-09 |
| 2026-10-21 | `supabase/functions/_shared/db_types.ts` | Regenerated: feature flags, `billing.tiers` Pro row, `members` product. | Types. | P1-09 |
| 2026-10-21 | `supabase/config.toml` | New `[functions.crm-admin]` block. | Registers the super-admin console's edge function. | P1-10 |
| 2026-10-21 | `supabase/functions/_shared/db_types.ts` | Regenerated: platform admins, platform audit log, support-access grants. | Types. | P1-10 |
| 2026-10-22 | `supabase/functions/whatsapp-webhook/index.ts` | Rewritten (first edit): now only verifies the signature (constant-time), hashes the body, writes a raw `crm.webhook_events` row, and acks. All parsing/DB-write logic moved verbatim to `_shared/whatsapp_webhook_processing.ts`. Pure helpers (`timingSafeEqualHex`, `sha256Hex`) split into a new sibling `lib.ts`/`lib_test.ts`. | A slow media download used to risk Meta's own delivery timeout on the webhook request itself; processing now runs async via a pg_cron-driven processor. Also fixes a timing side-channel in the signature comparison. | P2-01 |
| 2026-10-22 | `supabase/functions/_shared/types/whatsapp_webhook_payload_types.ts` | Added 4 webhook change variants: `message_template_status_update`, `message_template_quality_update`, `phone_number_quality_update`, `phone_number_name_update`, with their value shapes per Meta's docs. | These WABA-level events were previously unhandled; the roadmap's "quality/limit updates, account updates, name approvals" wording. | P2-01 |
| 2026-10-22 | `supabase/config.toml` | New `[functions.whatsapp-webhook-processor]` block. | Registers the async webhook-processing function, invoked only by pg_cron. | P2-01 |
| 2026-10-22 | `supabase/functions/_shared/db_types.ts` | Regenerated twice: `crm.webhook_events`, `purge_webhook_events`, then `claim_webhook_event`/`replay_webhook_event`. | Types. | P2-01 |
