import { assertEquals } from "jsr:@std/assert@1.0.13";
import { ACTIONS, isUuid, statusForPgError } from "./lib.ts";

const ORG = "3a182d8d-d6d8-44bd-b021-029915476b8c";
const ADMIN = "7c8a9b2d-4e3f-5a6b-8c9d-0e1f2a3b4c5d";

Deno.test("isUuid", () => {
  assertEquals(isUuid(ORG), true);
  assertEquals(isUuid("not-a-uuid"), false);
  assertEquals(isUuid(undefined), false);
});

Deno.test("statusForPgError maps the admin errors", () => {
  assertEquals(statusForPgError("42501"), 403);
  assertEquals(statusForPgError("22023"), 400);
  assertEquals(statusForPgError("P0002"), 404);
  assertEquals(statusForPgError("23505"), 409);
  assertEquals(statusForPgError(undefined), 500);
});

Deno.test("list_tenants builds args with an optional search", () => {
  const result = ACTIONS.list_tenants.build({}, ADMIN);
  assertEquals(result, { args: { p_search: null } });
  assertEquals(
    ACTIONS.list_tenants.build({ search: "Jupiter" }, ADMIN),
    { args: { p_search: "Jupiter" } },
  );
});

Deno.test("suspend requires a uuid organization_id", () => {
  assertEquals(ACTIONS.suspend.build({}, ADMIN), {
    error: "organization_id must be a uuid",
  });
  assertEquals(
    ACTIONS.suspend.build({ organization_id: ORG, reason: "unpaid" }, ADMIN),
    { args: { p_organization_id: ORG, p_reason: "unpaid" } },
  );
});

Deno.test("set_feature_override validates enabled and feature_key", () => {
  assertEquals(
    ACTIONS.set_feature_override.build({ organization_id: ORG }, ADMIN),
    { error: "feature_key is required" },
  );
  assertEquals(
    ACTIONS.set_feature_override.build(
      { organization_id: ORG, feature_key: "ai_agents" },
      ADMIN,
    ),
    { error: "enabled must be true or false" },
  );
  assertEquals(
    ACTIONS.set_feature_override.build(
      { organization_id: ORG, feature_key: "ai_agents", enabled: true, reason: "beta" },
      ADMIN,
    ),
    {
      args: {
        p_organization_id: ORG,
        p_feature_key: "ai_agents",
        p_enabled: true,
        p_reason: "beta",
        p_expires_at: null,
      },
    },
  );
});

Deno.test("set_tier and upgrade_pack carry the acting admin's id", () => {
  assertEquals(
    ACTIONS.set_tier.build({ organization_id: ORG, tier_id: "pro" }, ADMIN),
    { args: { p_organization_id: ORG, p_tier_id: "pro", p_admin_id: ADMIN } },
  );
  assertEquals(
    ACTIONS.upgrade_pack.build({ organization_id: ORG }, ADMIN),
    { args: { p_organization_id: ORG, p_version: null, p_admin_id: ADMIN } },
  );
});

Deno.test("grant_support_access requires a reason and defaults hours to 24", () => {
  assertEquals(
    ACTIONS.grant_support_access.build({ organization_id: ORG }, ADMIN),
    { error: "reason is required" },
  );
  assertEquals(
    ACTIONS.grant_support_access.build(
      { organization_id: ORG, reason: "ticket #42" },
      ADMIN,
    ),
    {
      args: { p_organization_id: ORG, p_admin_id: ADMIN, p_reason: "ticket #42", p_hours: 24 },
    },
  );
});

Deno.test("grant_platform_admin takes an email, not a user id", () => {
  assertEquals(ACTIONS.grant_platform_admin.build({}, ADMIN), {
    error: "email is required",
  });
  assertEquals(
    ACTIONS.grant_platform_admin.build({ email: "new.admin@example.com" }, ADMIN),
    { args: { p_email: "new.admin@example.com", p_granted_by: ADMIN } },
  );
});

Deno.test("list_support_access and get_platform_audit_log need no required fields", () => {
  assertEquals(ACTIONS.list_support_access.build({}, ADMIN), {
    args: { p_organization_id: null },
  });
  assertEquals(ACTIONS.get_platform_audit_log.build({}, ADMIN), {
    args: { p_before_id: null, p_limit: 50 },
  });
});
