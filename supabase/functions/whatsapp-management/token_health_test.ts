// [crm] P2-03: the flagging decision is the one piece of business logic in
// token_health.ts worth isolating -- getting it wrong either spams tenants
// with false "reconnect" prompts or silently misses a dead token.
import { assertEquals } from "jsr:@std/assert@1.0.13";
import { shouldFlagForReauth } from "./token_health.ts";

const DAY_MS = 24 * 60 * 60 * 1000;
const now = Date.now();

Deno.test("shouldFlagForReauth: an invalid token is always flagged, regardless of expiry", () => {
  assertEquals(shouldFlagForReauth(false, 0, now), true);
  assertEquals(
    shouldFlagForReauth(false, Math.floor((now + 365 * DAY_MS) / 1000), now),
    true,
  );
});

Deno.test("shouldFlagForReauth: valid with no expiry (0 = Meta's 'Never') is never flagged", () => {
  assertEquals(shouldFlagForReauth(true, 0, now), false);
});

Deno.test("shouldFlagForReauth: valid and far from expiry is not flagged", () => {
  const expires_at = Math.floor((now + 30 * DAY_MS) / 1000);
  assertEquals(shouldFlagForReauth(true, expires_at, now), false);
});

Deno.test("shouldFlagForReauth: valid but inside the 10-day window is flagged", () => {
  const expires_at = Math.floor((now + 5 * DAY_MS) / 1000);
  assertEquals(shouldFlagForReauth(true, expires_at, now), true);
});

Deno.test("shouldFlagForReauth: valid but already past expiry is flagged", () => {
  const expires_at = Math.floor((now - DAY_MS) / 1000);
  assertEquals(shouldFlagForReauth(true, expires_at, now), true);
});

Deno.test("shouldFlagForReauth: right at the 10-day boundary is flagged (<=, not <)", () => {
  const expires_at = Math.floor((now + 10 * DAY_MS) / 1000);
  assertEquals(shouldFlagForReauth(true, expires_at, now), true);
});
