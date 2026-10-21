// crm-admin (P1-10): the super-admin console's one endpoint. Every admin
// action goes through here — never through a crm function granted to
// `authenticated` — so there is one place that checks the caller is a
// platform admin before anything cross-tenant happens.
//
//   POST /crm-admin
//   Authorization: Bearer <user JWT>
//   { "action": "<name>", ...action-specific fields }
//   → 200 { data }  |  4xx/5xx { message }
//
// Flow: verify the caller's own JWT and self-check crm.is_platform_admin()
// with their own client (so a non-admin gets refused before anything else
// happens); only then switch to the service-role client and call the
// database function. Mirrors crm-invitations' two-client pattern.
//
// Platform admins are a separate axis from tenant roles (crm.permissions):
// see supabase/schemas/10_crm/10-27_admin.sql.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import * as log from "../_shared/logger.ts";
import { createClient, createUnsecureClient } from "../_shared/supabase.ts";
import { ACTIONS, PLATFORM_AUDIT_ACTION, statusForPgError } from "./lib.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ message: "method not allowed" }, 405);
  }

  const requestId = crypto.randomUUID();

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ message: "JSON body required" }, 400);
  }

  if (typeof body.action !== "string" || !ACTIONS[body.action]) {
    return json({ message: "unknown action" }, 400);
  }
  const action = body.action;
  const entry = ACTIONS[action];

  let userClient;
  try {
    userClient = createClient(req);
  } catch {
    return json({ message: "authentication required" }, 401);
  }

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return json({ message: "authentication required" }, 401);
  }
  const adminId = userData.user.id;

  const { data: isAdmin, error: adminCheckError } = await userClient
    .schema("crm")
    .rpc("is_platform_admin");
  if (adminCheckError || !isAdmin) {
    log.warn("crm-admin: refused, not a platform admin", {
      request_id: requestId,
      action,
      user_id: adminId,
    });
    return json({ message: "platform admin access required" }, 403);
  }

  const built = entry.build(body, adminId);
  if ("error" in built) {
    return json({ message: built.error }, 400);
  }

  const admin = createUnsecureClient();
  // The RPC name is a dynamic dispatch key (one of ACTIONS' entries, each
  // already validated above), not a literal the generated overload can
  // narrow from — a single documented cast on the client's declared type
  // (through unknown: the real return type is a thenable query builder, not
  // a plain Promise), not a loosening of the real request validation; the
  // database is still what actually checks args. Called as `client.rpc(...)`
  // rather than a detached `const rpc = client.rpc`, which loses the
  // PostgrestClient's internal `this` and breaks at runtime.
  const client = admin.schema("crm") as unknown as {
    rpc: (
      name: string,
      args: Record<string, unknown>,
      // deno-lint-ignore no-explicit-any
    ) => Promise<{ data: any; error: { message: string; code?: string } | null }>;
  };
  const { data, error } = await client.rpc(entry.rpc, built.args);

  if (error) {
    const status = statusForPgError(error.code);
    log.warn("crm-admin: action refused", {
      request_id: requestId,
      action,
      admin_id: adminId,
      code: error.code,
      status,
    });
    return json(
      { message: status === 500 ? "the action could not be completed" : error.message },
      status,
    );
  }

  const platformAction = PLATFORM_AUDIT_ACTION[action];
  if (platformAction) {
    const { error: auditError } = await admin.schema("crm").rpc("write_platform_audit", {
      p_admin_id: adminId,
      p_action: platformAction,
      p_target_type: "organization",
      p_target_id: typeof body.organization_id === "string" ? body.organization_id : undefined,
      p_details: typeof body.feature_key === "string" ? { feature_key: body.feature_key } : {},
    });
    if (auditError) {
      // The action already succeeded; a missed platform-log entry is not
      // worth failing the request over, but it is worth knowing about.
      log.error("crm-admin: action succeeded but platform audit write failed", {
        request_id: requestId,
        action,
        message: auditError.message,
      });
    }
  }

  log.info("crm-admin: action completed", {
    request_id: requestId,
    action,
    admin_id: adminId,
  });

  return json({ data }, 200);
});
