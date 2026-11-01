// [crm] P2-05: the pure decision logic behind the outbound send gate --
// getting these wrong either blocks sends that should go through or lets
// through sends CLAUDE.md requires blocked (window/opt-in/quiet hours).
import { assertEquals } from "jsr:@std/assert@1.0.13";
import {
  categorizeMetaErrorCode,
  confirmationTextFor,
  isWindowOpen,
  isWithinQuietHours,
  matchesKeyword,
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
const OPT_IN_KEYWORDS = ["START", "SUBSCRIBE"];

Deno.test("matchesKeyword: an exact, case-insensitive match is caught", () => {
  assertEquals(matchesKeyword("stop", KEYWORDS), "STOP");
  assertEquals(matchesKeyword("  Stop  ", KEYWORDS), "STOP");
  assertEquals(matchesKeyword("UNSUBSCRIBE", KEYWORDS), "UNSUBSCRIBE");
});

Deno.test("matchesKeyword: the keyword mentioned inside a longer message does not match", () => {
  assertEquals(
    matchesKeyword(
      "please stop sending flyers, I'm in the middle of something",
      KEYWORDS,
    ),
    null,
  );
});

Deno.test("matchesKeyword: an unrelated message does not match", () => {
  assertEquals(matchesKeyword("thanks, see you then", KEYWORDS), null);
});

Deno.test("matchesKeyword: also works for the opt-in list (P4-02)", () => {
  assertEquals(matchesKeyword("start", OPT_IN_KEYWORDS), "START");
  assertEquals(matchesKeyword("stop", OPT_IN_KEYWORDS), null);
});

Deno.test("confirmationTextFor: English for a Latin-script matched keyword", () => {
  assertEquals(
    confirmationTextFor("opted_out", "STOP"),
    "You've been unsubscribed and won't receive further messages. Reply START anytime to resubscribe.",
  );
  assertEquals(
    confirmationTextFor("opted_in", "START"),
    "You're now subscribed to receive messages from us. Reply STOP anytime to unsubscribe.",
  );
});

Deno.test("confirmationTextFor: Hindi for a Devanagari-script matched keyword", () => {
  assertEquals(
    confirmationTextFor("opted_out", "बंद"),
    "आपको अनसब्सक्राइब कर दिया गया है और अब आपको संदेश नहीं मिलेंगे। फिर से सदस्यता लेने के लिए कभी भी START भेजें।",
  );
  assertEquals(
    confirmationTextFor("opted_in", "शुरू"),
    "अब आप हमसे संदेश प्राप्त करने के लिए सब्सक्राइब हो गए हैं। अनसब्सक्राइब करने के लिए कभी भी STOP भेजें।",
  );
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
