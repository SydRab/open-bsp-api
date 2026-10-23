// [crm] P2-10: quality rating. No webhook exists for this -- it's only
// readable by polling the phone number's own GET endpoint. This mirrors
// token_health.ts's exact shape (daily cron, one connected number at a
// time, write the result into extra, flag only on a bad transition). The
// messaging-limit tier is the opposite shape -- no polling field for it,
// only ever delivered via the phone_number_quality_update webhook, handled
// in whatsapp_webhook_processing.ts instead.
//
// [crm] P2-11: the same GET call also returns verified_name, so this is
// also where a pending display-name change (phone_number_name_update
// webhook) gets resolved -- see the nameResolved check below.
// https://developers.facebook.com/docs/whatsapp/cloud-api/reference/phone-numbers
import * as log from "../_shared/logger.ts";
import type {
  createClient,
  WhatsAppOrganizationAddressExtra,
} from "../_shared/supabase.ts";
import { isQualityDegraded } from "../_shared/number_health.ts";
import { getWhatsAppAccessToken } from "../_shared/whatsapp_credentials.ts";
import { getPhoneNumber } from "./embedded_signup.ts";

type Client = ReturnType<typeof createClient>;

export async function checkNumberQuality(client: Client) {
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

    // Mock connections (P2-02) have no real Meta number to poll.
    if (extra.is_mock) {
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
      const { quality_rating, verified_name } = await getPhoneNumber(
        access_token,
        row.address,
      );

      const degraded = isQualityDegraded(extra.quality_rating, quality_rating);

      // [crm] P2-11: this is also where a pending display-name change gets
      // resolved -- re-registering after Meta's approval is what actually
      // makes verified_name catch up, and this is the one place that
      // re-polls it. Once it matches the requested name, the change has
      // taken effect, so there's nothing left pending to show.
      const nameResolved = extra.requested_verified_name &&
        verified_name === extra.requested_verified_name;

      await client
        .from("organizations_addresses")
        .update({
          extra: {
            quality_rating,
            quality_checked_at: new Date(now).toISOString(),
            verified_name,
            ...(nameResolved
              ? {
                name_status: null,
                requested_verified_name: null,
                name_rejection_reason: null,
              }
              : {}),
          },
        })
        .eq("organization_id", row.organization_id)
        .eq("address", row.address)
        .throwOnError();

      if (degraded) {
        flagged++;

        await client
          .from("logs")
          .insert({
            organization_id: row.organization_id,
            organization_address: row.address,
            category: "whatsapp_number_quality",
            service: "whatsapp",
            level: "warning",
            message:
              `WhatsApp number quality dropped from ${extra.quality_rating} to ${quality_rating}`,
          })
          .throwOnError();
      } else {
        healthy++;
      }
    } catch (error) {
      // Same reasoning as token_health.ts: a failed check (network blip,
      // Meta outage) is not evidence of a real quality drop -- log it, but
      // don't flag on a guess. Next day's run tries again.
      const message = error instanceof Error ? error.message : String(error);
      log.error("Failed to check WhatsApp number quality", {
        organization_id: row.organization_id,
        address: row.address,
        error: message,
      });
      skipped++;
    }
  }

  log.info("WhatsApp number quality summary", {
    total: rows.length,
    healthy,
    flagged,
    skipped,
  });

  return { total: rows.length, healthy, flagged, skipped };
}
