import { assertEquals } from "jsr:@std/assert@1.0.13";
import { maskEmail, statusForPgError, validatePayload } from "./lib.ts";

Deno.test("maskEmail keeps only the first letter and the domain", () => {
  assertEquals(maskEmail("priya.sharma@example.com"), "p***@example.com");
  assertEquals(maskEmail("nope"), "***");
});

Deno.test("statusForPgError maps the invite errors", () => {
  assertEquals(statusForPgError("42501"), 403);
  assertEquals(statusForPgError("23505"), 409);
  assertEquals(statusForPgError("22023"), 400);
  assertEquals(statusForPgError(undefined), 500);
});

Deno.test("validatePayload", () => {
  assertEquals(
    validatePayload({
      organization_id: "3a182d8d-d6d8-44bd-b021-029915476b8c",
      email: "a@b.co",
      role_key: "viewer",
    }),
    null,
  );
  assertEquals(
    validatePayload({ organization_id: "x", email: "a@b.co", role_key: "v" }),
    "organization_id must be a uuid",
  );
  assertEquals(validatePayload(null), "JSON body required");
});
