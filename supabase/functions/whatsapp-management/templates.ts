import type { Database, TemplateData } from "../_shared/supabase.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import * as log from "../_shared/logger.ts";
import { HTTPException } from "jsr:@hono/hono/http-exception";
import { ContentfulStatusCode } from "jsr:@hono/hono/utils/http-status";
import { getWhatsAppAccessToken } from "../_shared/whatsapp_credentials.ts";
import { upsertTemplateFromMeta } from "../_shared/whatsapp_templates.ts";

const API_VERSION = "v24.0";

async function getBusinessCredentials(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
): Promise<{ waba_id: string; access_token: string }> {
  const { data, error } = await client
    .from("organizations_addresses")
    .select("extra->>waba_id")
    .eq("organization_id", organization_id)
    .eq("address", organization_address)
    .single();

  if (error || !data) {
    log.error("Could not fetch business access token", error);
    throw new HTTPException(403, {
      message: "Could not fetch business access token",
      cause: error,
    });
  }

  // [crm] P2-02: the token lives in Supabase Vault, not in extra.
  const access_token = await getWhatsAppAccessToken(
    client,
    organization_id,
    organization_address,
  );

  return { waba_id: data.waba_id, access_token };
}

/** [crm] P2-04: fetches every template from Meta and upserts each into
 * crm.templates -- the UI reads the list from there now (fast, reflects
 * webhook-driven status/quality updates immediately), not from this call
 * directly. This is the manual "Sync" action; list/create/edit/delete all
 * keep the cache current on their own too. */
export async function syncTemplates(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
): Promise<{ synced: number }> {
  const { waba_id, access_token } = await getBusinessCredentials(
    client,
    organization_id,
    organization_address,
  );

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${waba_id}/message_templates`,
    {
      method: "GET",
      headers: { Authorization: `Bearer ${access_token}` },
    },
  );

  if (!response.ok) {
    throw new HTTPException(response.status as ContentfulStatusCode, {
      message: "Could not fetch templates",
      cause: await response.json().catch(() => ({})),
    });
  }

  // Meta wraps the list in `{ data: [...] }`.
  const { data: templates } = (await response.json()) as {
    data: TemplateData[];
  };

  for (const template of templates) {
    await upsertTemplateFromMeta(
      client,
      organization_id,
      organization_address,
      template,
    );
  }

  return { synced: templates.length };
}

export async function fetchTemplate(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
  template: TemplateData,
): Promise<TemplateData> {
  const { access_token } = await getBusinessCredentials(
    client,
    organization_id,
    organization_address,
  );

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${template.id}`,
    {
      method: "GET",
      headers: { Authorization: `Bearer ${access_token}` },
    },
  );

  if (!response.ok) {
    throw new HTTPException(response.status as ContentfulStatusCode, {
      message: "Could not fetch template",
      cause: await response.json().catch(() => ({})),
    });
  }

  return await response.json();
}

export async function createTemplate(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
  template: TemplateData,
  pack_item_key?: string,
): Promise<{
  id: string;
  status: string;
  category: string;
}> {
  const { waba_id, access_token } = await getBusinessCredentials(
    client,
    organization_id,
    organization_address,
  );

  const { name, category, language, components } = template;

  const filteredTemplate = {
    name,
    category,
    allow_category_change: true,
    language,
    components,
  };

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${waba_id}/message_templates`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(filteredTemplate),
    },
  );

  if (!response.ok) {
    throw new HTTPException(response.status as ContentfulStatusCode, {
      message: "Could not create template",
      cause: await response.json().catch(() => ({})),
    });
  }

  const created = await response.json() as {
    id: string;
    status: string;
    category: string;
  };

  // The create response doesn't echo the full object back -- build one from
  // what was submitted plus what Meta assigned (id, status).
  await upsertTemplateFromMeta(
    client,
    organization_id,
    organization_address,
    {
      ...template,
      id: created.id,
      status: created.status as TemplateData["status"],
    },
    pack_item_key,
  );

  return created;
}

export async function editTemplate(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
  template: TemplateData,
): Promise<{
  success: boolean;
}> {
  const { access_token } = await getBusinessCredentials(
    client,
    organization_id,
    organization_address,
  );

  const { category, components } = template;
  const filteredTemplate = { category, components };

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${template.id}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(filteredTemplate),
    },
  );

  if (!response.ok) {
    throw new HTTPException(response.status as ContentfulStatusCode, {
      message: "Could not update template",
      cause: await response.json().catch(() => ({})),
    });
  }

  const result = await response.json() as { success: boolean };

  // Editing triggers a new Meta review -- the template goes back to PENDING
  // until re-approved (the edit response itself is only {success}, with no
  // status of its own; the status/quality webhooks correct this once Meta
  // actually re-reviews it).
  await upsertTemplateFromMeta(
    client,
    organization_id,
    organization_address,
    { ...template, status: "PENDING" },
  );

  return result;
}

export async function deleteTemplate(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
  template: TemplateData,
): Promise<{
  success: boolean;
}> {
  const { waba_id, access_token } = await getBusinessCredentials(
    client,
    organization_id,
    organization_address,
  );

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${waba_id}/message_templates?name=${template.name}`,
    {
      method: "DELETE",
      headers: {
        Authorization: `Bearer ${access_token}`,
      },
    },
  );

  if (!response.ok) {
    throw new HTTPException(response.status as ContentfulStatusCode, {
      message: "Could not delete template",
      cause: await response.json().catch(() => ({})),
    });
  }

  // Deleting by name removes every language variant on Meta's side (the
  // call above carries no language) -- match that here.
  await client
    .schema("crm")
    .from("templates")
    .delete()
    .eq("organization_id", organization_id)
    .eq("organization_address", organization_address)
    .eq("name", template.name)
    .throwOnError();

  return await response.json();
}
