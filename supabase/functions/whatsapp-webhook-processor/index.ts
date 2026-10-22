// [crm] P2-01: picks up one crm.webhook_events row (invoked by pg_cron, same
// auth pattern as whatsapp-dispatcher) and runs the actual processing that
// used to happen inline in the webhook request. Claims the attempt (bumps
// attempts/last_attempt_at) BEFORE processing, so a crash mid-run still
// backs off the next retry instead of being immediately re-picked — attempts
// starting at 0 would otherwise always be "due now" by the cron's own
// backoff formula.
import * as log from "../_shared/logger.ts";
import { createUnsecureClient } from "../_shared/supabase.ts";
import { processWhatsAppWebhookPayload } from "../_shared/whatsapp_webhook_processing.ts";

const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.replace("Bearer ", "");

  if (token !== SERVICE_ROLE_KEY) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { id } = (await req.json()) as { id: string };
  const client = createUnsecureClient();

  // Atomic claim (bumps attempts/last_attempt_at and returns the row in one
  // statement) so two cron ticks racing to pick up the same event can't both
  // process it — the loser's UPDATE matches zero rows once the winner's has
  // run, since both are gated on `processed_at is null`.
  const { data: row, error: claimError } = await client
    .schema("crm")
    .rpc("claim_webhook_event", { p_id: id })
    .maybeSingle();

  if (claimError) {
    log.error("Failed to claim webhook event", {
      id,
      error: claimError.message,
    });
    return new Response("Claim failed", { status: 500 });
  }

  if (!row) {
    // Already processed, already dead-lettered, or claimed by an overlapping
    // tick. Not an error — the cron's own WHERE clause just raced itself.
    log.info("Webhook event already claimed or processed", { id });
    return new Response();
  }

  try {
    await processWhatsAppWebhookPayload(row.raw_body, client);

    await client
      .schema("crm")
      .from("webhook_events")
      .update({
        processed_at: new Date().toISOString(),
        processing_error: null,
      })
      .eq("id", id)
      .throwOnError();

    log.info("Processed webhook event", { id, attempts: row.attempts });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    log.error("Failed to process webhook event", {
      id,
      attempts: row.attempts,
      error: message,
    });

    await client
      .schema("crm")
      .from("webhook_events")
      .update({ processing_error: message })
      .eq("id", id)
      .throwOnError();
  }

  return new Response();
});
