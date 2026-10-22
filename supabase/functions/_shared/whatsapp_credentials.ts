// [crm] P2-02: the WhatsApp access token lives in Supabase Vault
// (crm.set_whatsapp_access_token / crm.get_whatsapp_access_token), never in
// organizations_addresses.extra directly -- extra has no column-level RLS,
// so any tenant member with row access could otherwise read a live Meta
// token straight through PostgREST.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "./types/database_types.ts";

// Shared system-user token, used when an address has no per-row token of
// its own (e.g. the Cloud API test number, wired directly through this env
// var rather than a per-tenant Vault secret).
const DEFAULT_ACCESS_TOKEN = Deno.env.get("META_SYSTEM_USER_ACCESS_TOKEN") ||
  "";

export async function getWhatsAppAccessToken(
  client: SupabaseClient<Database>,
  organization_id: string,
  address: string,
): Promise<string> {
  const { data, error } = await client
    .schema("crm")
    .rpc("get_whatsapp_access_token", {
      p_organization_id: organization_id,
      p_address: address,
    });

  if (error) throw error;

  return data || DEFAULT_ACCESS_TOKEN;
}

export async function setWhatsAppAccessToken(
  client: SupabaseClient<Database>,
  organization_id: string,
  address: string,
  access_token: string,
): Promise<void> {
  const { error } = await client
    .schema("crm")
    .rpc("set_whatsapp_access_token", {
      p_organization_id: organization_id,
      p_address: address,
      p_access_token: access_token,
    });

  if (error) throw error;
}
