// [crm] P3-09: buildConversionEventPayload is the one pure piece of
// conversions_api.ts -- no client, no network -- worth testing directly,
// same precedent as token_health.ts's shouldFlagForReauth.
import { assertEquals } from "jsr:@std/assert@1.0.13";
import { buildConversionEventPayload } from "./conversions_api.ts";

Deno.test("buildConversionEventPayload: event_time converts to unix seconds", () => {
  const payload = buildConversionEventPayload({
    event_name: "Lead",
    event_time: "2026-10-30T12:00:00.000Z",
    ctwa_clid: "clid-123",
    value: null,
    currency: null,
  });
  assertEquals(payload.data[0].event_time, 1793361600);
});

Deno.test("buildConversionEventPayload: action_source and messaging_channel are fixed", () => {
  const payload = buildConversionEventPayload({
    event_name: "Lead",
    event_time: "2026-10-30T12:00:00.000Z",
    ctwa_clid: "clid-123",
    value: null,
    currency: null,
  });
  assertEquals(payload.data[0].action_source, "business_messaging");
  assertEquals(payload.data[0].messaging_channel, "whatsapp");
  assertEquals(payload.data[0].user_data, { ctwa_clid: "clid-123" });
});

Deno.test("buildConversionEventPayload: no custom_data when value is null", () => {
  const payload = buildConversionEventPayload({
    event_name: "Lead",
    event_time: "2026-10-30T12:00:00.000Z",
    ctwa_clid: "clid-123",
    value: null,
    currency: null,
  });
  assertEquals("custom_data" in payload.data[0], false);
});

Deno.test("buildConversionEventPayload: custom_data carries value and currency when present", () => {
  const payload = buildConversionEventPayload({
    event_name: "Purchase",
    event_time: "2026-10-30T12:00:00.000Z",
    ctwa_clid: "clid-123",
    value: 4500,
    currency: "INR",
  });
  assertEquals(
    (payload.data[0] as { custom_data?: unknown }).custom_data,
    { value: 4500, currency: "INR" },
  );
});
