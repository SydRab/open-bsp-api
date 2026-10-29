-- WhatsApp sender number for internal alerts (P3-07d). Data only; the
-- table is in schemas/10_crm/10-07_settings.sql. Null by default --
-- falls back to the org's first connected WhatsApp number, confirmed
-- with the user 2026-10-30 (a new org needs no setup step before
-- task reminders work at all, only to pick a different number later).
insert into crm.setting_definitions (
  key, category, label, description, schema, platform_default, scopes,
  is_locked, edit_permission, pack_item_kind, pack_item_key, pack_item_path,
  sort_order
) values
  ('notifications.whatsapp_sender_address', 'notifications', 'WhatsApp sender for internal alerts',
   'Which connected WhatsApp number sends internal staff alerts (task reminders, SLA escalations). Leave unset to use the first connected number.',
   '{"type": "string"}', '""', '{tenant}', false, 'organization.manage',
   null, null, '{}', 10);
