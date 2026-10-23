// [crm] P2-11: validateBusinessProfile is the one piece of business logic
// worth isolating here -- same reasoning as interactive_messages_test.ts
// (local pre-validation of Meta's documented limits, so a bad request
// fails fast instead of a wasted round-trip).
import { assertEquals } from "jsr:@std/assert@1.0.13";
import { validateBusinessProfile } from "./business_profile.ts";

Deno.test("validateBusinessProfile: all fields empty/absent is valid", () => {
  assertEquals(validateBusinessProfile({}), null);
});

Deno.test("validateBusinessProfile: about within 1-139 chars is valid", () => {
  assertEquals(validateBusinessProfile({ about: "We sell shoes." }), null);
});

Deno.test("validateBusinessProfile: empty about is rejected (1 char minimum)", () => {
  assertEquals(
    validateBusinessProfile({ about: "" }),
    "about must be 1-139 characters",
  );
});

Deno.test("validateBusinessProfile: about over 139 chars is rejected", () => {
  assertEquals(
    validateBusinessProfile({ about: "a".repeat(140) }),
    "about must be 1-139 characters",
  );
});

Deno.test("validateBusinessProfile: address over 256 chars is rejected", () => {
  assertEquals(
    validateBusinessProfile({ address: "a".repeat(257) }),
    "address must be 256 characters or fewer",
  );
});

Deno.test("validateBusinessProfile: description over 512 chars is rejected", () => {
  assertEquals(
    validateBusinessProfile({ description: "a".repeat(513) }),
    "description must be 512 characters or fewer",
  );
});

Deno.test("validateBusinessProfile: a malformed email is rejected", () => {
  assertEquals(
    validateBusinessProfile({ email: "not-an-email" }),
    "email is not a valid address",
  );
});

Deno.test("validateBusinessProfile: an empty email string is allowed (clears the field)", () => {
  assertEquals(validateBusinessProfile({ email: "" }), null);
});

Deno.test("validateBusinessProfile: a valid email is accepted", () => {
  assertEquals(validateBusinessProfile({ email: "hello@example.com" }), null);
});

Deno.test("validateBusinessProfile: an unrecognized vertical is rejected", () => {
  assertEquals(
    validateBusinessProfile({ vertical: "NOT_A_REAL_VERTICAL" }),
    "vertical must be empty or one of: ALCOHOL, APPAREL, AUTO, BEAUTY, EDU, ENTERTAIN, EVENT_PLAN, FINANCE, GOVT, GROCERY, HEALTH, HOTEL, NONPROFIT, ONLINE_GAMBLING, OTC_DRUGS, OTHER, PHYSICAL_GAMBLING, PROF_SERVICES, RESTAURANT, RETAIL, TRAVEL",
  );
});

Deno.test("validateBusinessProfile: an empty vertical string clears the field", () => {
  assertEquals(validateBusinessProfile({ vertical: "" }), null);
});

Deno.test("validateBusinessProfile: a known vertical is accepted", () => {
  assertEquals(validateBusinessProfile({ vertical: "RETAIL" }), null);
});

Deno.test("validateBusinessProfile: more than 2 websites is rejected", () => {
  assertEquals(
    validateBusinessProfile({
      websites: [
        "https://a.example",
        "https://b.example",
        "https://c.example",
      ],
    }),
    "at most 2 websites are allowed",
  );
});

Deno.test("validateBusinessProfile: a website missing http(s):// is rejected", () => {
  assertEquals(
    validateBusinessProfile({ websites: ["example.com"] }),
    "each website must start with http:// or https://",
  );
});

Deno.test("validateBusinessProfile: two valid websites are accepted", () => {
  assertEquals(
    validateBusinessProfile({
      websites: ["https://example.com", "http://other.example"],
    }),
    null,
  );
});
