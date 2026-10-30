// [crm] P3-09: Meta's "Conversions API for Business Messaging" -- a
// distinct API from the standard web Conversions API. Doc, read directly
// (not guessed) before writing this file:
// https://developers.facebook.com/docs/marketing-api/conversions-api/business-messaging
//
// A "dataset" is created (idempotently -- the endpoint creates-or-fetches
// one per WABA) via POST /{waba_id}/dataset, authenticated with that
// WABA's own existing token (whatsapp_business_manage_events scope,
// already granted by Embedded Signup) -- no new credential type needed.
// The dataset id is cached in organizations_addresses.extra.
// conversions_dataset_id, right next to the waba_id P2-02 already stores
// there.
//
// No documented hard event-time reject window for this endpoint (unlike
// the standard web CAPI's 7-day limit) -- only that ad-click attribution
// itself degrades past 7 days. test_event_code support is unconfirmed for
// this specific endpoint, so it is deliberately not sent -- do not guess
// the shape (CLAUDE.md).
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "./supabase.ts";
import * as log from "./logger.ts";
import { getWhatsAppAccessToken } from "./whatsapp_credentials.ts";

const API_VERSION = "v24.0";

async function getBusinessCredentials(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
): Promise<
  { waba_id: string; access_token: string; extra: Record<string, unknown> }
> {
  const { data, error } = await client
    .from("organizations_addresses")
    .select("extra")
    .eq("organization_id", organization_id)
    .eq("address", organization_address)
    .single();

  if (error || !data) {
    throw new Error(
      `Could not fetch business credentials: ${error?.message}`,
    );
  }

  const extra = (data.extra as Record<string, unknown>) || {};
  const access_token = await getWhatsAppAccessToken(
    client,
    organization_id,
    organization_address,
  );

  return { waba_id: extra.waba_id as string, access_token, extra };
}

/** This address's Meta dataset id, creating it (once) on first use. */
export async function getOrCreateDatasetId(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
): Promise<string> {
  const { waba_id, access_token, extra } = await getBusinessCredentials(
    client,
    organization_id,
    organization_address,
  );

  if (typeof extra.conversions_dataset_id === "string") {
    return extra.conversions_dataset_id;
  }

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${waba_id}/dataset`,
    { method: "POST", headers: { Authorization: `Bearer ${access_token}` } },
  );
  const body = await response.json();
  if (!response.ok || typeof body?.dataset_id !== "string") {
    log.error("Failed to create/fetch conversions dataset", {
      waba_id,
      body,
    });
    throw new Error(`Dataset creation failed: ${JSON.stringify(body)}`);
  }

  await client
    .from("organizations_addresses")
    .update({ extra: { ...extra, conversions_dataset_id: body.dataset_id } })
    .eq("organization_id", organization_id)
    .eq("address", organization_address)
    .throwOnError();

  return body.dataset_id as string;
}

export type ConversionEvent = {
  event_name: string;
  /** ISO timestamp. */
  event_time: string;
  ctwa_clid: string;
  value: number | null;
  currency: string | null;
};

/** The pure piece: Meta's documented payload shape, no client/network --
 * worth testing directly, same precedent as token_health.ts's
 * shouldFlagForReauth. */
export function buildConversionEventPayload(event: ConversionEvent) {
  const custom_data: Record<string, unknown> = {};
  if (event.value != null) custom_data.value = event.value;
  if (event.currency != null) custom_data.currency = event.currency;

  return {
    data: [{
      event_name: event.event_name,
      event_time: Math.floor(new Date(event.event_time).getTime() / 1000),
      action_source: "business_messaging",
      messaging_channel: "whatsapp",
      user_data: { ctwa_clid: event.ctwa_clid },
      ...(Object.keys(custom_data).length > 0 ? { custom_data } : {}),
    }],
  };
}

export async function sendConversionEvent(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
  event: ConversionEvent,
): Promise<void> {
  const dataset_id = await getOrCreateDatasetId(
    client,
    organization_id,
    organization_address,
  );
  const { access_token } = await getBusinessCredentials(
    client,
    organization_id,
    organization_address,
  );

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${dataset_id}/events`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access_token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(buildConversionEventPayload(event)),
    },
  );

  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new Error(
      `Meta conversion event send failed: ${JSON.stringify(body)}`,
    );
  }
}
