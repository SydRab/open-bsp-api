import { assertEquals } from "jsr:@std/assert@1.0.13";
import { sha256Hex, timingSafeEqualHex } from "./lib.ts";

Deno.test("timingSafeEqualHex: equal strings are equal", () => {
  assertEquals(timingSafeEqualHex("abc123", "abc123"), true);
});

Deno.test("timingSafeEqualHex: different strings are not equal", () => {
  assertEquals(timingSafeEqualHex("abc123", "abc124"), false);
  assertEquals(timingSafeEqualHex("abc123", "ZZZ123"), false);
});

Deno.test("timingSafeEqualHex: a difference anywhere is caught, not just the first byte", () => {
  assertEquals(timingSafeEqualHex("aaaaaa", "aaaaab"), false);
  assertEquals(timingSafeEqualHex("baaaaa", "aaaaaa"), false);
});

Deno.test("timingSafeEqualHex: different lengths are never equal", () => {
  assertEquals(timingSafeEqualHex("abc", "abcd"), false);
  assertEquals(timingSafeEqualHex("", "a"), false);
  assertEquals(timingSafeEqualHex("", ""), true);
});

Deno.test("sha256Hex: deterministic, 64 lowercase hex chars", async () => {
  const digest = await sha256Hex("hello");
  assertEquals(digest.length, 64);
  assertEquals(/^[0-9a-f]+$/.test(digest), true);
  assertEquals(
    digest,
    "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
  );
});

Deno.test("sha256Hex: different input, different digest", async () => {
  const a = await sha256Hex("payload-a");
  const b = await sha256Hex("payload-b");
  assertEquals(a === b, false);
});

Deno.test("sha256Hex: same input, same digest (dedupe depends on this)", async () => {
  const a = await sha256Hex("retry-of-the-same-webhook-body");
  const b = await sha256Hex("retry-of-the-same-webhook-body");
  assertEquals(a, b);
});
