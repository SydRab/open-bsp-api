-- Branding tokens (P1-11): white-label logo and primary color, through the
-- existing settings engine (P1-04) rather than a new table. An empty string
-- (the platform default) means "use the default mark/color" — the UI treats
-- a resolved empty value as unset. No file upload: logo is a pasted URL, like
-- support_email/website already are.

insert into crm.setting_definitions (
  key, category, label, description, schema, platform_default, scopes,
  is_locked, edit_permission, pack_item_kind, pack_item_key, pack_item_path,
  sort_order
) values
  ('branding.logo_url', 'branding', 'Logo URL',
   'A hosted image URL shown in the sidebar and organization settings in place of the default mark. Leave empty to use the default.',
   '{"type": "string", "maxLength": 500, "pattern": "^$|^https?://.+"}',
   '""', '{tenant}', false, 'organization.manage', null, null, '{}', 200),

  ('branding.primary_color', 'branding', 'Primary color',
   'A hex color (e.g. #2563eb) used for buttons and highlights across the app. Leave empty to use the default.',
   '{"type": "string", "pattern": "^$|^#[0-9a-fA-F]{6}$"}',
   '""', '{tenant}', false, 'organization.manage', null, null, '{}', 210);
