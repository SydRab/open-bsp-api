// [crm] P2-06: the validation/conversion logic behind the three outbound
// interactive message types -- a wrong limit here either silently drops a
// button Meta would have accepted or sends a request Meta rejects with a
// confusing error.
import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.13";
import {
  buildInteractiveButtonsPayload,
  buildInteractiveFlowPayload,
  buildInteractiveListPayload,
} from "./interactive_messages.ts";

Deno.test("buildInteractiveButtonsPayload: a valid request converts correctly", () => {
  const payload = buildInteractiveButtonsPayload({
    header: "Quick question",
    body: "Would you like a demo?",
    footer: "Reply anytime",
    buttons: [
      { id: "yes", title: "Yes" },
      { id: "no", title: "No" },
    ],
  });

  assertEquals(payload, {
    type: "button",
    header: { type: "text", text: "Quick question" },
    body: { text: "Would you like a demo?" },
    footer: { text: "Reply anytime" },
    action: {
      buttons: [
        { type: "reply", reply: { id: "yes", title: "Yes" } },
        { type: "reply", reply: { id: "no", title: "No" } },
      ],
    },
  });
});

Deno.test("buildInteractiveButtonsPayload: optional header/footer are omitted, not sent empty", () => {
  const payload = buildInteractiveButtonsPayload({
    body: "Pick one",
    buttons: [{ id: "a", title: "A" }],
  });

  assertEquals("header" in payload, false);
  assertEquals("footer" in payload, false);
});

Deno.test("buildInteractiveButtonsPayload: rejects zero buttons", () => {
  assertThrows(
    () => buildInteractiveButtonsPayload({ body: "x", buttons: [] }),
    Error,
    "at least one button",
  );
});

Deno.test("buildInteractiveButtonsPayload: rejects more than 3 buttons", () => {
  assertThrows(
    () =>
      buildInteractiveButtonsPayload({
        body: "x",
        buttons: [
          { id: "1", title: "A" },
          { id: "2", title: "B" },
          { id: "3", title: "C" },
          { id: "4", title: "D" },
        ],
      }),
    Error,
    "at most 3 buttons",
  );
});

Deno.test("buildInteractiveButtonsPayload: rejects a title over 20 chars", () => {
  assertThrows(
    () =>
      buildInteractiveButtonsPayload({
        body: "x",
        buttons: [{ id: "1", title: "a".repeat(21) }],
      }),
    Error,
    "button title",
  );
});

Deno.test("buildInteractiveButtonsPayload: rejects duplicate button titles", () => {
  assertThrows(
    () =>
      buildInteractiveButtonsPayload({
        body: "x",
        buttons: [
          { id: "1", title: "Same" },
          { id: "2", title: "Same" },
        ],
      }),
    Error,
    "unique",
  );
});

Deno.test("buildInteractiveButtonsPayload: rejects a body over 1024 chars", () => {
  assertThrows(
    () =>
      buildInteractiveButtonsPayload({
        body: "a".repeat(1025),
        buttons: [{ id: "1", title: "A" }],
      }),
    Error,
    "body",
  );
});

Deno.test("buildInteractiveListPayload: a valid request converts correctly", () => {
  const payload = buildInteractiveListPayload({
    body: "Which shipping option?",
    button: "Shipping Options",
    sections: [
      {
        title: "Fast",
        rows: [{ id: "express", title: "Express", description: "1-2 days" }],
      },
    ],
  });

  assertEquals(payload, {
    type: "list",
    body: { text: "Which shipping option?" },
    action: {
      button: "Shipping Options",
      sections: [
        {
          title: "Fast",
          rows: [
            { id: "express", title: "Express", description: "1-2 days" },
          ],
        },
      ],
    },
  });
});

Deno.test("buildInteractiveListPayload: rejects more than 10 sections", () => {
  const sections = Array.from({ length: 11 }, (_, i) => ({
    title: `Section ${i}`,
    rows: [{ id: `row-${i}`, title: "Row" }],
  }));

  assertThrows(
    () => buildInteractiveListPayload({ body: "x", button: "Go", sections }),
    Error,
    "at most 10 sections",
  );
});

Deno.test("buildInteractiveListPayload: rejects more than 10 rows across all sections combined", () => {
  const sections = [
    {
      title: "A",
      rows: Array.from(
        { length: 6 },
        (_, i) => ({ id: `a${i}`, title: `A${i}` }),
      ),
    },
    {
      title: "B",
      rows: Array.from(
        { length: 5 },
        (_, i) => ({ id: `b${i}`, title: `B${i}` }),
      ),
    },
  ];

  assertThrows(
    () => buildInteractiveListPayload({ body: "x", button: "Go", sections }),
    Error,
    "at most 10 rows",
  );
});

Deno.test("buildInteractiveListPayload: rejects a section with no rows", () => {
  assertThrows(
    () =>
      buildInteractiveListPayload({
        body: "x",
        button: "Go",
        sections: [{ title: "Empty", rows: [] }],
      }),
    Error,
    "at least one row",
  );
});

Deno.test("buildInteractiveListPayload: rejects a row description over 72 chars", () => {
  assertThrows(
    () =>
      buildInteractiveListPayload({
        body: "x",
        button: "Go",
        sections: [{
          title: "A",
          rows: [{ id: "1", title: "Row", description: "a".repeat(73) }],
        }],
      }),
    Error,
    "row description",
  );
});

Deno.test("buildInteractiveFlowPayload: a valid navigate request converts correctly", () => {
  const payload = buildInteractiveFlowPayload({
    body: "Let's get you booked in",
    flow_id: "123456",
    flow_token: "tok-abc",
    flow_cta: "Book now",
    flow_action_payload: { screen: "WELCOME" },
  });

  assertEquals(payload, {
    type: "flow",
    body: { text: "Let's get you booked in" },
    action: {
      name: "flow",
      parameters: {
        flow_id: "123456",
        flow_message_version: "3",
        flow_token: "tok-abc",
        flow_cta: "Book now",
        flow_action_payload: { screen: "WELCOME" },
      },
    },
  });
});

Deno.test("buildInteractiveFlowPayload: flow_name works in place of flow_id", () => {
  const payload = buildInteractiveFlowPayload({
    body: "x",
    flow_name: "booking_flow",
    flow_token: "tok",
    flow_cta: "Go",
  });

  assertEquals(
    (payload.action.parameters as { flow_name?: string }).flow_name,
    "booking_flow",
  );
});

Deno.test("buildInteractiveFlowPayload: rejects flow_action_payload with data_exchange", () => {
  assertThrows(
    () =>
      buildInteractiveFlowPayload({
        body: "x",
        flow_id: "1",
        flow_token: "tok",
        flow_cta: "Go",
        flow_action: "data_exchange",
        flow_action_payload: { screen: "A" },
      }),
    Error,
    "data_exchange",
  );
});

Deno.test("buildInteractiveFlowPayload: rejects a flow_cta over 30 chars", () => {
  assertThrows(
    () =>
      buildInteractiveFlowPayload({
        body: "x",
        flow_id: "1",
        flow_token: "tok",
        flow_cta: "a".repeat(31),
      }),
    Error,
    "flow_cta",
  );
});
