// [crm] P2-04: crm.templates is a local cache of each connected number's
// Meta templates, not a source of truth of its own -- Meta always wins.
// Three independent paths keep it current: whatsapp-management's list/create
// calls (this file), the status/quality webhooks (whatsapp_webhook_processing.ts),
// and pack-template submission (embedded via whatsapp-management/templates.ts's
// submitPackTemplates). All of them write through the functions here so the
// upsert shape stays in one place.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, TemplateData } from "./supabase.ts";

/** Upserts one template row from a Graph API TemplateData object (list,
 * create, or edit response/request). pack_item_key is only written when
 * explicitly passed -- omitting it leaves an existing association alone,
 * since routine list syncs don't know which pack item (if any) a template
 * came from. */
export async function upsertTemplateFromMeta(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
  template: TemplateData,
  pack_item_key?: string,
): Promise<void> {
  await client
    .schema("crm")
    .from("templates")
    .upsert(
      {
        organization_id,
        organization_address,
        meta_id: template.id || null,
        name: template.name,
        category: template.category,
        language: template.language,
        status: template.status,
        components: template.components,
        synced_at: new Date().toISOString(),
        ...(pack_item_key !== undefined ? { pack_item_key } : {}),
      },
      { onConflict: "organization_id,organization_address,name,language" },
    )
    .throwOnError();
}

/** Applied by the message_template_status_update webhook. Matches by
 * meta_id -- globally unique on Meta's side, organization_id kept as a
 * defense-in-depth filter, not because it's load-bearing. If no row
 * matches (the webhook arrived before any sync ever ran, or the template
 * was created outside our UI), this is a no-op: the next list sync creates
 * the row properly rather than this writing a partial one with no
 * components. */
export async function updateTemplateStatus(
  client: SupabaseClient<Database>,
  organization_id: string,
  meta_id: string,
  status: string,
  rejection_reason: string | null,
): Promise<boolean> {
  const { data, error } = await client
    .schema("crm")
    .from("templates")
    .update({
      status,
      rejection_reason,
      synced_at: new Date().toISOString(),
    })
    .eq("organization_id", organization_id)
    .eq("meta_id", meta_id)
    .select("id")
    .maybeSingle();

  if (error) throw error;
  return !!data;
}

/** Applied by the message_template_quality_update webhook. Same matching
 * rules as updateTemplateStatus. */
export async function updateTemplateQuality(
  client: SupabaseClient<Database>,
  organization_id: string,
  meta_id: string,
  quality_score: string,
): Promise<boolean> {
  const { data, error } = await client
    .schema("crm")
    .from("templates")
    .update({
      quality_score,
      synced_at: new Date().toISOString(),
    })
    .eq("organization_id", organization_id)
    .eq("meta_id", meta_id)
    .select("id")
    .maybeSingle();

  if (error) throw error;
  return !!data;
}
