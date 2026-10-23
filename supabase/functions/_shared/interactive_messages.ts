// [crm] P2-06: validates and builds the three outbound interactive message
// shapes (reply buttons, list, Flow invite) from this project's own, simpler
// internal representation (message_types.ts's Interactive*SendData) into
// Meta's exact wire format. Validation happens here, before
// whatsapp-dispatcher ever calls Meta -- a bad request fails fast with a
// clear message instead of a wasted API round-trip and a generic error
// code (100 / 131009, both "invalid-params" per _shared/send_policy.ts's
// categorizeMetaErrorCode).
//
// Limits verified directly against Meta's own docs, not third-party
// summaries:
// https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/interactive-reply-buttons-messages
// https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/interactive-list-messages
// https://developers.facebook.com/documentation/business-messaging/whatsapp/flows/guides/sendingaflow
import type {
  InteractiveButtonsSendData,
  InteractiveFlowSendData,
  InteractiveListSendData,
} from "./types/message_types.ts";
import type {
  OutgoingInteractiveButtons,
  OutgoingInteractiveFlow,
  OutgoingInteractiveList,
} from "./types/whatsapp_endpoint_types.ts";

class InteractiveMessageValidationError extends Error {}

function assertMaxLength(
  value: string | undefined,
  max: number,
  field: string,
): void {
  if (value !== undefined && value.length > max) {
    throw new InteractiveMessageValidationError(
      `${field} must be at most ${max} characters (got ${value.length})`,
    );
  }
}

export function buildInteractiveButtonsPayload(
  data: InteractiveButtonsSendData,
): OutgoingInteractiveButtons["interactive"] {
  if (data.buttons.length === 0) {
    throw new InteractiveMessageValidationError(
      "at least one button is required",
    );
  }
  if (data.buttons.length > 3) {
    throw new InteractiveMessageValidationError(
      `at most 3 buttons are allowed (got ${data.buttons.length})`,
    );
  }

  const seenTitles = new Set<string>();
  for (const button of data.buttons) {
    assertMaxLength(button.id, 256, "button id");
    assertMaxLength(button.title, 20, "button title");
    if (seenTitles.has(button.title)) {
      throw new InteractiveMessageValidationError(
        `button titles must be unique (duplicate: "${button.title}")`,
      );
    }
    seenTitles.add(button.title);
  }

  assertMaxLength(data.body, 1024, "body");
  assertMaxLength(data.footer, 60, "footer");
  assertMaxLength(data.header, 60, "header");

  return {
    type: "button",
    ...(data.header ? { header: { type: "text", text: data.header } } : {}),
    body: { text: data.body },
    ...(data.footer ? { footer: { text: data.footer } } : {}),
    action: {
      buttons: data.buttons.map((button) => ({
        type: "reply" as const,
        reply: button,
      })),
    },
  };
}

export function buildInteractiveListPayload(
  data: InteractiveListSendData,
): OutgoingInteractiveList["interactive"] {
  if (data.sections.length === 0) {
    throw new InteractiveMessageValidationError(
      "at least one section is required",
    );
  }
  if (data.sections.length > 10) {
    throw new InteractiveMessageValidationError(
      `at most 10 sections are allowed (got ${data.sections.length})`,
    );
  }

  let totalRows = 0;
  for (const section of data.sections) {
    assertMaxLength(section.title, 24, "section title");
    if (section.rows.length === 0) {
      throw new InteractiveMessageValidationError(
        `section "${section.title}" must have at least one row`,
      );
    }
    totalRows += section.rows.length;
    for (const row of section.rows) {
      assertMaxLength(row.id, 200, "row id");
      assertMaxLength(row.title, 24, "row title");
      assertMaxLength(row.description, 72, "row description");
    }
  }
  if (totalRows > 10) {
    throw new InteractiveMessageValidationError(
      `at most 10 rows are allowed across all sections combined (got ${totalRows})`,
    );
  }

  assertMaxLength(data.button, 20, "action.button");
  assertMaxLength(data.body, 4096, "body");
  assertMaxLength(data.footer, 60, "footer");
  assertMaxLength(data.header, 60, "header");

  return {
    type: "list",
    ...(data.header ? { header: { type: "text", text: data.header } } : {}),
    body: { text: data.body },
    ...(data.footer ? { footer: { text: data.footer } } : {}),
    action: {
      button: data.button,
      sections: data.sections,
    },
  };
}

export function buildInteractiveFlowPayload(
  data: InteractiveFlowSendData,
): OutgoingInteractiveFlow["interactive"] {
  assertMaxLength(data.flow_cta, 30, "flow_cta");
  assertMaxLength(data.body, 1024, "body");
  assertMaxLength(data.footer, 60, "footer");
  assertMaxLength(data.header, 60, "header");

  if (
    data.flow_action === "data_exchange" && data.flow_action_payload
  ) {
    throw new InteractiveMessageValidationError(
      "flow_action_payload must be omitted when flow_action is data_exchange",
    );
  }

  return {
    type: "flow",
    ...(data.header ? { header: { type: "text", text: data.header } } : {}),
    body: { text: data.body },
    ...(data.footer ? { footer: { text: data.footer } } : {}),
    action: {
      name: "flow",
      parameters: {
        ...("flow_id" in data
          ? { flow_id: data.flow_id }
          : { flow_name: data.flow_name }),
        flow_message_version: "3",
        flow_token: data.flow_token,
        flow_cta: data.flow_cta,
        ...(data.flow_action ? { flow_action: data.flow_action } : {}),
        ...(data.flow_action_payload
          ? { flow_action_payload: data.flow_action_payload }
          : {}),
        ...(data.mode ? { mode: data.mode } : {}),
      },
    },
  };
}
