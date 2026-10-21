// Pure helpers for crm-admin, kept apart so they can be unit tested.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(v: unknown): v is string {
  return typeof v === "string" && UUID.test(v);
}

/**
 * HTTP status for an error raised by a crm admin function. The functions
 * raise with explicit SQLSTATEs (supabase/schemas/10_crm/10-28_admin_resolution.sql
 * and the P1-01/P1-05/P1-09 functions this console also calls).
 */
export function statusForPgError(code: string | undefined): number {
  switch (code) {
    case "42501": // insufficient privilege (not a platform admin, or no grant)
      return 403;
    case "23505": // duplicate
      return 409;
    case "22023": // invalid parameter
    case "22P02": // malformed uuid
      return 400;
    case "P0002": // not found
      return 404;
    default:
      return 500;
  }
}

export type ActionResult = { error: string } | { args: Record<string, unknown> };

/**
 * One entry per action: which crm function it calls, and how to build that
 * function's arguments from the request body plus the caller's own user id
 * (service-role calls carry no auth.uid(), so every mutating function takes
 * the acting admin's id explicitly). Returns an error message instead of
 * args when the body is missing something the function needs — this is
 * deliberately light: the database is still the real validator (lengths,
 * formats, business rules), this just avoids an obviously-wrong RPC call.
 */
export const ACTIONS: Record<
  string,
  { rpc: string; build: (body: Record<string, unknown>, adminId: string) => ActionResult }
> = {
  list_tenants: {
    rpc: "list_tenants",
    build: (b) => ({ args: { p_search: typeof b.search === "string" ? b.search : null } }),
  },
  suspend: {
    rpc: "suspend_organization",
    build: (b) => {
      if (!isUuid(b.organization_id)) return { error: "organization_id must be a uuid" };
      return {
        args: {
          p_organization_id: b.organization_id,
          p_reason: typeof b.reason === "string" ? b.reason : null,
        },
      };
    },
  },
  reactivate: {
    rpc: "reactivate_organization",
    build: (b) => {
      if (!isUuid(b.organization_id)) return { error: "organization_id must be a uuid" };
      return { args: { p_organization_id: b.organization_id } };
    },
  },
  set_feature_override: {
    rpc: "set_organization_feature",
    build: (b) => {
      if (!isUuid(b.organization_id)) return { error: "organization_id must be a uuid" };
      if (typeof b.feature_key !== "string" || b.feature_key === "") {
        return { error: "feature_key is required" };
      }
      if (typeof b.enabled !== "boolean") return { error: "enabled must be true or false" };
      return {
        args: {
          p_organization_id: b.organization_id,
          p_feature_key: b.feature_key,
          p_enabled: b.enabled,
          p_reason: typeof b.reason === "string" ? b.reason : null,
          p_expires_at: typeof b.expires_at === "string" ? b.expires_at : null,
        },
      };
    },
  },
  clear_feature_override: {
    rpc: "clear_organization_feature",
    build: (b) => {
      if (!isUuid(b.organization_id)) return { error: "organization_id must be a uuid" };
      if (typeof b.feature_key !== "string" || b.feature_key === "") {
        return { error: "feature_key is required" };
      }
      return { args: { p_organization_id: b.organization_id, p_feature_key: b.feature_key } };
    },
  },
  set_kill_switch: {
    rpc: "set_feature_kill_switch",
    build: (b) => {
      if (typeof b.feature_key !== "string" || b.feature_key === "") {
        return { error: "feature_key is required" };
      }
      if (typeof b.enabled !== "boolean") return { error: "enabled must be true or false" };
      return { args: { p_feature_key: b.feature_key, p_enabled: b.enabled } };
    },
  },
  set_tier: {
    rpc: "set_organization_tier",
    build: (b, adminId) => {
      if (!isUuid(b.organization_id)) return { error: "organization_id must be a uuid" };
      if (typeof b.tier_id !== "string" || b.tier_id === "") {
        return { error: "tier_id is required" };
      }
      return {
        args: { p_organization_id: b.organization_id, p_tier_id: b.tier_id, p_admin_id: adminId },
      };
    },
  },
  upgrade_pack: {
    rpc: "admin_upgrade_organization_pack",
    build: (b, adminId) => {
      if (!isUuid(b.organization_id)) return { error: "organization_id must be a uuid" };
      return {
        args: {
          p_organization_id: b.organization_id,
          p_version: typeof b.version === "number" ? b.version : null,
          p_admin_id: adminId,
        },
      };
    },
  },
  grant_support_access: {
    rpc: "grant_support_access",
    build: (b, adminId) => {
      if (!isUuid(b.organization_id)) return { error: "organization_id must be a uuid" };
      if (typeof b.reason !== "string" || b.reason === "") return { error: "reason is required" };
      return {
        args: {
          p_organization_id: b.organization_id,
          p_admin_id: adminId,
          p_reason: b.reason,
          p_hours: typeof b.hours === "number" ? b.hours : 24,
        },
      };
    },
  },
  revoke_support_access: {
    rpc: "revoke_support_access",
    build: (b, adminId) => {
      if (!isUuid(b.grant_id)) return { error: "grant_id must be a uuid" };
      return { args: { p_grant_id: b.grant_id, p_admin_id: adminId } };
    },
  },
  list_support_access: {
    rpc: "get_support_access",
    build: (b) => ({
      args: { p_organization_id: isUuid(b.organization_id) ? b.organization_id : null },
    }),
  },
  get_tenant_config: {
    rpc: "admin_get_tenant_config",
    build: (b, adminId) => {
      if (!isUuid(b.organization_id)) return { error: "organization_id must be a uuid" };
      return { args: { p_organization_id: b.organization_id, p_admin_id: adminId } };
    },
  },
  get_tenant_audit_log: {
    rpc: "admin_get_audit_log",
    build: (b, adminId) => {
      if (!isUuid(b.organization_id)) return { error: "organization_id must be a uuid" };
      return {
        args: {
          p_organization_id: b.organization_id,
          p_admin_id: adminId,
          p_before_id: typeof b.before_id === "number" ? b.before_id : null,
          p_limit: typeof b.limit === "number" ? b.limit : 50,
        },
      };
    },
  },
  list_platform_admins: {
    rpc: "list_platform_admins",
    build: () => ({ args: {} }),
  },
  grant_platform_admin: {
    rpc: "grant_platform_admin",
    build: (b, adminId) => {
      if (typeof b.email !== "string" || !b.email.includes("@")) {
        return { error: "email is required" };
      }
      return { args: { p_email: b.email, p_granted_by: adminId } };
    },
  },
  revoke_platform_admin: {
    rpc: "revoke_platform_admin",
    build: (b, adminId) => {
      if (!isUuid(b.user_id)) return { error: "user_id must be a uuid" };
      return { args: { p_user_id: b.user_id, p_revoked_by: adminId } };
    },
  },
  get_platform_audit_log: {
    rpc: "get_platform_audit_log",
    build: (b) => ({
      args: {
        p_before_id: typeof b.before_id === "number" ? b.before_id : null,
        p_limit: typeof b.limit === "number" ? b.limit : 50,
      },
    }),
  },
};

/**
 * These actions reach crm functions that predate crm.platform_audit_log
 * (suspend/reactivate from P1-01, the three feature ones from P1-09) and so
 * never attribute an admin themselves; crm-admin logs them with a direct
 * crm.write_platform_audit call after they succeed. Everything else already
 * writes its own platform_audit_log entry inside the database function.
 */
export const PLATFORM_AUDIT_ACTION: Record<string, string> = {
  suspend: "organization.suspended",
  reactivate: "organization.reactivated",
  set_feature_override: "feature.override_set",
  clear_feature_override: "feature.override_cleared",
  set_kill_switch: "feature.kill_switch_changed",
};
