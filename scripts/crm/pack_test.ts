// deno test --allow-read scripts/crm/
import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "jsr:@std/assert@1.0.13";
import {
  checkTemplateBody,
  findBannedPhrases,
  type PackDefinition,
  validatePack,
} from "./pack.ts";
import { packToSql } from "./pack-to-sql.ts";

const packUrl = new URL(
  "../../packs/trading_institute/v1.json",
  import.meta.url,
);

async function loadPack(): Promise<PackDefinition> {
  return JSON.parse(await Deno.readTextFile(packUrl)) as PackDefinition;
}

Deno.test("trading_institute v1 is valid", async () => {
  assertEquals(validatePack(await loadPack()), []);
});

Deno.test("trading_institute v1 has the roadmap's pipeline", async () => {
  const pack = await loadPack();
  assertEquals(
    pack.pipeline_stages.map((s) => s.key),
    ["lead_inquiring", "trial_booked", "paid_student", "lost"],
  );
});

Deno.test("trading_institute v1 has en and hi templates", async () => {
  const pack = await loadPack();
  assert(pack.message_templates.length > 0);
  for (const t of pack.message_templates) {
    assert(t.languages.en, t.name);
    assert(t.languages.hi, t.name);
  }
});

Deno.test("template body: parameter at the start or end is refused", () => {
  assertEquals(
    checkTemplateBody("{{1}}, your class is booked.", ["Priya"]),
    ["body starts with a parameter"],
  );
  assertEquals(
    checkTemplateBody("Your class is booked for {{1}}", ["Monday"]),
    ["body ends with a parameter"],
  );
});

Deno.test("template body: parameters in order with examples", () => {
  assertEquals(
    checkTemplateBody("Hi {{1}}, see you on {{2}}.", ["Priya", "Monday"]),
    [],
  );
  const problems = checkTemplateBody("Hi {{2}}, see you on {{1}}.", [
    "a",
    "b",
  ]);
  assert(problems.length === 2);
  assertStringIncludes(
    checkTemplateBody("Hi {{1}} and {{2}}.", ["a"]).join(),
    "2 parameters but 1 example values",
  );
});

Deno.test("template body: length limit", () => {
  const body = "Hello " + "a".repeat(1100) + ".";
  assertStringIncludes(checkTemplateBody(body, []).join(), "max 1024");
});

Deno.test("banned phrases are caught case-insensitively", () => {
  assertEquals(
    findBannedPhrases("Join now for GUARANTEED Returns!", [
      "guaranteed return",
    ]),
    ["guaranteed return"],
  );
});

Deno.test("a pack promising returns fails validation", async () => {
  const pack = await loadPack();
  pack.message_templates[0].languages.en.body =
    "Hi {{1}}, join {{2}} for guaranteed profit every month.";
  assertStringIncludes(
    validatePack(pack).join("\n"),
    'contains banned phrase "guaranteed profit"',
  );
});

Deno.test("a footer disclaimer over 60 characters fails validation", async () => {
  const pack = await loadPack();
  pack.compliance.disclaimer_short.en = "x".repeat(61);
  assertStringIncludes(validatePack(pack).join("\n"), "max 60");
});

Deno.test("pack-to-sql embeds the definition and a checksum guard", async () => {
  const { sql } = await packToSql(await Deno.readTextFile(packUrl));
  assertStringIncludes(sql, "insert into crm.pack_versions");
  assertStringIncludes(sql, "already published with different content");
  assertStringIncludes(sql, '"lead_inquiring"');
});
