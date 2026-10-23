// [crm] P2-04: submits a pack's message_template items (crm.organization_pack_items,
// kind = 'message_template', shape documented in packs/trading_institute/v1.json)
// to Meta, one per language, so a tenant gets a working set of templates with
// one click instead of hand-typing each one in the editor.
import type { createClient, TemplateData } from "../_shared/supabase.ts";
import { Json } from "../_shared/db_types.ts";
import * as log from "../_shared/logger.ts";
import { HTTPException } from "jsr:@hono/hono/http-exception";
import { createTemplate } from "./templates.ts";

type Client = ReturnType<typeof createClient>;

type PackTemplateValue = {
  name: string;
  category: "MARKETING" | "UTILITY";
  attach_disclaimer?: boolean;
  languages: Record<string, { body: string; examples?: string[] }>;
};

/** Pure: builds the Meta-shaped template payload for one pack item in one
 * language. Exported for direct unit testing -- no client, no network. */
export function buildTemplateFromPackItem(
  item_key: string,
  value: PackTemplateValue,
  language: string,
  footer: string | null,
): TemplateData {
  const languageContent = value.languages[language];

  const components: TemplateData["components"] = [
    {
      type: "BODY",
      text: languageContent.body,
      ...(languageContent.examples?.length
        ? { example: { body_text: [languageContent.examples] } }
        : {}),
    },
  ];

  if (footer) {
    components.push({ type: "FOOTER", text: footer });
  }

  return {
    id: "",
    name: item_key,
    status: "PENDING",
    category: value.category,
    sub_category: "CUSTOM",
    language,
    components,
  };
}

export async function submitPackTemplates(
  client: Client,
  organization_id: string,
  organization_address: string,
): Promise<{ submitted: number; failed: number; skipped: number }> {
  const { data: items } = await client
    .schema("crm")
    .from("organization_pack_items")
    .select("item_key, value")
    .eq("organization_id", organization_id)
    .eq("kind", "message_template")
    .throwOnError();

  const { data: existing } = await client
    .schema("crm")
    .from("templates")
    .select("pack_item_key")
    .eq("organization_id", organization_id)
    .eq("organization_address", organization_address)
    .not("pack_item_key", "is", null)
    .throwOnError();

  const alreadySubmitted = new Set(
    (existing ?? []).map((row) => row.pack_item_key),
  );

  let submitted = 0;
  let failed = 0;
  let skipped = 0;

  for (const item of items ?? []) {
    if (alreadySubmitted.has(item.item_key)) {
      skipped++;
      continue;
    }

    const value = item.value as unknown as PackTemplateValue;

    for (const language of Object.keys(value.languages)) {
      let footer: string | null = null;

      if (value.attach_disclaimer) {
        const { data: disclaimer } = await client
          .schema("crm")
          .rpc("current_disclaimer", {
            p_organization_id: organization_id,
            p_kind: "short",
            p_locale: language,
          })
          .maybeSingle();

        footer = disclaimer?.text ?? null;

        if (!footer) {
          log.warn(
            `Pack template ${item.item_key} (${language}) wants the disclaimer attached, but no short disclaimer is set for that locale -- submitting without a footer`,
            { organization_id, item_key: item.item_key, language },
          );
        }
      }

      const template = buildTemplateFromPackItem(
        item.item_key,
        value,
        language,
        footer,
      );

      try {
        await createTemplate(
          client,
          organization_id,
          organization_address,
          template,
          item.item_key,
        );
        submitted++;
      } catch (error) {
        failed++;
        // Meta's actual rejection reason lives in an HTTPException's
        // `cause`, not its top-level `.message` -- same extraction as
        // embedded_signup.ts.
        const cause = error instanceof HTTPException ? error.cause : error;
        const message = error instanceof Error ? error.message : String(error);
        log.error("Failed to submit pack template", {
          organization_id,
          item_key: item.item_key,
          language,
          error: message,
          cause,
        });
        await client
          .from("logs")
          .insert({
            organization_id,
            organization_address,
            category: "template_pack_submit",
            service: "whatsapp",
            level: "error",
            message:
              `Could not submit pack template ${item.item_key} (${language})`,
            metadata: { error: message, cause } as Json,
          })
          .throwOnError();
      }
    }
  }

  return { submitted, failed, skipped };
}
