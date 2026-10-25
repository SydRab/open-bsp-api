-- Qualification engine settings (P3-04). Data only; the table is in
-- schemas/10_crm/10-07_settings.sql. auto_start off by default -- same
-- reasoning as messaging.instant_welcome (P3-03): an org must deliberately
-- turn on automatic outbound messaging, confirmed with the user 2026-10-25.
-- question_timeout_hours/max_nudges are tenant-editable defaults for the
-- nudge sweep (crm.sweep_qualification_nudges).
insert into crm.setting_definitions (
  key, category, label, description, schema, platform_default, scopes,
  is_locked, edit_permission, pack_item_kind, pack_item_key, pack_item_path,
  sort_order
) values
  ('qualification.auto_start', 'qualification', 'Auto-start qualification',
   'On a contact''s first message, start asking the pack''s qualification questions automatically.',
   '{"type": "boolean"}', 'false', '{tenant}', false, 'organization.manage',
   null, null, '{}', 41),
  ('qualification.question_timeout_hours', 'qualification', 'Question timeout (hours)',
   'If a lead does not answer a pending question within this many hours, send one reminder.',
   '{"type": "number", "minimum": 1, "maximum": 168}', '6', '{tenant}', false, 'organization.manage',
   null, null, '{}', 42),
  ('qualification.max_nudges', 'qualification', 'Maximum reminders',
   'How many times to re-prompt an unanswered or unrecognized reply before leaving the lead for manual follow-up.',
   '{"type": "number", "minimum": 0, "maximum": 10}', '2', '{tenant}', false, 'organization.manage',
   null, null, '{}', 43);
