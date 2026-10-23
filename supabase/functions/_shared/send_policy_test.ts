// [crm] P2-05: the pure decision logic behind the outbound send gate --
// getting these wrong either blocks sends that should go through or lets
// through sends CLAUDE.md requires blocked (window/opt-in/quiet hours).
import { assertEquals } from "jsr:@std/assert@1.0.13";
import {
  categorizeMetaErrorCode,
  isWindowOpen,
  isWithinQuietHours,
  matchesOptOutKeyword,
} from "./send_policy.ts";

const HOUR_MS = 60 * 60 * 1000;

Deno.test("isWindowOpen: no prior inbound message means the window is closed", () => {
  assertEquals(isWindowOpen(null), false);
});

Deno.test("isWindowOpen: a reply 1 hour ago is inside the window", () => {
  const now = new Date();
  const lastInboundAt = new Date(now.getTime() - 1 * HOUR_MS).toISOString();
  assertEquals(isWindowOpen(lastInboundAt, now), true);
});

Deno.test("isWindowOpen: a reply exactly 24 hours ago has closed the window", () => {
  const now = new Date();
  const lastInboundAt = new Date(now.getTime() - 24 * HOUR_MS).toISOString();
  assertEquals(isWindowOpen(lastInboundAt, now), false);
});

Deno.test("isWindowOpen: a reply 23h59m ago is still inside the window", () => {
  const now = new Date();
  const lastInboundAt = new Date(
    now.getTime() - (24 * HOUR_MS - 60_000),
  ).toISOString();
  assertEquals(isWindowOpen(lastInboundAt, now), true);
});

// Asia/Kolkata (UTC+5:30, no DST) for deterministic conversion by hand.
const KOLKATA = "Asia/Kolkata";
const DEFAULT_QUIET_HOURS = { start: "21:00", end: "09:00" }; // overnight wrap

Deno.test("isWithinQuietHours: overnight window, local 22:00 is inside it", () => {
  // Kolkata 2026-01-01 22:00 = UTC 2026-01-01 16:30
  const now = new Date("2026-01-01T16:30:00Z");
  assertEquals(isWithinQuietHours(DEFAULT_QUIET_HOURS, KOLKATA, now), true);
});

Deno.test("isWithinQuietHours: overnight window, local 05:00 (past midnight) is inside it", () => {
  // Kolkata 2026-01-01 05:00 = UTC 2025-12-31 23:30
  const now = new Date("2025-12-31T23:30:00Z");
  assertEquals(isWithinQuietHours(DEFAULT_QUIET_HOURS, KOLKATA, now), true);
});

Deno.test("isWithinQuietHours: overnight window, local 10:00 (just past end) is outside it", () => {
  // Kolkata 2026-01-01 10:00 = UTC 2026-01-01 04:30
  const now = new Date("2026-01-01T04:30:00Z");
  assertEquals(isWithinQuietHours(DEFAULT_QUIET_HOURS, KOLKATA, now), false);
});

Deno.test("isWithinQuietHours: overnight window, local 20:59 (just before start) is outside it", () => {
  // Kolkata 2026-01-01 20:59 = UTC 2026-01-01 15:29
  const now = new Date("2026-01-01T15:29:00Z");
  assertEquals(isWithinQuietHours(DEFAULT_QUIET_HOURS, KOLKATA, now), false);
});

Deno.test("isWithinQuietHours: a same-day (non-wrap) window works the other way", () => {
  const businessHours = { start: "09:00", end: "17:00" };

  // Kolkata 12:00 -> UTC 06:30: inside.
  assertEquals(
    isWithinQuietHours(
      businessHours,
      KOLKATA,
      new Date("2026-01-01T06:30:00Z"),
    ),
    true,
  );
  // Kolkata 20:00 -> UTC 14:30: outside.
  assertEquals(
    isWithinQuietHours(
      businessHours,
      KOLKATA,
      new Date("2026-01-01T14:30:00Z"),
    ),
    false,
  );
});

Deno.test("isWithinQuietHours: a zero-width window (start === end) is never quiet", () => {
  assertEquals(
    isWithinQuietHours({ start: "09:00", end: "09:00" }, KOLKATA, new Date()),
    false,
  );
});

const KEYWORDS = ["STOP", "UNSUBSCRIBE"];

Deno.test("matchesOptOutKeyword: an exact, case-insensitive match is caught", () => {
  assertEquals(matchesOptOutKeyword("stop", KEYWORDS), "STOP");
  assertEquals(matchesOptOutKeyword("  Stop  ", KEYWORDS), "STOP");
  assertEquals(matchesOptOutKeyword("UNSUBSCRIBE", KEYWORDS), "UNSUBSCRIBE");
});

Deno.test("matchesOptOutKeyword: the keyword mentioned inside a longer message does not match", () => {
  assertEquals(
    matchesOptOutKeyword(
      "please stop sending flyers, I'm in the middle of something",
      KEYWORDS,
    ),
    null,
  );
});

Deno.test("matchesOptOutKeyword: an unrelated message does not match", () => {
  assertEquals(matchesOptOutKeyword("thanks, see you then", KEYWORDS), null);
});

Deno.test("categorizeMetaErrorCode: known codes map to their named category", () => {
  assertEquals(categorizeMetaErrorCode(131047), "re-engagement");
  assertEquals(categorizeMetaErrorCode(131049), "marketing-limit");
  assertEquals(categorizeMetaErrorCode(131050), "undeliverable");
  assertEquals(categorizeMetaErrorCode(131009), "invalid-params");
  assertEquals(categorizeMetaErrorCode(130429), "rate-limit");
});

Deno.test("categorizeMetaErrorCode: an uncatalogued code falls back to 'other'", () => {
  assertEquals(categorizeMetaErrorCode(999999), "other");
});
