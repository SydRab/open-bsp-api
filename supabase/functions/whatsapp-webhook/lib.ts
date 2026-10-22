// [crm] P2-01: pure helpers, split out of index.ts (which calls Deno.serve
// at module load — importing it from a test would start a server) so they
// are importable from lib_test.ts.

/** Constant-time comparison of two hex strings. A length mismatch is itself
 * conclusive (an attacker already knows the expected digest's length — it is
 * always 64 hex chars for HMAC-SHA256), so returning early there leaks
 * nothing useful; only an equal-length byte-by-byte compare needs to run in
 * constant time. */
export function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;

  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/** sha256 of the raw body, hex-encoded — Meta sends no per-delivery id, but
 * does resend byte-identical payloads on retry/timeout, so a body hash is
 * the correct idempotency key for crm.webhook_events. */
export async function sha256Hex(body: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(body),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
