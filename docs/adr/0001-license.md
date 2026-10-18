# ADR 0001 — License of the OpenBSP forks

| | |
|---|---|
| Status | **Proposed. Pending legal counsel confirmation.** Not to be marked Accepted until counsel signs off. |
| Date | 2026-10-18 |
| Task | P0-02 |
| Scope | `open-bsp-api` (commit `22358fd`) and `open-bsp-ui` (commit `735e00d`), forked to `SydRab/*` |

## Context

We want to run a closed-source, white-label, paid multi-tenant SaaS on top of both forks. We
need to know what the licenses allow, what they require, and what is not covered by them.

## Findings

### 1. Both repos use the Unlicense

`LICENSE` in both repos is the standard text of the **Unlicense** (https://unlicense.org/),
also shown as a badge in both READMEs. The Unlicense is a public-domain dedication. It says
anyone may "copy, modify, publish, use, compile, sell, or distribute this software … for any
purpose, commercial or non-commercial, and by any means". It has a standard "AS IS", no-warranty
and no-liability clause.

What that means for us:

| Question | Answer under the Unlicense |
|---|---|
| Can we use it commercially and charge for it? | Yes |
| Can we keep our changes closed-source? | Yes. There is no copyleft or source-sharing obligation, including for network/SaaS use. |
| Do we have to credit OpenBSP or keep the license text? | No attribution is required. Keeping `LICENSE` in the repo is still good practice. |
| Can we rebrand (white-label)? | Yes, as far as the code goes (see §3 for names and logos) |
| Can we relicense our derived product? | Yes; our own code can carry any license we choose |
| Warranty or support from upstream? | None |

### 2. Points for counsel

1. **Public-domain dedication outside the US.** In some legal systems (including parts of the
   EU), authors cannot fully waive their rights. The Unlicense has no explicit fallback license
   (unlike CC0). Ask counsel to confirm the Unlicense gives us enough rights under Indian law,
   and under the law of the upstream author's jurisdiction (not confirmed).
   If counsel is not comfortable, the cheap fix is to ask the upstream author for a written
   confirmation or an MIT/0BSD grant.
2. **Outside contributions.** Neither `CONTRIBUTING.md` mentions how contributions are licensed.
   Almost all commits are from the upstream author: about 360 of 365 commits in the API repo
   and 223 of 225 in the UI repo. Three other contributors made 5 commits between them. Ask
   counsel whether contributions to an Unlicensed repo can be treated as made under the same
   terms.
3. **No warranty.** We carry all liability toward our tenants. Our tenant Terms must disclaim
   and allocate liability for us.

### 3. Things the license does not cover

| Item | Where | What to do |
|---|---|---|
| The **"OpenBSP" name** and logos | READMEs, `ui/public/logo*.png`, UI titles | A software license does not grant trademark rights. Do not use the OpenBSP name or logo in our product or marketing. Replace with our branding (P10-03, earlier in P1-11). |
| **Meta Business Partner** badges | `api/meta-business-partner-{dark,light}.png`, README | Meta trademarks; they also claim a partner status the upstream author holds, not us. Never ship or show them. |
| **App Review videos** | `api/app-review/*.mp4` | They show the upstream author's app. Do not reuse them for our Meta App Review; we record our own. |
| Upstream demo assets | `demo.mp4`, `ui.png`, `architecture.png` | Do not use in our marketing |
| **whatsmeow / open-bsp-whatsmeow** | Separate repos, not vendored here | `tulir/whatsmeow` is MPL-2.0. It is not in our code base, and we are disabling the WhatsApp-Web feature anyway (see audit §6). No license impact. |

### 4. Third-party dependencies

**Frontend (`ui/package-lock.json`, 512 packages, dev included):**

| License | Count | Notes |
|---|---|---|
| MIT | 340 | — |
| ISC | 26 | — |
| Apache-2.0 | 15 | — |
| BSD-2/3-Clause | 14 | — |
| MPL-2.0 | 12 | `lightningcss` and its platform binaries (Tailwind's CSS build tooling). File-level copyleft only. It runs at build time and is not shipped as modified source. No obligation unless we modify it. |
| MPL-2.0 OR Apache-2.0 | 1 | `dompurify`; we can choose Apache-2.0 |
| Others (MIT-0, CC0, MIT OR CC0, BlueOak, Unlicense, Python-2.0 dev-only, MIT AND ISC) | 8 | All permissive |
| Not recorded in the lockfile | 96 | Mostly well-known MIT/ISC packages (`debug`, `ms`, `nanoid`, `postcss`, `tslib`, `typescript`, eslint tooling…). Must be confirmed with a real scanner. |

**No GPL, LGPL, AGPL or SSPL licenses were found.**

**Backend (`supabase/functions/deno.json`):** supabase-js (MIT), hono and @hono/mcp (MIT),
openai (Apache-2.0), @google/genai (Apache-2.0), zod (MIT), ajv (MIT), ky (MIT), postgres
(Unlicense), mysql2 (MIT), @libsql/client (MIT), mathjs (Apache-2.0), @slack/web-api (MIT),
dayjs (MIT). `plugin/`: @modelcontextprotocol/sdk (MIT). These are the licenses as commonly
published, from general knowledge. The Deno lockfile has no license data, so they must be
confirmed by the scanner in P0-05.

Apache-2.0 dependencies require keeping their NOTICE files when we distribute them. For a
hosted SaaS we do not distribute the backend. For the frontend bundle, include a third-party
notices page or file.

## Decision (proposed)

1. Treat both forks as usable for a closed-source, white-label, paid SaaS, **subject to
   counsel confirming §2**.
2. Keep the upstream `LICENSE` files unchanged in both repos. Our own code is proprietary
   unless we decide otherwise; record that in a top-level `NOTICE`/`LICENSE-CRM` file later
   (no change made now).
3. Never use the OpenBSP name or logos, Meta partner badges, App Review videos or demo media in
   our product, marketing or Meta submissions.
4. Add an automated license check to CI (P0-05) for npm and Deno dependencies. It fails on
   GPL/AGPL/SSPL or unknown licenses in production dependencies.
5. Ship a third-party notices file with the frontend build.

## Consequences

- No source-disclosure obligation blocks the business model.
- We take on all warranty and liability toward tenants; the Terms must cover this.
- We must replace upstream branding before any tenant sees the product.

## Open actions

- [ ] Counsel: confirm §2 items 1–3 (owner: you)
- [ ] Optional: ask the upstream author for a written confirmation of the license grant
- [ ] P0-05: add the license scanner to CI
- [ ] P1-11 / P10-03: remove OpenBSP branding from the UI
