// [crm] P2-04: buildTemplateFromPackItem is the one pure piece of pack
// template submission -- no client, no network -- worth testing directly.
import { assertEquals } from "jsr:@std/assert@1.0.13";
import { buildTemplateFromPackItem } from "./pack_templates.ts";

const packItem = {
  name: "lead_inquiry_ack",
  category: "UTILITY" as const,
  attach_disclaimer: true,
  languages: {
    en: { body: "Hi {{1}}, thanks for your interest.", examples: ["Priya"] },
    hi: { body: "नमस्ते {{1}}", examples: ["प्रिया"] },
  },
};

Deno.test("buildTemplateFromPackItem: uses the pack item's key as the template name", () => {
  const template = buildTemplateFromPackItem(
    "lead_inquiry_ack",
    packItem,
    "en",
    null,
  );
  assertEquals(template.name, "lead_inquiry_ack");
  assertEquals(template.category, "UTILITY");
  assertEquals(template.language, "en");
  assertEquals(template.status, "PENDING");
});

Deno.test("buildTemplateFromPackItem: body component carries the right language's text and examples", () => {
  const en = buildTemplateFromPackItem(
    "lead_inquiry_ack",
    packItem,
    "en",
    null,
  );
  const body = en.components.find((c) => c.type === "BODY");
  assertEquals(body?.type, "BODY");
  if (body?.type === "BODY") {
    assertEquals(body.text, "Hi {{1}}, thanks for your interest.");
    assertEquals(body.example?.body_text, [["Priya"]]);
  }

  const hi = buildTemplateFromPackItem(
    "lead_inquiry_ack",
    packItem,
    "hi",
    null,
  );
  const hiBody = hi.components.find((c) => c.type === "BODY");
  assertEquals(hiBody?.type === "BODY" && hiBody.text, "नमस्ते {{1}}");
});

Deno.test("buildTemplateFromPackItem: no footer component when footer is null", () => {
  const template = buildTemplateFromPackItem(
    "lead_inquiry_ack",
    packItem,
    "en",
    null,
  );
  assertEquals(
    template.components.some((c) => c.type === "FOOTER"),
    false,
  );
});

Deno.test("buildTemplateFromPackItem: footer component carries the disclaimer text when given", () => {
  const template = buildTemplateFromPackItem(
    "lead_inquiry_ack",
    packItem,
    "en",
    "Educational content only, not investment advice.",
  );
  const footer = template.components.find((c) => c.type === "FOOTER");
  assertEquals(
    footer?.type === "FOOTER" && footer.text,
    "Educational content only, not investment advice.",
  );
});

Deno.test("buildTemplateFromPackItem: no example field when the pack item has no examples", () => {
  const noExamples = {
    ...packItem,
    languages: { en: { body: "Hi there, no variables here." } },
  };
  const template = buildTemplateFromPackItem(
    "lead_inquiry_ack",
    noExamples,
    "en",
    null,
  );
  const body = template.components.find((c) => c.type === "BODY");
  assertEquals(body?.type === "BODY" && body.example, undefined);
});
