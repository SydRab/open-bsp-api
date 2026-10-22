// [crm] P2-03: WhatsApp token health. Unlike Instagram/Slack, the token
// Embedded Signup issues (a Business Integration System User token) has no
// programmatic refresh endpoint -- Meta's own guidance is that recovering an
// expired/invalid one means re-running Embedded Signup, not silently
// swapping it out. So this never attempts a refresh: it only checks each
// connected number's token against Meta's Debug Token API and flags
// `needs_reauth` when it's invalid or expiring soon, for the UI to surface
// and the tenant to act on via the same "Connect WhatsApp" button that
// already exists. https://developers.facebook.com/docs/graph-api/reference/debug_token
import * as log from "../_shared/logger.ts";
import type {
  createClient,
  WhatsAppOrganizationAddressExtra,
} from "../_shared/supabase.ts";
import { getWhatsAppAccessToken } from "../_shared/whatsapp_credentials.ts";

const API_VERSION = "v24.0";
const APP_ID = Deno.env.get("META_APP_ID");
const APP_SECRET = Deno.env.get("META_APP_SECRET");

// Flag a token once it's within this window of its known expiry. Mirrors
// Instagram's refresh window (login.ts) for consistency, even though the
// action taken once flagged is different (prompt reconnect, not refresh).
const REAUTH_WINDOW_MS = 10 * 24 * 60 * 60 * 1000; // 10 days

type Client = ReturnType<typeof createClient>;

/** Which (app_id, app_secret) pair issued a connection's token, from the
 * pipe-separated META_APP_ID/META_APP_SECRET lists. Falls back to the first
 * pair for rows connected before extra.application_id existed, or when the
 * recorded id no longer appears in the list (app removed from the env var) --
 * this is a best-effort health check, not a hard-fail path. */
function resolveAppCredentials(
  application_id?: string,
): { app_id: string; app_secret: string } | null {
  if (!APP_ID || !APP_SECRET) return null;

  const ids = APP_ID.split("|");
  const secrets = APP_SECRET.split("|");

  if (ids.length !== secrets.length) return null;

  const idIndex = application_id ? ids.indexOf(application_id) : -1;

  return {
    app_id: ids[idIndex === -1 ? 0 : idIndex],
    app_secret: secrets[idIndex === -1 ? 0 : idIndex],
  };
}

async function debugToken(
  input_token: string,
  app_id: string,
  app_secret: string,
): Promise<{ is_valid: boolean; expires_at: number }> {
  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/debug_token?input_token=${input_token}&access_token=${app_id}|${app_secret}`,
  );

  if (!response.ok) {
    throw new Error(`Debug Token API returned ${response.status}`);
  }

  const { data } = await response.json();
  return { is_valid: !!data?.is_valid, expires_at: data?.expires_at ?? 0 };
}

/** Pure: no network, no DB -- just the flagging decision, so it's directly
 * unit-testable. expires_at is a Unix seconds timestamp; 0 means Meta
 * reports no expiry ("Never"), which never flags on expiry grounds. */
export function shouldFlagForReauth(
  is_valid: boolean,
  expires_at: number,
  now: number,
): boolean {
  if (!is_valid) return true;
  if (expires_at <= 0) return false;
  return expires_at * 1000 - now <= REAUTH_WINDOW_MS;
}

export async function checkTokenHealth(client: Client) {
  const { data: rows } = await client
    .from("organizations_addresses")
    .select("organization_id, address, service, extra")
    .eq("service", "whatsapp")
    .eq("status", "connected")
    .throwOnError();

  const now = Date.now();
  let healthy = 0;
  let flagged = 0;
  let skipped = 0;

  for (const row of rows) {
    if (row.service !== "whatsapp") continue; // narrow the union

    const extra = (row.extra ?? {}) as WhatsAppOrganizationAddressExtra;

    // Mock connections (P2-02) have no real token to check.
    if (extra.is_mock) {
      skipped++;
      continue;
    }

    const credentials = resolveAppCredentials(extra.application_id);

    if (!credentials) {
      skipped++;
      continue;
    }

    const access_token = await getWhatsAppAccessToken(
      client,
      row.organization_id,
      row.address,
    );

    if (!access_token) {
      skipped++;
      continue;
    }

    try {
      const { is_valid, expires_at } = await debugToken(
        access_token,
        credentials.app_id,
        credentials.app_secret,
      );

      const flag = shouldFlagForReauth(is_valid, expires_at, now);

      await client
        .from("organizations_addresses")
        .update({
          extra: {
            token_checked_at: new Date(now).toISOString(),
            token_expires_at: expires_at > 0
              ? new Date(expires_at * 1000).toISOString()
              : null,
            needs_reauth: flag ? new Date(now).toISOString() : null,
          },
        })
        .eq("organization_id", row.organization_id)
        .eq("address", row.address)
        .throwOnError();

      if (flag) {
        flagged++;

        await client
          .from("logs")
          .insert({
            organization_id: row.organization_id,
            organization_address: row.address,
            category: "whatsapp_token_health",
            service: "whatsapp",
            level: "warning",
            message: is_valid
              ? "WhatsApp token expires soon -- reconnect recommended"
              : "WhatsApp token is no longer valid -- reconnect required",
          });
      } else {
        healthy++;
      }
    } catch (error) {
      // A failed health check (network blip, Meta outage) is not evidence
      // the token itself is bad -- log it, but don't flag needs_reauth on a
      // guess. Next day's run tries again.
      const message = error instanceof Error ? error.message : String(error);
      log.error("Failed to check WhatsApp token health", {
        organization_id: row.organization_id,
        address: row.address,
        error: message,
      });
      skipped++;
    }
  }

  log.info("WhatsApp token health summary", {
    total: rows.length,
    healthy,
    flagged,
    skipped,
  });

  return { total: rows.length, healthy, flagged, skipped };
}
