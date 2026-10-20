// Pure helpers for crm-invitations, kept apart so they can be unit tested.

/** "priya.sharma@example.com" → "p***@example.com". Never log a full email. */
export function maskEmail(email: string): string {
  const at = email.lastIndexOf("@");
  if (at <= 0) return "***";
  return `${email[0]}***${email.slice(at)}`;
}

/**
 * HTTP status for an error raised by crm.invite_member. The function raises
 * with explicit SQLSTATEs (supabase/schemas/10_crm/10-12_members.sql).
 */
export function statusForPgError(code: string | undefined): number {
  switch (code) {
    case "42501": // insufficient privilege
      return 403;
    case "23505": // already a member / already invited
      return 409;
    case "22023": // invalid parameter (bad email, unknown role)
    case "22P02": // malformed uuid
      return 400;
    case "P0002": // not found
      return 404;
    default:
      return 500;
  }
}

export type InvitePayload = {
  organization_id: string;
  email: string;
  role_key: string;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Validates the request body shape. Returns an error message or null. */
export function validatePayload(body: unknown): string | null {
  if (typeof body !== "object" || body === null) return "JSON body required";
  const b = body as Record<string, unknown>;
  if (typeof b.organization_id !== "string" || !UUID.test(b.organization_id)) {
    return "organization_id must be a uuid";
  }
  if (typeof b.email !== "string" || !b.email.includes("@")) {
    return "email is required";
  }
  if (typeof b.role_key !== "string" || b.role_key === "") {
    return "role_key is required";
  }
  return null;
}
