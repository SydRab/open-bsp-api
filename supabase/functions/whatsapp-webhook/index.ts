import * as log from "../_shared/logger.ts";
import { createUnsecureClient } from "../_shared/supabase.ts";
import { sha256Hex, timingSafeEqualHex } from "./lib.ts";

const VERIFY_TOKEN = Deno.env.get("WHATSAPP_VERIFY_TOKEN");
const APP_ID = Deno.env.get("META_APP_ID");
const APP_SECRET = Deno.env.get("META_APP_SECRET");

Deno.serve(async (request) => {
  switch (request.method) {
    case "GET":
      return verifyToken(request);
    case "POST":
      return await ingestWebhook(request);
  }

  return new Response("Method not implemented", { status: 501 });
});

function verifyToken(request: Request): Response {
  if (!VERIFY_TOKEN) {
    log.warn("WHATSAPP_VERIFY_TOKEN environment variable not set");
  }

  const params = new URL(request.url).searchParams;

  if (
    params.get("hub.mode") === "subscribe" &&
    params.get("hub.verify_token") === VERIFY_TOKEN
  ) {
    return new Response(params.get("hub.challenge"));
  }

  return new Response("Verification failed, tokens do not match", {
    status: 403,
  });
}

/**
 * Validates the WhatsApp webhook signature to ensure the request comes from Meta
 * @param request The incoming request
 * @param body The raw body of the request
 * @returns Promise<boolean> true if signature is valid, false otherwise
 */
async function validateWebhookSignature(
  request: Request,
  body: string,
): Promise<boolean> {
  if (!APP_ID || !APP_SECRET) {
    log.warn("META_APP_ID or META_APP_SECRET environment variable not set");
    return false;
  }

  const ids = APP_ID.split("|");
  const secrets = APP_SECRET.split("|");

  if (ids.length !== secrets.length) {
    log.warn(
      "META_APP_ID and META_APP_SECRET environment variables must have the same number of elements, separated by '|'",
    );
    return false;
  }

  let idIndex = 0;

  const url = new URL(request.url);
  const appId = url.searchParams.get("app_id");

  if (appId) {
    idIndex = ids.indexOf(appId);

    if (idIndex === -1) {
      log.warn(
        `Could not find app_id '${appId}' in META_APP_ID environment variable`,
      );
      return false;
    }
  }

  const signature = request.headers.get("X-Hub-Signature-256");

  if (!signature) {
    log.warn("Missing X-Hub-Signature-256 header");
    return false;
  }

  const signatureValue = signature.replace("sha256=", "");

  try {
    // Create HMAC-SHA256 signature
    const encoder = new TextEncoder();
    const key = encoder.encode(secrets[idIndex]);
    const data = encoder.encode(body);

    const cryptoKey = await crypto.subtle.importKey(
      "raw",
      key,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );

    const signature = await crypto.subtle.sign("HMAC", cryptoKey, data);
    const expectedSignature = Array.from(new Uint8Array(signature))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // [crm] P2-01: both sides are fixed-length hex digests of a value Meta
    // controls, so a short-circuiting === leaks (via response timing) how
    // many leading characters an attacker's guess got right — classic
    // signature-comparison timing side channel. Compare every byte
    // regardless of where they first differ.
    const isValid = timingSafeEqualHex(signatureValue, expectedSignature);

    if (!isValid) {
      log.warn("Invalid webhook signature", {
        expected: expectedSignature,
        received: signatureValue,
      });
    }

    return isValid;
  } catch (error) {
    log.error(
      "Error validating webhook signature",
      error instanceof Error ? error.message : String(error),
    );
    return false;
  }
}

/**
 * [crm] P2-01: verify → dedupe → log the raw event → ack. Nothing here does
 * the actual processing (parsing, DB writes, media downloads) — that used to
 * run inline in this request, risking Meta's own delivery timeout on a slow
 * media download. whatsapp-webhook-processor (invoked by pg_cron, same
 * pattern as whatsapp-dispatcher) picks up unprocessed crm.webhook_events
 * rows asynchronously instead. See crm.webhook_events' schema file for the
 * retry/dead-letter design.
 */
async function ingestWebhook(request: Request): Promise<Response> {
  const body = await request.text();
  const isValidSignature = await validateWebhookSignature(request, body);
  const dedupeKey = await sha256Hex(body);

  const client = createUnsecureClient();

  // ON CONFLICT DO NOTHING + a `select` of what actually landed is how we
  // tell "new event" from "Meta retried the same delivery" — the two need
  // different log lines, but both still ack 200 so Meta stops retrying.
  const { data: inserted, error } = await client
    .schema("crm")
    .from("webhook_events")
    .insert({
      service: "whatsapp",
      dedupe_key: dedupeKey,
      raw_body: body,
      signature_valid: isValidSignature,
    })
    .select("id")
    .maybeSingle();

  if (error && error.code !== "23505") {
    log.error("Failed to store raw webhook event", { error: error.message });
    // Still ack: losing the raw-event log is better than Meta retry-storming
    // an endpoint that is already failing to write.
    return new Response();
  }

  if (!isValidSignature) {
    // Return 200 to prevent Meta from retrying. Common cause: the user deleted
    // their org but didn't remove the webhook from their Meta app configuration.
    return new Response();
  }

  if (!inserted) {
    log.info("Duplicate webhook delivery, already stored", { dedupeKey });
    return new Response();
  }

  log.info("Webhook event stored for async processing", {
    id: inserted.id,
    dedupeKey,
  });

  return new Response();
}
