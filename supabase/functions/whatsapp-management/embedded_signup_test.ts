// [crm] P2-02: the mock credential-exchange branch of each Graph API helper.
// None of these take a Supabase client, so they're directly testable without
// a DB -- unlike performEmbeddedSignup itself, which orchestrates them
// alongside real DB writes and is exercised by a live smoke test instead
// (see README.md's "Local development before Business Verification clears").
import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.13";
import { HTTPException } from "jsr:@hono/hono/http-exception";
import {
  deregisterPhoneNumber,
  getBusinessAccessToken,
  getPhoneNumber,
  getWabaPhoneNumberId,
  MOCK_ACCESS_TOKEN,
  MOCK_APP_ID,
  MOCK_ERROR_CODE,
  normalizePhoneNumber,
  postInitDataSync,
  postRegisterPhoneNumber,
  postSubscribeToWebhooks,
} from "./embedded_signup.ts";

Deno.test("normalizePhoneNumber: strips everything but digits", () => {
  assertEquals(normalizePhoneNumber("+54 9 260 423 7115"), "5492604237115");
  assertEquals(normalizePhoneNumber("(555) 0100"), "5550100");
  assertEquals(normalizePhoneNumber("5550100"), "5550100");
});

Deno.test("getBusinessAccessToken: mock mode returns the sentinel token, no fetch", async () => {
  const token = await getBusinessAccessToken(
    MOCK_APP_ID,
    "anything",
    "mock-success-1",
  );
  assertEquals(token, MOCK_ACCESS_TOKEN);
});

Deno.test("getBusinessAccessToken: mock mode honors the forced-error code", async () => {
  const error = await assertRejects(
    () => getBusinessAccessToken(MOCK_APP_ID, "anything", MOCK_ERROR_CODE),
    HTTPException,
  );
  assertEquals(error.status, 502);
});

Deno.test("postSubscribeToWebhooks: mock mode succeeds without a real call", async () => {
  assertEquals(
    await postSubscribeToWebhooks(MOCK_ACCESS_TOKEN, "waba-1"),
    true,
  );
  // Also with a callback URL override requested -- still short-circuits.
  assertEquals(
    await postSubscribeToWebhooks(
      MOCK_ACCESS_TOKEN,
      "waba-1",
      "https://example.com/webhook",
      "verify-token",
    ),
    true,
  );
});

Deno.test("postRegisterPhoneNumber: mock mode succeeds", async () => {
  assertEquals(
    await postRegisterPhoneNumber(MOCK_ACCESS_TOKEN, "phone-1", "123456"),
    true,
  );
});

Deno.test("getPhoneNumber: mock mode echoes the requested id in canned data", async () => {
  const data = await getPhoneNumber(MOCK_ACCESS_TOKEN, "phone-1");
  assertEquals(data.id, "phone-1");
  assertEquals(data.code_verification_status, "VERIFIED");
  assertEquals(data.quality_rating, "GREEN");
  // 555-0100 is the reserved fictional US number block -- never a real
  // Meta sandbox "555" test number, so it can't be confused for one.
  assertEquals(data.display_phone_number, "+1 555 0100");
});

Deno.test("getWabaPhoneNumberId: mock mode derives a stable fake id from the waba_id", async () => {
  assertEquals(
    await getWabaPhoneNumberId(MOCK_ACCESS_TOKEN, "waba-123"),
    "mock-phone-waba-123",
  );
});

Deno.test("postInitDataSync: mock mode returns a success shape per sync type", async () => {
  const contacts = await postInitDataSync(
    MOCK_ACCESS_TOKEN,
    "phone-1",
    "contacts",
  );
  assertEquals(contacts.messaging_product, "whatsapp");
  assertEquals(contacts.request_id, "mock-request-contacts");

  const messages = await postInitDataSync(
    MOCK_ACCESS_TOKEN,
    "phone-1",
    "messages",
  );
  assertEquals(messages.request_id, "mock-request-messages");
});

Deno.test("deregisterPhoneNumber: mock mode succeeds without a real call", async () => {
  assertEquals(await deregisterPhoneNumber(MOCK_ACCESS_TOKEN, "phone-1"), true);
});
