// Validation for vertical pack definition files (packs/<key>/v<n>.json).
//
// Template rules follow Meta's docs (checked 2026-10-20):
// - name: lowercase alphanumerics and underscores, up to 512 characters
//   https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates
// - body up to 1024 characters, footer up to 60, positional {{n}} parameters
//   from 1 in placeholder order, an example value for each
//   https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates/components
// - a template cannot start or end with a parameter
//   https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/template-review/
// - language codes ("en", "hi")
//   https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates/supported-languages

export const PACK_LANGUAGES = ["en", "hi"] as const;
export const TEMPLATE_CATEGORIES = ["MARKETING", "UTILITY", "AUTHENTICATION"];
export const FIELD_TYPES = [
  "text",
  "number",
  "date",
  "select",
  "multi_select",
  "boolean",
];

const KEY = /^[a-z][a-z0-9_]*$/;
const TEMPLATE_NAME = /^[a-z0-9_]{1,512}$/;
const BODY_MAX = 1024;
const FOOTER_MAX = 60;

type Localized = Record<string, string>;

export type PackDefinition = {
  key: string;
  version: number;
  name: string;
  description?: string;
  is_default?: boolean;
  pipeline_stages: { key: string; name: Localized; type: string }[];
  custom_fields: {
    key: string;
    entity: string;
    type: string;
    label: Localized;
    required?: boolean;
    options?: { value: string; label: Localized }[];
  }[];
  qualification_questions: { key: string; field: string; prompt: Localized }[];
  message_templates: {
    name: string;
    category: string;
    purpose?: string;
    attach_disclaimer: boolean;
    languages: Record<string, { body: string; examples: string[] }>;
  }[];
  compliance: {
    disclaimer_short: Localized;
    disclaimer_full: Localized;
    banned_phrases: Record<string, string[]>;
    [key: string]: unknown;
  };
  modules: Record<string, boolean>;
  terminology: Record<string, Localized>;
};

function checkLocalized(
  errors: string[],
  where: string,
  value: unknown,
): void {
  if (typeof value !== "object" || value === null) {
    errors.push(
      `${where}: must be an object with ${PACK_LANGUAGES.join(", ")}`,
    );
    return;
  }
  for (const lang of PACK_LANGUAGES) {
    const text = (value as Localized)[lang];
    if (typeof text !== "string" || text.trim() === "") {
      errors.push(`${where}: missing "${lang}" text`);
    }
  }
}

function checkUniqueKeys(
  errors: string[],
  where: string,
  keys: string[],
  pattern: RegExp,
): void {
  const seen = new Set<string>();
  for (const key of keys) {
    if (!pattern.test(key ?? "")) errors.push(`${where}: invalid key "${key}"`);
    if (seen.has(key)) errors.push(`${where}: duplicate key "${key}"`);
    seen.add(key);
  }
}

/** Template body checks. Returns problems, empty when valid. */
export function checkTemplateBody(
  body: string,
  examples: string[],
): string[] {
  const problems: string[] = [];

  if (body.length > BODY_MAX) {
    problems.push(`body is ${body.length} characters (max ${BODY_MAX})`);
  }

  const params = [...body.matchAll(/\{\{\s*(\w+)\s*\}\}/g)].map((m) => m[1]);
  params.forEach((p, i) => {
    if (p !== String(i + 1)) {
      problems.push(
        `parameters must be {{1}}..{{n}} in order; found {{${p}}} at position ${
          i + 1
        }`,
      );
    }
  });

  if (examples.length !== params.length) {
    problems.push(
      `${params.length} parameters but ${examples.length} example values`,
    );
  }

  if (/^\s*\{\{/.test(body)) problems.push("body starts with a parameter");
  if (/\}\}\s*$/.test(body)) problems.push("body ends with a parameter");

  return problems;
}

/** Banned phrases found in a text, case-insensitively. */
export function findBannedPhrases(text: string, phrases: string[]): string[] {
  const lower = text.toLowerCase();
  return phrases.filter((p) => lower.includes(p.toLowerCase()));
}

/** Validates a pack definition. Returns a list of errors, empty when valid. */
export function validatePack(pack: PackDefinition): string[] {
  const errors: string[] = [];

  if (!KEY.test(pack.key ?? "")) errors.push(`key: invalid "${pack.key}"`);
  if (!Number.isInteger(pack.version) || pack.version < 1) {
    errors.push("version: must be a positive integer");
  }
  if (!pack.name) errors.push("name: required");

  // Pipeline: at least one open stage, exactly one won and one lost.
  const stages = pack.pipeline_stages ?? [];
  checkUniqueKeys(errors, "pipeline_stages", stages.map((s) => s.key), KEY);
  stages.forEach((s) => {
    checkLocalized(errors, `pipeline_stages.${s.key}.name`, s.name);
    if (!["open", "won", "lost"].includes(s.type)) {
      errors.push(`pipeline_stages.${s.key}: type must be open, won or lost`);
    }
  });
  for (const type of ["won", "lost"]) {
    const count = stages.filter((s) => s.type === type).length;
    if (count !== 1) {
      errors.push(`pipeline_stages: needs exactly one "${type}" stage`);
    }
  }
  if (!stages.some((s) => s.type === "open")) {
    errors.push('pipeline_stages: needs at least one "open" stage');
  }

  // Custom fields.
  const fields = pack.custom_fields ?? [];
  checkUniqueKeys(errors, "custom_fields", fields.map((f) => f.key), KEY);
  fields.forEach((f) => {
    const where = `custom_fields.${f.key}`;
    checkLocalized(errors, `${where}.label`, f.label);
    if (!["contact", "deal"].includes(f.entity)) {
      errors.push(`${where}: entity must be contact or deal`);
    }
    if (!FIELD_TYPES.includes(f.type)) {
      errors.push(`${where}: unknown type "${f.type}"`);
    }
    const hasOptions = f.type === "select" || f.type === "multi_select";
    if (hasOptions) {
      if (!f.options?.length) errors.push(`${where}: options required`);
      checkUniqueKeys(
        errors,
        `${where}.options`,
        (f.options ?? []).map((o) => o.value),
        KEY,
      );
      (f.options ?? []).forEach((o) =>
        checkLocalized(errors, `${where}.options.${o.value}`, o.label)
      );
    } else if (f.options) {
      errors.push(`${where}: options only apply to select fields`);
    }
  });

  // Qualification questions point at a field.
  const fieldKeys = new Set(fields.map((f) => f.key));
  const questions = pack.qualification_questions ?? [];
  checkUniqueKeys(
    errors,
    "qualification_questions",
    questions.map((q) => q.key),
    KEY,
  );
  questions.forEach((q) => {
    checkLocalized(errors, `qualification_questions.${q.key}.prompt`, q.prompt);
    if (!fieldKeys.has(q.field)) {
      errors.push(
        `qualification_questions.${q.key}: unknown field "${q.field}"`,
      );
    }
  });

  // Compliance.
  const compliance = pack.compliance;
  if (!compliance) {
    errors.push("compliance: required");
  } else {
    checkLocalized(
      errors,
      "compliance.disclaimer_short",
      compliance.disclaimer_short,
    );
    checkLocalized(
      errors,
      "compliance.disclaimer_full",
      compliance.disclaimer_full,
    );
    for (const lang of PACK_LANGUAGES) {
      const short = compliance.disclaimer_short?.[lang] ?? "";
      if (short.length > FOOTER_MAX) {
        errors.push(
          `compliance.disclaimer_short.${lang}: ${short.length} characters, must fit a template footer (max ${FOOTER_MAX})`,
        );
      }
    }
  }
  const banned = Object.values(compliance?.banned_phrases ?? {}).flat();

  // Templates.
  const templates = pack.message_templates ?? [];
  checkUniqueKeys(
    errors,
    "message_templates",
    templates.map((t) => t.name),
    TEMPLATE_NAME,
  );
  templates.forEach((t) => {
    const where = `message_templates.${t.name}`;
    if (!TEMPLATE_CATEGORIES.includes(t.category)) {
      errors.push(`${where}: unknown category "${t.category}"`);
    }
    if (typeof t.attach_disclaimer !== "boolean") {
      errors.push(`${where}: attach_disclaimer must be true or false`);
    }
    if (t.category === "MARKETING" && !t.attach_disclaimer) {
      errors.push(`${where}: marketing templates carry the disclaimer`);
    }
    for (const lang of PACK_LANGUAGES) {
      const content = t.languages?.[lang];
      if (!content) {
        errors.push(`${where}: missing "${lang}" version`);
        continue;
      }
      for (const p of checkTemplateBody(content.body, content.examples ?? [])) {
        errors.push(`${where}.${lang}: ${p}`);
      }
      for (const phrase of findBannedPhrases(content.body, banned)) {
        errors.push(`${where}.${lang}: contains banned phrase "${phrase}"`);
      }
    }
  });

  // Modules and terminology.
  for (const [key, on] of Object.entries(pack.modules ?? {})) {
    if (!KEY.test(key)) errors.push(`modules: invalid key "${key}"`);
    if (typeof on !== "boolean") errors.push(`modules.${key}: must be boolean`);
  }
  for (const [key, value] of Object.entries(pack.terminology ?? {})) {
    if (!KEY.test(key)) errors.push(`terminology: invalid key "${key}"`);
    checkLocalized(errors, `terminology.${key}`, value);
  }

  return errors;
}
