// [crm] P3-09: picks up one crm.outbox_events row (invoked by pg_cron,
// same auth pattern as whatsapp-webhook-processor) and sends it to Meta's
// Conversions API for Business Messaging. Claims the attempt (bumps
// attempts/last_attempt_at) BEFORE sending, so a crash mid-send still
// backs off the next retry instead of being immediately re-picked.
import * as log from "../_shared/logger.ts";
import { createUnsecureClient } from "../_shared/supabase.ts";
import { sendConversionEvent } from "../_shared/conversions_api.ts";

const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.replace("Bearer ", "");

  if (token !== SERVICE_ROLE_KEY) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { id } = (await req.json()) as { id: string };
  const client = createUnsecureClient();

  // Atomic claim, same reasoning as whatsapp-webhook-processor's own.
  const { data: row, error: claimError } = await client
    .schema("crm")
    .rpc("claim_outbox_event", { p_id: id })
    .maybeSingle();

  if (claimError) {
    log.error("Failed to claim outbox event", {
      id,
      error: claimError.message,
    });
    return new Response("Claim failed", { status: 500 });
  }

  if (!row) {
    // Already sent, already dead-lettered, or claimed by an overlapping
    // tick. Not an error -- the cron's own WHERE clause just raced itself.
    log.info("Outbox event already claimed or processed", { id });
    return new Response();
  }

  try {
    await sendConversionEvent(
      client,
      row.organization_id,
      row.organization_address,
      {
        event_name: row.event_name,
        event_time: row.event_time,
        ctwa_clid: row.ctwa_clid,
        value: row.value,
        currency: row.currency,
      },
    );

    await client.schema("crm").rpc("mark_outbox_event_sent", { p_id: id })
      .throwOnError();

    log.info("Sent conversion event", { id, attempts: row.attempts });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    log.error("Failed to send conversion event", {
      id,
      attempts: row.attempts,
      error: message,
    });

    await client
      .schema("crm")
      .rpc("mark_outbox_event_failed", { p_id: id, p_error: message })
      .throwOnError();
  }

  return new Response();
});
