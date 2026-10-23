// [crm] P2-10: the three flagging/throttling decisions are the business
// logic worth isolating here -- same reasoning as token_health_test.ts.
import { assertEquals } from "jsr:@std/assert@1.0.13";
import {
  effectivePacing,
  isLimitDowngraded,
  isQualityDegraded,
} from "./number_health.ts";

Deno.test("isQualityDegraded: no prior data is never a degradation", () => {
  assertEquals(isQualityDegraded(null, "RED"), false);
  assertEquals(isQualityDegraded(undefined, "RED"), false);
});

Deno.test("isQualityDegraded: GREEN to YELLOW is a degradation", () => {
  assertEquals(isQualityDegraded("GREEN", "YELLOW"), true);
});

Deno.test("isQualityDegraded: YELLOW to RED is a degradation", () => {
  assertEquals(isQualityDegraded("YELLOW", "RED"), true);
});

Deno.test("isQualityDegraded: GREEN to RED is a degradation", () => {
  assertEquals(isQualityDegraded("GREEN", "RED"), true);
});

Deno.test("isQualityDegraded: staying RED is not a NEW degradation", () => {
  assertEquals(isQualityDegraded("RED", "RED"), false);
});

Deno.test("isQualityDegraded: improving (RED to GREEN) is not a degradation", () => {
  assertEquals(isQualityDegraded("RED", "GREEN"), false);
});

Deno.test("isQualityDegraded: an unrecognized rating on either side is never flagged", () => {
  assertEquals(isQualityDegraded("UNKNOWN", "GREEN"), false);
  assertEquals(isQualityDegraded("GREEN", "NA"), false);
});

Deno.test("isLimitDowngraded: no prior data is never a downgrade", () => {
  assertEquals(isLimitDowngraded(null, "TIER_50"), false);
});

Deno.test("isLimitDowngraded: TIER_10K to TIER_2K is a downgrade", () => {
  assertEquals(isLimitDowngraded("TIER_10K", "TIER_2K"), true);
});

Deno.test("isLimitDowngraded: TIER_NOT_SET to any real tier is an upgrade, not a downgrade", () => {
  assertEquals(isLimitDowngraded("TIER_NOT_SET", "TIER_50"), false);
});

Deno.test("isLimitDowngraded: an upgrade (TIER_50 to TIER_250) is not a downgrade", () => {
  assertEquals(isLimitDowngraded("TIER_50", "TIER_250"), false);
});

Deno.test("isLimitDowngraded: same tier twice is not a NEW downgrade", () => {
  assertEquals(isLimitDowngraded("TIER_2K", "TIER_2K"), false);
});

const DEFAULTS = { capacity: 5, refillPerSecond: 1 };

Deno.test("effectivePacing: no signal uses the defaults unchanged", () => {
  assertEquals(effectivePacing(null, null, DEFAULTS), DEFAULTS);
  assertEquals(effectivePacing("GREEN", "TIER_10K", DEFAULTS), DEFAULTS);
});

Deno.test("effectivePacing: RED quality throttles hardest, regardless of tier", () => {
  assertEquals(effectivePacing("RED", "TIER_UNLIMITED", DEFAULTS), {
    capacity: 1,
    refillPerSecond: 0.2,
  });
});

Deno.test("effectivePacing: YELLOW quality eases off", () => {
  assertEquals(effectivePacing("YELLOW", "TIER_10K", DEFAULTS), {
    capacity: 2,
    refillPerSecond: 0.5,
  });
});

Deno.test("effectivePacing: a low tier eases off even with good/unknown quality", () => {
  assertEquals(effectivePacing("GREEN", "TIER_50", DEFAULTS), {
    capacity: 2,
    refillPerSecond: 0.5,
  });
  assertEquals(effectivePacing(null, "TIER_NOT_SET", DEFAULTS), {
    capacity: 2,
    refillPerSecond: 0.5,
  });
});

Deno.test("effectivePacing: RED quality wins over a high tier -- the worse signal decides", () => {
  assertEquals(effectivePacing("RED", "TIER_100K", DEFAULTS), {
    capacity: 1,
    refillPerSecond: 0.2,
  });
});
