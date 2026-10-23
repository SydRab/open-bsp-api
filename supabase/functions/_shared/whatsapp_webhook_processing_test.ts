// [crm] P2-06: nfm_reply (a completed WhatsApp Flow) carries response_json as
// an escaped JSON string -- Meta's choice, not ours. Worth a direct test
// since a parse failure there must not throw and lose the whole webhook
// event (see the try/catch in webhookMessageToIncomingMessage).
import { assertEquals } from "jsr:@std/assert@1.0.13";
import { webhookMessageToIncomingMessage } from "./whatsapp_webhook_processing.ts";
import type { WebhookIncomingMessage } from "./types/whatsapp_webhook_payload_types.ts";

function nfmReplyMessage(response_json: string): WebhookIncomingMessage {
  return {
    from_user_id: "US.13491208655302741918",
    id: "wamid.test",
    timestamp: 1700000000,
    type: "interactive",
    interactive: {
      type: "nfm_reply",
      nfm_reply: { name: "flow", body: "Sent", response_json },
    },
  } as WebhookIncomingMessage;
}

Deno.test("webhookMessageToIncomingMessage: a valid nfm_reply parses response_json into an object", () => {
  const content = webhookMessageToIncomingMessage(
    nfmReplyMessage('{"flow_token":"tok-123","grade":"10th"}'),
  );

  assertEquals(content?.type, "data");
  assertEquals((content as { kind?: string })?.kind, "nfm_reply");
  assertEquals(
    (content as { data?: { name: string; body: string; response: unknown } })
      ?.data,
    {
      name: "flow",
      body: "Sent",
      response: { flow_token: "tok-123", grade: "10th" },
    },
  );
});

Deno.test("webhookMessageToIncomingMessage: malformed response_json falls back to _raw instead of throwing", () => {
  const content = webhookMessageToIncomingMessage(
    nfmReplyMessage("not valid json"),
  );

  assertEquals(
    (content as { data?: { response: unknown } })?.data?.response,
    { _raw: "not valid json" },
  );
});
