# OpenBSP fork audit (P0-01)

| | |
|---|---|
| Date | 2026-10-18 |
| Backend fork | `api/api` = `SydRab/open-bsp-api`, branch `main`, commit `22358fd` (2026-10-17) |
| Frontend fork | `ui/ui` = `SydRab/open-bsp-ui`, branch `main`, commit `735e00d` (2026-10-08) |
| Method | Read-only inspection of schema files, edge functions, UI routes, CI and upstream docs. Nothing was run, installed or changed. |
| Related | [ADR 0001 — License](adr/0001-license.md), [ADR 0002 — Tenancy model](adr/0002-tenancy-model.md) |

---

## 1. Summary

OpenBSP is a solid multi-tenant messaging core. It already has organizations, members with
roles, invitations, RLS on every table, a WhatsApp Cloud API webhook and dispatcher, Embedded
Signup, template management, an AI agent runner, an MCP server, a billing schema and a React
inbox UI. **It has no CRM layer at all**: no pipeline, deals, campaigns, consent, sequences,
webinars, payments, classroom or Telegram.

The plan is to **extend the messaging core and build the CRM layer beside it**. Three things
must be fixed before any real tenant connects a number (all Phase 2, flagged for approval
because they touch tokens and sending):

1. **Critical: WhatsApp and Instagram access tokens are readable by every org member.**
   Tokens are stored in plain text in `organizations_addresses.extra.access_token`. The table's
   only SELECT policy lets any `member` (and any member-level API key) read the whole row, and
   the UI shows the token on the WhatsApp integration page
   (`ui/src/routes/_auth/integrations/whatsapp/$orgAddressId/index.tsx:151`). This breaks the
   CLAUDE.md secrets rule. Fix in P2-02/P2-03: move tokens to Vault, keep only the secret id.
2. **The send path has no policy checks.** All outbound messages already go through one choke
   point (insert into `messages` → trigger → `{service}-dispatcher`), which is good. But nothing
   checks the 24h window, opt-in/opt-out, quiet hours, frequency caps, disclaimers or approvals.
   Fix in P2-05 by adding the policy gate in front of the dispatcher.
3. **The webhook is processed inline, with no raw event log.** The signature is verified on
   the raw body (good), but the compare is not constant-time, and all processing runs inside
   the HTTP request. Fix in P2-01.

Other notable points:

- **The WhatsApp-Web (whatsmeow) bridge is an unofficial WhatsApp client.** CLAUDE.md bans it.
  Decision: **disable it, but keep the files** so upstream merges stay clean (see §6).
- **There are no automated tests** in either repo: no Deno tests, no SQL/RLS tests, no UI tests.
  CI runs only `deno fmt/lint/check`. The P1-12 RLS test suite starts from zero.
- **API keys are stored and compared in plain text** (`api_keys.key`). Upstream lists
  "Encrypt API keys" in its TODO. P9-01 replaces this with hashed keys.
- **The logger does no redaction.** `_shared/logger.ts` prints whatever it is given, and the
  webhook logs the received and expected signature on failure. P0-09 needs a scrubbing logger.
- **The UI's source language is Spanish.** Spanish strings are the i18n keys, with locale
  files for en/fr/pt/sw. Hindi must be added, and English should become the default (P1-11).

---

## 2. Stack

| Layer | What is there |
|---|---|
| Backend runtime | Deno 2 edge functions on Supabase, Hono router in the management functions |
| Database | Postgres with a **declarative schema** (`supabase/schemas/**`). Migrations (113) are **generated** with `supabase db diff`, not hand-written, except for cron jobs, enum additions and data backfills (see upstream `CLAUDE.md`). |
| Extensions | `pg_cron`, `pg_net`, `supabase_vault`, `pgcrypto`, `moddatetime`, `pg_graphql`, `pg_stat_statements`, `uuid-ossp`. **No `pgmq` and no `pgvector` yet.** |
| Realtime | `conversations` and `messages` are in the `supabase_realtime` publication |
| Frontend | React 19, TypeScript 5.9, Vite (rolldown-vite 7.2), TanStack Router (file routes) + TanStack Query, Zustand, **Ant Design 6** + Tailwind 4, react-hook-form, Recharts, dayjs, libphonenumber-js, DOMPurify. PWA manifest exists. |
| Frontend auth | Supabase JS client with the anon/publishable key only. **No service-role key in the UI** (checked). |
| CI | `check.yml`: `deno fmt --check`, `deno lint`, `deno check` (functions + plugin). `release.yml` is **manual only** (`workflow_dispatch`); deployment is via the Supabase GitHub integration. UI: `npm run check` (prettier, eslint, `tsc -b`). |
| Extras | `plugin/`: a Claude Code plugin/MCP client for the API. `openapi.json`: PostgREST API description. |

This also settles roadmap open decision #2 (frontend stack and component library): React 19 +
TanStack + Ant Design 6 + Tailwind 4.

---

## 3. Inventory

### 3.1 Tables (`supabase/schemas/03_models`, `06_billing`)

| Table | Purpose | Tenant key | RLS policies |
|---|---|---|---|
| `organizations` | The tenant. `id, name, extra jsonb`. Creating one auto-creates the first owner agent and a `local` address. | `id` | 4 (any user can create; members read; admins update; owners delete) |
| `agents` | **Membership row**: a human member (`user_id` set) or an AI agent (`user_id` null). `role` enum, `extra` (AI prompt/model/tools), soft delete via `deleted_at`. One row per user per org. | `organization_id` | 8 |
| `invitations` | Email invite with role and status | `organization_id` | 3 |
| `organizations_addresses` | A connected channel account (WhatsApp number, Instagram, Slack, local…). `extra` holds `waba_id`, `phone_number_id`, **`access_token`**. `agent_id` set = private account. | `organization_id` | 1 (members read; writes only via service role) |
| `contacts_addresses` | A contact's address on a service (phone, IG id…), per org address | `organization_id` | 4 |
| `conversations` | Thread between an org address and a contact address, with `type` (direct/group/channel) | `organization_id` | 4 |
| `conversations_agents` | Participants, for restricted conversations | `organization_id` | 4 |
| `messages` | All messages, both directions. `content jsonb`, `status jsonb`, `external_id` (WAMID) **unique globally** | `organization_id` | 2 |
| `api_keys` | Org API keys with role. **Plain-text `key`.** | `organization_id` | 3 |
| `webhooks` | Outbound webhooks per table and operation, with optional token | `organization_id` | 1 |
| `logs` | App-level logs and errors (level, category, metadata) | `organization_id` | 1 |
| `onboarding_tokens` | Shareable links for a third party to complete Embedded Signup into an org | `organization_id` | 3 |
| `storage.objects` | Media bucket, visibility tied to conversations | via path | 2 |
| `billing.products, tiers, tiers_products, plans, plans_products` | Platform catalog (limits per tier and plan) | — | in `06-20_rls.sql` (13 total) |
| `billing.accounts, subscriptions, usage, ledger, invoices, invoices_items, payments, costs` | Per-org subscription, usage counters, ledger, invoices | `organization_id` | (same) |

Enums (`01_types.sql`): `service` (whatsapp, instagram, local, slack, discord, teams,
whatsapp-web), `role` (owner, admin, member), `webhook_operation`, `webhook_table`, `log_level`.

### 3.2 SQL functions and triggers

| Group | Functions |
|---|---|
| Access helpers (`04-01`) | `get_authorized_orgs(role)` — **the tenant gate used by almost every policy**. Resolves orgs from the JWT via `agents`, else from the `api-key` header via `api_keys`, with an ordinal role check (owner 3 > admin 2 > member 1). Also `get_own_agents()`, `agent_identity_unchanged()`, `agent_identity_and_role_unchanged()`. |
| Visibility (`04-02`) | `get_visible_addresses()`, `get_participant_conversations()`, `get_restricted_conversations()`, `is_conversation_visible()`, `is_media_visible()`. Model: a shared account (no `agent_id`) is visible to the whole org; a personal account only to its owner; restricted conversations only to participants. |
| Invitations (`04-03`) | `accept_invitation()`, `reject_invitation()` |
| Integrity triggers (`02-03`) | `after_insert_on_organizations`, `prevent_last_owner_deletion`, `prevent_owner_user_deletion`, `preserve_agent_deletion`, `mark_agent_deleted`, `preserve_conversation_addressing`, `preserve_message_addressing`, `before_insert_on_messages`, `before_insert_on_conversations`, `after_insert_on_local_conversation`, `cleanup_removed_address_if_empty`, `before_insert_or_update_on_invitations`, `notify_webhook` |
| Edge-function bridges (`02-02`) | `dispatcher_edge_function()` (outbound send via `pg_net` to `/{service}-dispatcher`), `edge_function(path, method)` (agent-client, media-preprocessor), `local_message_to_agent()`. Edge URL and token are read from **Vault** (`edge_functions_url`, `edge_functions_token`). |
| Utilities | `merge_update_jsonb`, `merge_update` (jsonb `extra` merge on update), `init_data` |
| Billing (`06-30`) | `check_limit`, `update_usage`, `check_product_limit`, `update_product_usage`, `check_storage_limit`, `update_storage_usage`, `update_account_usage`, `guard_ledger_insert`, `process_ledger_entry`, `initialize_subscription` |

pg_cron jobs: `dispatch-outgoing-pending-messages` (every minute; retry sweep with backoff at
1, 2, 4, 8, 16 min, then every 30 min up to 12 h), `annotate-pending-messages` (media
preprocessing), `storage-gc-hourly`, `refresh-instagram-tokens` (daily), Slack token refresh.

### 3.3 Edge functions (`supabase/functions`)

| Function | Lines | Entry / routes | What it does |
|---|---|---|---|
| `whatsapp-webhook` | 1298 | `GET` verify (`hub.verify_token`), `POST` events | Verifies `X-Hub-Signature-256` (HMAC-SHA256 on the raw body); parses messages, statuses, edits, revokes; upserts contacts/conversations/messages; downloads media to Storage. **Inline processing, no raw event log, non-constant-time compare.** Dedupe relies on the unique `messages.external_id`. |
| `whatsapp-dispatcher` | 609 | `POST` from DB trigger / cron | Sends text, media, interactive and template messages via Graph API `v24.0`. Maps Meta error codes (131021/26/37/42/47, 132xxx). Uses the address token, or the platform `META_SYSTEM_USER_ACCESS_TOKEN` as fallback. |
| `whatsapp-management` | 1340 | `GET/POST /onboard`, `POST /onboard/events`, `POST /signup`, `PUT/POST/PATCH/DELETE /templates` | **Embedded Signup**: code → business token exchange, `subscribed_apps`, phone `register`, phone lookup, `smb_app_data` sync (coexistence), deregister and delete. **Templates**: list, fetch, create, edit, delete against Meta. |
| `instagram-webhook` / `-dispatcher` / `-management` | 1000 / 437 / 1062 | `/authorize-url`, `/onboard`, `/refresh-tokens`, `/deauthorize`, `/data-deletion` (+ status) | Instagram DM channel, OAuth, Meta data-deletion callbacks (signed_request HMAC) |
| `slack-webhook` / `-dispatcher` / `-management` | 1092 / 422 / 817 | `/authorize-url`, `/connect` (POST/DELETE), `/refresh-tokens`, `/sync` | Slack as an internal-comms channel |
| `generic-webhook` / `generic-dispatcher` | 556 / 223 | Deployed under a per-service slug (e.g. `whatsapp-web-webhook`) | Generic connector protocol for bridged services |
| `whatsapp-web-management` | 276 | `/sessions` (POST), `/sessions/pending/:id`, `/sessions/:address` (GET/DELETE), `/sessions/events` | Pairs and manages **whatsmeow** sessions on an external bridge — **unofficial, to be disabled** |
| `agent-client` | 1006 | `POST` from DB trigger | AI agent runner: on an inbound message, calls an LLM (OpenAI Chat Completions / Responses protocol; OpenAI, Anthropic, Gemini, Groq base URLs) with tools: `http` fetch, `sql` (parameterised queries against an **external** DB the tenant configures), `mcp`, `calculator`, `attachment`; `code` is a stub. |
| `media-preprocessor` | 577 | `POST` from DB trigger / cron | Extracts text and annotations from media for the agent (uses Google GenAI) |
| `mcp` | 967 | `ALL *`, `GET /.well-known/oauth-protected-resource` | MCP server over the org's data; API-key or OAuth (Supabase Auth OAuth 2.1) |
| `storage-gc` | 164 | cron | Deletes orphaned media objects |
| `_shared/` | — | — | `logger.ts` (no redaction), `management_auth.ts` (`requireRoles`, `requireScope`), `supabase.ts` (clients), `dispatch.ts`, `media.ts`, `db_types.ts` (generated) |

Backend imports (`functions/deno.json`): supabase-js, hono, @hono/mcp, openai, @google/genai,
zod, ajv, ky, postgres, mysql2, @libsql/client, mathjs, @slack/web-api, dayjs.

### 3.4 Frontend routes (`ui/src/routes`)

| Area | Routes |
|---|---|
| Auth | `/login`, `/oauth/callback`, `/oauth/consent` (MCP OAuth), `/oauth/instagram` |
| Public onboarding | `/onboard/whatsapp/$token`, `/onboard/instagram/$token`, `/onboard/instagram/callback` |
| Inbox | `/_auth/conversations`, `/conversations/new` (chat list, search, filters, composer, template picker, media) |
| Contacts | `/contacts`, `/contacts/new`, `/contacts/$addressId` |
| AI agents | `/agents`, `/agents/new`, `/agents/$agentId` |
| Integrations | `/integrations`; WhatsApp: list, new, onboarding tokens, `$orgAddressId`, templates (list/new/edit); Instagram: same shape; WhatsApp-Web: list/new/detail; media preprocessing |
| Settings | organization (new/edit), members (list/new/detail), API keys, webhooks |
| Stats | `/stats/usage`, `/stats/quotas` |

State: an active-organization switcher in the Zustand store (`useSetActiveOrg`), so multi-org
membership already works in the UI.

---

## 4. Feature map against the roadmap

| Roadmap area | In OpenBSP? | Notes |
|---|---|---|
| Inbox | **Yes** | Realtime conversations/messages, composer, template picker, media, visibility rules. No assign/transfer UI, tags, internal notes, canned replies, unread counts or SLA. |
| Organizations / members | **Yes** | Orgs, agents, invitations, 3-level roles, last-owner guard, soft delete. No slug, timezone, locale, suspend state, permissions or scopes. |
| Bots / AI agents | **Yes** | `agents` with `user_id` null + `agent-client` + tools. No approval queue, compliance filter, cost caps or kill switch. |
| Flows (WhatsApp Flows) | **No** | — |
| Templates | **Partly** | CRUD against Meta and a template editor. Need: sync job, versioning, template-status webhook handling, category validation, footer disclaimer. |
| Campaigns / broadcasts | **No** | — |
| Sequences / scheduler | **No** | Only pg_cron for internal sweeps |
| Contacts / leads | **Thin** | `contacts_addresses` only. No contact entity, consents, tags, segments, custom fields, ad referrals. |
| Pipeline / deals | **No** | — |
| Conversion API to Meta | **No** | — |
| Payments | **No** (tenant side) | `billing.*` is the **platform's** own subscription billing, not student fees |
| Telegram | **No** | The `service` enum has no `telegram`; `generic-webhook` is a possible base |
| Public API | **Partly** | PostgREST + API keys + `openapi.json` + MCP. Keys are plain text and unscoped. |
| Tenant webhooks | **Partly** | `webhooks` table + `notify_webhook` trigger via `pg_net`: one attempt, no retries, no HMAC signature (upstream TODO) |
| Platform billing / plans | **Yes, schema** | Tiers, plans, limits, usage, ledger, invoices. No payment provider; renewal is a TODO. |
| Audit log | **No** | `logs` is operational, not an append-only audit trail |
| i18n | **Partly** | Spanish source plus en/fr/pt/sw; no Hindi |

---

## 5. Reuse / Extend / Replace / Build matrix

- **Reuse** = use as is.
- **Extend** = keep upstream and add our own tables or functions around it, with minimal edits.
- **Replace** = keep the files for merges, but route our product through new code.
- **Build** = nothing exists.

| Domain (roadmap §5) | Decision | What and why | Phase |
|---|---|---|---|
| Tenancy (`tenants`) | **Extend** | `organizations` is the tenant (see ADR 0002). Add a 1:1 profile table for slug, timezone (default `Asia/Kolkata`), locale and status. Make suspension block `get_authorized_orgs` (one small upstream edit). | P1-01 |
| Members (`tenant_members`) | **Reuse + extend** | `agents` (humans) is the membership row; keep its last-owner and soft-delete triggers. | P1-03 |
| Roles and permissions | **Extend** | Keep the upstream `role` enum as a coarse tier so upstream policies still work. Add permission catalog, eight preset roles, overrides, scopes and `has_permission()` in our own schema. | P1-02 |
| Invitations | **Extend** | Reuse `invitations` + `accept_invitation`; add a preset-role field and an email send. | P1-03 |
| Audit log | **Build** | New append-only table. `logs` stays operational. | P1-08 |
| Settings, packs, custom fields, org profile, disclaimers | **Build** | Nothing exists. `organizations.extra` is not a settings engine. | P1-04…P1-07 |
| Feature flags / entitlements | **Extend** | `billing.tiers/plans/products` already model limits; add flags on top | P1-09 |
| Super-admin console | **Build** | No platform-admin role exists | P1-10 |
| Frontend shell | **Extend** | Reuse auth, org switcher, layout, AntD. Add permission-aware nav, Hindi, English as default, branding tokens. | P1-11 |
| RLS tests | **Build** | No tests exist. Start with the upstream tables, then every new table. | P1-12 |
| WhatsApp webhook | **Extend** (P2-01 may turn it into a replace) | Keep parsing, mapping and media download. Add: constant-time compare, raw event log table, ack-then-queue, template/quality/account handlers, routing by `phone_number_id`. | P2-01 |
| Embedded Signup | **Extend** | Flow is complete (exchange, subscribe, register, coexistence sync). **Change token storage to Vault.** | P2-02 |
| Credentials (`waba_credentials`) | **Replace** | Tokens in `extra.access_token`, readable by members — see §1. New credential service; stop exposing the token in the UI. | P2-03 |
| Templates | **Extend** | Reuse management routes and editor; add sync, versions, status webhooks, category rules | P2-04, P4-07 |
| Outbound sender | **Extend** | Keep the single `messages`-insert → dispatcher choke point and the cron retry with backoff. Add the policy gate (window, consent, quiet hours, caps, disclaimer, approval), pacing, idempotency keys and dead-letter. | P2-05, P4-06 |
| Message types | **Extend** | Dispatcher covers text, media, interactive and templates; add Flows and the `referral` object | P2-06 |
| Media pipeline | **Reuse** | Immediate download to Storage exists; check size limits and tenant paths | P2-07 |
| Status tracking | **Extend** | `status jsonb` per message; add forward-only rules and visible failure reasons | P2-08 |
| Inbox UI | **Extend** | Add assignment, tags, notes, canned replies, unread counts, window-aware composer | P2-09 |
| Number health, business profile, multi-number | **Build / extend** | Multiple addresses per org already work; quality and limit tracking is missing | P2-10…P2-12 |
| Contacts / leads | **Build** (on top of `contacts_addresses`) | A `contacts` entity with `contact_channels` that link to `contacts_addresses` | P3-02, P7-02 |
| Pipeline, deals, SLA, assignment | **Build** | — | P3 |
| Conversion feedback / outbox | **Build** | — | P3-09 |
| Consent, segments, campaigns, short links | **Build** | — | P4 |
| Sequences, webinars, scheduler | **Build** | Use pg_cron + a queue (`pgmq` or a `jobs` table) | P5 |
| Student payments | **Build** | Separate from `billing.*` (that is the platform's own billing) | P6 |
| Telegram | **Build** | New `crm-telegram-*` functions; may reuse the `generic-*` connector patterns. Needs a `telegram` value in the `service` enum (hand-written `alter type … add value`). | P7 |
| Classroom | **Build** | — | P8 |
| Public API | **Replace** keys, **extend** API | Hashed, scoped, prefixed keys; keep PostgREST and `openapi.json` as a base | P9-01 |
| Tenant webhooks | **Extend** | Add HMAC signing, retries, delivery log, replay | P9-02 |
| AI agents | **Extend** | Reuse `agent-client` and tools. Add draft-only mode, compliance layer, approval queue, cost caps, kill switch. Review the `http`/`sql` tools for SSRF and data-exfiltration risk before enabling them for tenants. | P9-03, P9-04 |
| MCP server | **Reuse** | Already exists; scope it to new permissions | P9-05 |
| Platform billing | **Extend** | Reuse `billing.*`; add a provider (Razorpay/Cashfree subscriptions), GST invoices, dunning | P10-01 |
| White-label | **Build** | Remove OpenBSP branding and logos from the UI (`public/logo*.png`, titles) behind branding tokens | P10-03 |
| Data export / erasure | **Build** | Upstream TODO lists data export as open | P10-06 |
| Logging | **Replace** wrapper | New scrubbing logger with `tenant_id` + `request_id` (keep upstream `logger.ts` for upstream code) | P0-09 |
| Instagram, Slack | **Reuse, not in scope** | Keep deployed only if wanted; not needed for the trading vertical | — |
| WhatsApp-Web (whatsmeow) | **Disable** | Banned by CLAUDE.md. See §6. | P0 follow-up |

---

## 6. WhatsApp-Web bridge: disable, keep files

Decision (2026-10-18): the whatsmeow bridge stays in the repo for upstream merges, but is never
deployed or reachable in our product. **No code was changed in this task.** Proposed follow-up
(needs approval, and each edit gets logged in `docs/upstream-edits.md`):

1. Do not deploy `whatsapp-web-management`, `whatsapp-web-webhook` and
   `whatsapp-web-dispatcher` (all three are declared in `supabase/config.toml`). Prefer a
   deploy allowlist in our CI over editing `config.toml`.
2. Never set `WHATSAPP_WEB_URL` / `WHATSAPP_WEB_TOKEN` in any environment, so the function
   fails closed even if deployed by mistake.
3. UI: hide the WhatsApp-Web card on `/integrations` and its routes behind a build-time flag.
4. DB: keep the `whatsapp-web` enum value (removing an enum value is destructive and breaks
   merges). Optionally add a check that rejects new `organizations_addresses` rows with
   `service = 'whatsapp-web'`.
5. Add a CI check that fails if any of the three functions appears in the deploy list.

---

## 7. Gaps against CLAUDE.md rules

| Rule | Current state | Fix in |
|---|---|---|
| Tenant isolation + RLS test per table | RLS is on for every table; **no tests** | P1-12 |
| Column name `tenant_id` | Upstream uses `organization_id` everywhere | ADR 0002 (proposes keeping `organization_id`; CLAUDE.md wording needs your approval to change) |
| Secrets in Vault, tables keep only ids | **Violated** for WhatsApp/Instagram/Slack tokens (`extra`), webhook `token`, API keys | P2-03, P9-01, P9-02 |
| Never log tokens or full bodies | Logger has no scrubbing; webhook logs signature values; no request ids | P0-09 |
| Webhooks: raw-body signature, raw log first, ack fast, async, idempotent | Signature yes (not constant-time); no raw log; inline processing; idempotent via unique WAMID | P2-01 |
| One send path with policy checks | One path yes; **no policy checks** | P2-05 |
| Retries, backoff, dead-letter visible in UI | Outbound: cron backoff for 12 h, then gives up silently. Tenant webhooks: one attempt. | P2-05, P9-02 |
| Service role only in edge functions | **OK** (UI uses the anon key only) | — |
| Store UTC, tenant timezone | `timestamptz` everywhere; **no tenant timezone** | P1-01 |
| PII masking, export, erasure | Not present; Meta data-deletion callback exists for Instagram | P0-09, P10-06 |
| No unofficial WhatsApp libraries | **Violated** by the whatsmeow bridge | §6 |

---

## 8. Notes from upstream docs (`CLAUDE.md`, `TODO.md`, `IDEAS.md`, `AUTH.md`)

- **Migrations are generated.** Edit `supabase/schemas/**`, then
  `supabase db diff -f <name>`. Hand-write only cron, enum additions and backfills. Our
  migrations must follow the same workflow so `db reset` stays reproducible. Proposal: our
  declarative files live in `supabase/schemas/10_crm/**`, and generated migration names carry a
  `crm_` prefix (e.g. `<timestamp>_crm_tenant_profile.sql`).
- **Regenerate types after each migration:** `_shared/db_types.ts`, copied to
  `ui/src/supabase/db_types.ts` (the UI has a `types:sync-check` script).
- **`deno check` only works from inside `supabase/functions`.** The upstream `.claude` hook that
  runs `deno check <file>` always passes and verifies nothing.
- **Upstream CLAUDE.md names the upstream author's Supabase project ref** and production log
  queries. Never use these from our sessions.
- **Upstream TODO items that match our roadmap:** webhook delivery retries and dead-letter,
  batched org deletion, encrypt API keys, data export, move RLS helpers out of `public`,
  API-key-created `local` conversations become orphans (the insert policy admits `anon`).
- **Connection ownership:** reconnecting a WhatsApp number from another org moves it to the
  newest org. That is fine for us (tenants own their WABA), but should be audited (P1-08).

---

## 9. Risks found

| Risk | Severity | Mitigation |
|---|---|---|
| Members can read WABA/IG tokens | **Critical** | Do not onboard any external tenant before P2-03. Meanwhile, use only our own test WABA. |
| No tests at all | High | P1-12 before any Phase 1 schema work merges |
| Unofficial bridge deployed by accident | High | §6 steps 1, 2 and 5 |
| Plain-text API keys | Medium | P9-01; until then issue keys only to ourselves |
| `agent-client` `http`/`sql` tools can reach arbitrary hosts | Medium | Keep agents disabled for tenants until P9-03/P9-04 |
| Global unique `messages.external_id` | Low | WAMIDs are globally unique; check again when Telegram ids are added (they are only unique per chat) |
| Spanish-first UI strings | Low | P1-11 |
