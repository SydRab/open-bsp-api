-- P4-02: a sibling setting to compliance.opt_out_keywords (seeded in
-- 20261020220553_crm_settings_catalog.sql) for the START/opt-back-in half
-- CLAUDE.md's "STOP/unsubscribe is honored instantly" line never named but
-- the roadmap's own P4-02 line asks for. Same hand-written-DML exception
-- as the original catalog seed -- db diff emits schema DDL only, never
-- data.
insert into crm.setting_definitions (
  key, category, label, description, schema, platform_default, scopes,
  is_locked, edit_permission, pack_item_kind, pack_item_key, pack_item_path,
  sort_order
) values
  ('compliance.opt_in_keywords', 'messaging', 'Opt-in keywords',
   'Replies that resume messages at once. START always applies.',
   '{"type": "array", "minItems": 1, "maxItems": 50, "mustContain": ["START"],
     "items": {"type": "string", "minLength": 1, "maxLength": 30}}',
   '["START", "SUBSCRIBE"]', '{tenant}', false, 'organization.manage',
   'compliance', 'opt_in_keywords', '{}', 45);
