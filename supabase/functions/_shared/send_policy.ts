// [crm] P2-05: the outbound sender's single compliance gate. Called from
// whatsapp-dispatcher immediately before the Meta API call -- confirmed (by
// grepping every function for a direct `graph.facebook.com/.../messages`
// call) to be the ONLY place that sends a WhatsApp message, so a check here
// covers every caller (the UI compose path, the MCP sendMessage tool used by
// AI agents, and anything future) without each of them re-implementing it.
//
// Three kinds of outcome:
//   allowed  -- call Meta.
//   blocked  -- terminal. Never reaches Meta; recorded as status.failed with
//               a categorized reason in status.errors, same shape the dispatcher
//               already uses for a real Meta rejection. No auto-retry: the
//               reason (window closed / opted out / over the marketing cap)
//               doesn't resolve itself by waiting, a human has to act. P2-08/
//               P2-09 (not built yet) own actually surfacing the reason text;
//               today this is visible only as the existing generic "failed"
//               icon (MessageStatusUtils.ts) -- see SYSTEM_BLUEPRINT_AND_GUIDE.md.
//   held     -- temporary. Keeps status.pending and adds a held_* key; the
//               already-existing dispatch_cron_backoff sweep re-fires the
//               dispatcher at the same 1/2/4/8/16/30-min checkpoints it uses
//               for a transient Meta error, so no new cron is needed. Quiet
//               hours (worst case ~12h) and pacing (sub-minute) both fit
//               inside that sweep's 12h/29-attempt cap.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { ConversationRow, Database, OutgoingMessage } from "./supabase.ts";

// Conservative, self-imposed defaults -- NOT a documented Meta tier limit
// (those vary per number and quality rating, and aren't reliably knowable
// from here). The point is to smooth OUR OWN bursts (e.g. a future broadcast
// feature firing many sends at once) before they trip Meta's own throughput
// limit (code 130429) or per-recipient limit (131056), not to approximate
// Meta's limit exactly.
export const SEND_PACING_CAPACITY = 5;
export const SEND_PACING_REFILL_PER_SECOND = 1;

/**
 * Named failure categories for a permanent Meta rejection, per the roadmap's
 * P2-05 wording ("error mapping: re-engagement, marketing-limit,
 * undeliverable, invalid params, rate limit"). Verified against Meta's own
 * error-code reference (not the third-party summaries that first turned up,
 * which disagreed with each other on several codes):
 * https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/
 *
 * This is a REFINEMENT of whatsapp-dispatcher's existing RETRYABLE_META_CODES
 * split, not a replacement: that set already decides retry vs. permanent
 * correctly. This only sub-classifies the permanent bucket for the reason
 * text a human eventually sees (P2-08, not built yet) -- rate-limit codes
 * ARE in RETRYABLE_META_CODES already and never reach this function; it is
 * listed below anyway so the mapping is complete if a caller ever wants it
 * for a code that arrived without going through that retry decision first.
 */
const META_ERROR_CATEGORIES: Record<number, string> = {
  // Re-engagement: the 24h customer service window is closed.
  131047: "re-engagement",
  // Marketing-limit: Meta-side marketing restrictions, distinct from our own
  // marketing.frequency_cap (which never reaches Meta at all -- see
  // checkSendPolicy above).
  131049: "marketing-limit",
  131063: "marketing-limit",
  131064: "marketing-limit",
  // Undeliverable: the recipient, not the message, is the problem.
  130403: "undeliverable",
  131050: "undeliverable", // recipient opted out of marketing WITH META directly
  131026: "undeliverable",
  130472: "undeliverable",
  // Invalid params: the request itself is malformed.
  100: "invalid-params",
  131008: "invalid-params",
  131009: "invalid-params",
  132000: "invalid-params",
  132012: "invalid-params",
  131021: "invalid-params",
  131051: "invalid-params",
  131055: "invalid-params",
  132018: "invalid-params",
  135000: "invalid-params",
  // Rate limit (see note above: these are already retried, not surfaced via
  // this function, in the dispatcher's actual flow).
  4: "rate-limit",
  80007: "rate-limit",
  130429: "rate-limit",
  131056: "rate-limit",
  133016: "rate-limit",
  2: "rate-limit",
};

/** Named category for a Meta error code, or "other" when uncatalogued. */
export function categorizeMetaErrorCode(code: number): string {
  return META_ERROR_CATEGORIES[code] ?? "other";
}

export type SendPolicyDecision =
  | { outcome: "allowed" }
  | {
    outcome: "blocked";
    category: "window_closed" | "opted_out" | "marketing_cap";
    message: string;
  }
  | { outcome: "held"; key: "held_quiet_hours" | "held_rate_limit" };

/** Pure: the 24h customer service window, open iff a contact message landed within the last 24h. */
export function isWindowOpen(
  lastInboundAt: string | null,
  now: Date = new Date(),
): boolean {
  if (!lastInboundAt) return false;
  return now.getTime() - new Date(lastInboundAt).getTime() <
    24 * 60 * 60 * 1000;
}

function localHourMinute(
  timezone: string,
  now: Date,
): { hour: number; minute: number } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    hour: "numeric",
    minute: "numeric",
    hour12: false,
  }).formatToParts(now);

  const hour = Number(parts.find((p) => p.type === "hour")?.value ?? "0");
  const minute = Number(parts.find((p) => p.type === "minute")?.value ?? "0");

  // Intl can render midnight as "24" with hour12: false.
  return { hour: hour === 24 ? 0 : hour, minute };
}

/**
 * Pure: is `now`, read in `timezone`, inside [start, end)? `start > end`
 * (e.g. the 21:00-09:00 default) is an overnight window, not an error.
 */
export function isWithinQuietHours(
  quietHours: { start: string; end: string },
  timezone: string,
  now: Date = new Date(),
): boolean {
  const toMinutes = (hhmm: string) => {
    const [h, m] = hhmm.split(":").map(Number);
    return h * 60 + m;
  };

  const start = toMinutes(quietHours.start);
  const end = toMinutes(quietHours.end);
  if (start === end) return false;

  const { hour, minute } = localHourMinute(timezone, now);
  const current = hour * 60 + minute;

  return start < end
    ? current >= start && current < end
    : current >= start || current < end;
}

/**
 * Pure: does the whole trimmed message (not a substring anywhere in it)
 * case-insensitively equal one of the opt-out keywords? An exact-match rule
 * (the common STOP/UNSUBSCRIBE convention) rather than a substring search,
 * so "please stop sending flyers, I'm in the middle of something" does not
 * opt someone out by accident. Returns the matched keyword, or null.
 */
export function matchesOptOutKeyword(
  text: string,
  keywords: string[],
): string | null {
  const normalized = text.trim().toUpperCase();
  return keywords.find((k) => k.toUpperCase() === normalized) ?? null;
}

export async function getSetting<T>(
  client: SupabaseClient<Database>,
  organization_id: string,
  key: string,
): Promise<T> {
  const { data, error } = await client
    .schema("crm")
    .rpc("get_setting", { p_organization_id: organization_id, p_key: key });

  if (error) throw error;

  return data as T;
}

export async function checkSendPolicy(
  client: SupabaseClient<Database>,
  message: {
    organization_id: string;
    organization_address: string;
    conversation_id: string;
    conversation_address: string | null;
    content: unknown;
    service: Database["public"]["Enums"]["service"];
  },
): Promise<SendPolicyDecision> {
  const content = message.content as OutgoingMessage;

  if (!(content.type === "data" && content.kind === "template")) {
    // Free-form session messages are only ever sendable inside the window --
    // Meta rejects them with code 131047 otherwise. Category-blind: a free-
    // form reply isn't "marketing" under Meta's own classification, so
    // consent/cap/quiet-hours don't apply here, only the window.
    const { data: conversation } = await client
      .from("conversations")
      .select("last_inbound_at")
      .eq("id", message.conversation_id)
      .maybeSingle<Pick<ConversationRow, "last_inbound_at">>();

    if (!isWindowOpen(conversation?.last_inbound_at ?? null)) {
      return {
        outcome: "blocked",
        category: "window_closed",
        message:
          "24h customer service window is closed (no contact reply in the last 24h, or none yet). Send a template message to re-open it.",
      };
    }
  } else if (message.conversation_address) {
    const template = content.data;

    // The category lookup is best-effort against crm.templates (P2-04),
    // which is a synced CACHE, not Meta itself -- a template created
    // directly in Meta's UI and never synced here won't be found. Unknown
    // category skips the marketing-only checks below rather than blocking
    // every send whose template isn't cached; "Sync with Meta" is how an
    // org keeps this current. Documented as a known gap, not silently
    // assumed safe.
    const { data: templateRow } = await client
      .schema("crm")
      .from("templates")
      .select("category")
      .eq("organization_id", message.organization_id)
      .eq("organization_address", message.organization_address)
      .eq("name", template.name)
      .eq("language", template.language.code)
      .maybeSingle();

    if (templateRow?.category === "MARKETING") {
      // marketing.requires_opt_in is platform-locked true (CLAUDE.md:
      // "Marketing messages require recorded opt-in"). There is no opt-in
      // COLLECTION flow yet (a future phase's job -- see
      // SYSTEM_BLUEPRINT_AND_GUIDE.md known gaps), so until one exists and
      // records an 'opted_in' event, every marketing template send is
      // correctly blocked here: silence is never consent.
      const { data: status } = await client
        .schema("crm")
        .rpc("get_consent_status", {
          p_organization_id: message.organization_id,
          p_organization_address: message.organization_address,
          p_service: message.service,
          p_address: message.conversation_address,
        });

      if (status !== "opted_in") {
        return {
          outcome: "blocked",
          category: "opted_out",
          message:
            "This contact has no recorded marketing opt-in (or opted out). Marketing templates require consent.",
        };
      }

      const [quietHours, timezoneRow] = await Promise.all([
        getSetting<{ start: string; end: string }>(
          client,
          message.organization_id,
          "messaging.quiet_hours",
        ),
        client
          .schema("crm")
          .from("organization_profiles")
          .select("timezone")
          .eq("organization_id", message.organization_id)
          .single(),
      ]);

      if (
        isWithinQuietHours(
          quietHours,
          timezoneRow.data?.timezone ?? "Asia/Kolkata",
        )
      ) {
        return { outcome: "held", key: "held_quiet_hours" };
      }

      const cap = await getSetting<
        { max_messages: number; period_days: number }
      >(client, message.organization_id, "marketing.frequency_cap");

      const { data: recentCount, error: capError } = await client
        .schema("crm")
        .rpc("count_recent_marketing_sends", {
          p_organization_id: message.organization_id,
          p_organization_address: message.organization_address,
          p_conversation_address: message.conversation_address,
          p_period_days: cap.period_days,
        });

      if (capError) throw capError;

      if ((recentCount ?? 0) >= cap.max_messages) {
        return {
          outcome: "blocked",
          category: "marketing_cap",
          message:
            `This contact already received ${recentCount} marketing message(s) in the last ${cap.period_days} day(s) (cap: ${cap.max_messages}).`,
        };
      }
    }
  }

  const { data: tokenAvailable, error: pacingError } = await client
    .schema("crm")
    .rpc("try_consume_send_token", {
      p_organization_id: message.organization_id,
      p_service: message.service,
      p_organization_address: message.organization_address,
      p_capacity: SEND_PACING_CAPACITY,
      p_refill_per_second: SEND_PACING_REFILL_PER_SECOND,
    });

  if (pacingError) throw pacingError;

  if (!tokenAvailable) {
    return { outcome: "held", key: "held_rate_limit" };
  }

  return { outcome: "allowed" };
}
