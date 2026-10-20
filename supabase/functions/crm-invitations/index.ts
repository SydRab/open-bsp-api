// crm-invitations (P1-03): invite someone to an organization with a crm role
// and email them.
//
//   POST /crm-invitations
//   Authorization: Bearer <user JWT>
//   { "organization_id": uuid, "email": string, "role_key": string }
//   → 201 { invitation_id, email_delivery: "invite" | "magic_link" | "failed" }
//
// The invitation is created by crm.invite_member AS THE CALLER, so the
// database decides who may invite whom (members.invite, tier limits). Only
// the email step uses the service role:
// - a new address gets Supabase Auth's invite email (creates the auth user):
//   https://supabase.com/docs/reference/javascript/auth-admin-inviteuserbyemail
// - an existing user gets a sign-in link; after signing in they see the
//   pending invitation and accept it in the app:
//   https://supabase.com/docs/reference/javascript/auth-signinwithotp
// If the email fails the invitation still stands and shows up in the app.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient as createClientBase } from "@supabase/supabase-js";
import * as log from "../_shared/logger.ts";
import { createClient, createUnsecureClient } from "../_shared/supabase.ts";
import {
  type InvitePayload,
  maskEmail,
  statusForPgError,
  validatePayload,
} from "./lib.ts";

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

async function sendEmail(
  email: string,
): Promise<"invite" | "magic_link" | "failed"> {
  const redirectTo = Deno.env.get("CRM_APP_URL") || undefined;
  const admin = createUnsecureClient();

  const { error } = await admin.auth.admin.inviteUserByEmail(email, {
    redirectTo,
  });
  if (!error) return "invite";

  if (error.code !== "email_exists") {
    log.warn("crm-invitations: invite email failed", {
      code: error.code,
      status: error.status,
    });
    return "failed";
  }

  // Already has an account: send a sign-in link instead.
  const anon = createClientBase(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { auth: { persistSession: false } },
  );
  const { error: otpError } = await anon.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: false, emailRedirectTo: redirectTo },
  });
  if (otpError) {
    log.warn("crm-invitations: sign-in email failed", {
      code: otpError.code,
      status: otpError.status,
    });
    return "failed";
  }
  return "magic_link";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ message: "method not allowed" }, 405);
  }

  const requestId = crypto.randomUUID();

  let body: InvitePayload;
  try {
    body = await req.json();
  } catch {
    return json({ message: "JSON body required" }, 400);
  }
  const invalid = validatePayload(body);
  if (invalid) return json({ message: invalid }, 400);

  let supabase;
  try {
    supabase = createClient(req);
  } catch {
    return json({ message: "authentication required" }, 401);
  }

  const { data: invitationId, error } = await supabase
    .schema("crm")
    .rpc("invite_member", {
      p_organization_id: body.organization_id,
      p_email: body.email,
      p_role_key: body.role_key,
    });

  if (error) {
    const status = statusForPgError(error.code);
    log.warn("crm-invitations: invite refused", {
      request_id: requestId,
      tenant_id: body.organization_id,
      code: error.code,
      status,
    });
    return json(
      {
        message: status === 500 ? "could not create invitation" : error.message,
      },
      status,
    );
  }

  const email = body.email.trim().toLowerCase();
  const delivery = await sendEmail(email);

  log.info("crm-invitations: invited", {
    request_id: requestId,
    tenant_id: body.organization_id,
    invitation_id: invitationId,
    email: maskEmail(email),
    email_delivery: delivery,
  });

  return json({ invitation_id: invitationId, email_delivery: delivery }, 201);
});
