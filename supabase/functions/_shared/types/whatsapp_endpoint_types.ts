import type {
  ContactsMessage,
  LocationMessage,
} from "./whatsapp_webhook_message_types.ts";
import type { TemplateMessage } from "./whatsapp_template_types.ts";

//===================================
// Outgoing message components, as sent to the WhatsApp Cloud API
//===================================

export type OutgoingContextInfo = {
  context?: { message_id: string };
};

// Text based

export type OutgoingText = {
  type: "text";
  text: {
    body: string;
    preview_url?: boolean;
  };
};

export type OutgoingReaction = {
  type: "reaction";
  reaction: {
    emoji: string;
    message_id: string;
  };
};

// File based

export type OutgoingAudio = {
  type: "audio";
  audio: ({ id: string } | { link: string }) & { voice?: boolean };
};

export type OutgoingImage = {
  type: "image";
  image: ({ id: string } | { link: string }) & { caption?: string };
};

export type OutgoingVideo = {
  type: "video";
  video: ({ id: string } | { link: string }) & { caption?: string };
};

export type OutgoingDocument = {
  type: "document";
  document: ({ id: string } | { link: string }) & {
    caption?: string;
    filename?: string;
  };
};

export type OutgoingSticker = {
  type: "sticker";
  sticker: { id: string } | { link: string };
};

// Interactive (P2-06). Session messages only -- Meta rejects all three
// outside the 24h customer service window the same way a free-form text
// message would (the send gate's window check, _shared/send_policy.ts,
// already treats every non-template message the same way, so no change
// was needed there for these).
//
// Shapes verified directly against Meta's own docs, not the third-party
// summaries that turned up first:
// https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/interactive-reply-buttons-messages
// https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/interactive-list-messages
// https://developers.facebook.com/documentation/business-messaging/whatsapp/flows/guides/sendingaflow

export type OutgoingButtonHeader =
  | { type: "text"; text: string }
  | { type: "image"; image: { id: string } | { link: string } }
  | { type: "video"; video: { id: string } | { link: string } }
  | { type: "document"; document: { id: string } | { link: string } };

// Up to 3 buttons; each reply.id max 256 chars, reply.title max 20 chars.
// body.text max 1024, footer.text max 60. Enforced in
// _shared/interactive_messages.ts before this shape is ever built, not here
// -- these are the wire types, not the validator.
export type OutgoingInteractiveButtons = {
  type: "interactive";
  interactive: {
    type: "button";
    header?: OutgoingButtonHeader;
    body: { text: string };
    footer?: { text: string };
    action: {
      buttons: {
        type: "reply";
        reply: { id: string; title: string };
      }[];
    };
  };
};

// 1-10 sections, 10 rows max across all sections combined. action.button
// max 20 chars, section title max 24, row id max 200, row title max 24, row
// description max 72. header.text max 60 (list headers are text-only,
// unlike button headers).
export type OutgoingInteractiveList = {
  type: "interactive";
  interactive: {
    type: "list";
    header?: { type: "text"; text: string };
    body: { text: string };
    footer?: { text: string };
    action: {
      button: string;
      sections: {
        title: string;
        rows: { id: string; title: string; description?: string }[];
      }[];
    };
  };
};

// Sends an invite to open a Flow the organization already created and
// published in Meta Business Manager directly -- this project does not
// manage Flow definitions (the screens/JSON), only sends/receives this
// message and parses the completion reply (nfm_reply, inbound side).
// flow_id and flow_name are mutually exclusive (exactly one).
// flow_cta: 30 chars or fewer, no emoji. flow_action_payload is for
// "navigate" (the default) and must be omitted for "data_exchange".
export type OutgoingInteractiveFlow = {
  type: "interactive";
  interactive: {
    type: "flow";
    header?: { type: "text"; text: string };
    body: { text: string };
    footer?: { text: string };
    action: {
      name: "flow";
      parameters:
        & ({ flow_id: string } | { flow_name: string })
        & {
          flow_message_version: "3";
          flow_token: string;
          flow_cta: string;
          flow_action?: "navigate" | "data_exchange";
          flow_action_payload?: {
            screen: string;
            data?: Record<string, unknown>;
          };
          mode?: "draft" | "published";
        };
    };
  };
};

//===================================
// Endpoint message, as sent to the WhatsApp endpoint
//===================================

// Message format sent to the WhatsApp endpoint
// https://developers.facebook.com/docs/whatsapp/cloud-api/reference/messages
export type EndpointMessage =
  & {
    biz_opaque_callback_data?: string;
    messaging_product: "whatsapp";
    recipient_type?: "individual";
    to?: string; // phone number; omitted when messaging a BSUID only
    recipient?: string; // BSUID (or parent BSUID); takes a back seat to `to`
  }
  & OutgoingContextInfo
  & (
    | OutgoingAudio
    | ContactsMessage
    | OutgoingDocument
    | OutgoingImage
    | OutgoingInteractiveButtons
    | OutgoingInteractiveFlow
    | OutgoingInteractiveList
    | LocationMessage
    | OutgoingReaction
    | OutgoingSticker
    | TemplateMessage
    | OutgoingText
    | OutgoingVideo
  );

export type EndpointMessageResponse = {
  messaging_product: "whatsapp";
  contacts: [
    {
      input: string;
      wa_id: string;
    },
  ];
  messages: [
    {
      id: string;
      group_id?: string;
      message_status?: "accepted" | "held_for_quality_assessment";
    },
  ];
};
