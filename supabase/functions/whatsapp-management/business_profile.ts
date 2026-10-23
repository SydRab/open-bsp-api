// [crm] P2-11: business profile management and display-name status.
// Verified against Meta's own docs directly, not third-party summaries:
// https://developers.facebook.com/docs/whatsapp/cloud-api/reference/business-profiles
// https://developers.facebook.com/documentation/business-messaging/whatsapp/display-names
//
// Profile PICTURE updates are a deliberate scope cut -- they go through a
// different mechanism entirely (profile_picture_handle, sourced from Meta's
// separate Resumable Upload API), a genuinely separate integration, not a
// field on this endpoint.
import { HTTPException } from "jsr:@hono/hono/http-exception";
import { ContentfulStatusCode } from "jsr:@hono/hono/utils/http-status";
import { MOCK_ACCESS_TOKEN } from "./embedded_signup.ts";

const API_VERSION = "v24.0";

export type BusinessProfileFields = {
  about?: string;
  address?: string;
  description?: string;
  email?: string;
  vertical?: string;
  websites?: string[];
};

// Meta's closed list for `vertical` -- empty string is also accepted
// (clears the field), handled separately by the caller, not listed here.
export const BUSINESS_PROFILE_VERTICALS = [
  "ALCOHOL",
  "APPAREL",
  "AUTO",
  "BEAUTY",
  "EDU",
  "ENTERTAIN",
  "EVENT_PLAN",
  "FINANCE",
  "GOVT",
  "GROCERY",
  "HEALTH",
  "HOTEL",
  "NONPROFIT",
  "ONLINE_GAMBLING",
  "OTC_DRUGS",
  "OTHER",
  "PHYSICAL_GAMBLING",
  "PROF_SERVICES",
  "RESTAURANT",
  "RETAIL",
  "TRAVEL",
] as const;

/** Pure: no network. Mirrors interactive_messages.ts's own convention of
 * validating every Meta-documented limit locally before ever calling Meta,
 * so a bad request fails fast with a specific message instead of a wasted
 * round-trip. Returns the first violation, or null when the fields are
 * all within Meta's documented limits. */
export function validateBusinessProfile(
  fields: BusinessProfileFields,
): string | null {
  if (
    fields.about !== undefined &&
    (fields.about.length < 1 || fields.about.length > 139)
  ) {
    return "about must be 1-139 characters";
  }

  if (fields.address !== undefined && fields.address.length > 256) {
    return "address must be 256 characters or fewer";
  }

  if (fields.description !== undefined && fields.description.length > 512) {
    return "description must be 512 characters or fewer";
  }

  if (fields.email !== undefined && fields.email.length > 0) {
    if (fields.email.length > 128) {
      return "email must be 128 characters or fewer";
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(fields.email)) {
      return "email is not a valid address";
    }
  }

  if (
    fields.vertical !== undefined &&
    fields.vertical !== "" &&
    !BUSINESS_PROFILE_VERTICALS.includes(
      fields.vertical as typeof BUSINESS_PROFILE_VERTICALS[number],
    )
  ) {
    return `vertical must be empty or one of: ${
      BUSINESS_PROFILE_VERTICALS.join(", ")
    }`;
  }

  if (fields.websites !== undefined) {
    if (fields.websites.length > 2) {
      return "at most 2 websites are allowed";
    }
    for (const url of fields.websites) {
      if (url.length > 256) {
        return "each website must be 256 characters or fewer";
      }
      if (!/^https?:\/\//.test(url)) {
        return "each website must start with http:// or https://";
      }
    }
  }

  return null;
}

export async function getBusinessProfile(
  business_access_token: string,
  phone_number_id: string,
): Promise<BusinessProfileFields> {
  if (business_access_token === MOCK_ACCESS_TOKEN) {
    return {
      about: "Mock business profile",
      vertical: "OTHER",
      websites: [],
    };
  }

  const fields = "about,address,description,email,vertical,websites";
  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${phone_number_id}/whatsapp_business_profile?fields=${fields}`,
    { headers: { Authorization: `Bearer ${business_access_token}` } },
  );

  if (!response.ok) {
    throw new HTTPException(response.status as ContentfulStatusCode, {
      message: "Could not get business profile",
      cause: await response.json().catch(() => ({})),
    });
  }

  const { data } = await response.json();
  return (data?.[0] ?? {}) as BusinessProfileFields;
}

export async function updateBusinessProfile(
  business_access_token: string,
  phone_number_id: string,
  fields: BusinessProfileFields,
): Promise<boolean> {
  const invalid = validateBusinessProfile(fields);
  if (invalid) {
    throw new HTTPException(400, { message: invalid });
  }

  if (business_access_token === MOCK_ACCESS_TOKEN) {
    return true;
  }

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${phone_number_id}/whatsapp_business_profile`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${business_access_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ messaging_product: "whatsapp", ...fields }),
    },
  );

  if (!response.ok) {
    throw new HTTPException(response.status as ContentfulStatusCode, {
      message: "Could not update business profile",
      cause: await response.json().catch(() => ({})),
    });
  }

  return (await response.json()).success;
}

export async function requestDisplayNameChange(
  business_access_token: string,
  phone_number_id: string,
  new_display_name: string,
): Promise<boolean> {
  if (business_access_token === MOCK_ACCESS_TOKEN) {
    return true;
  }

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${phone_number_id}?new_display_name=${
      encodeURIComponent(new_display_name)
    }`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${business_access_token}` },
    },
  );

  if (!response.ok) {
    throw new HTTPException(response.status as ContentfulStatusCode, {
      message: "Could not request display name change",
      cause: await response.json().catch(() => ({})),
    });
  }

  return (await response.json()).success;
}
