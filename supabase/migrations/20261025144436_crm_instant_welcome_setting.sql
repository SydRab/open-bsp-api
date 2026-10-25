-- Instant welcome toggle (P3-03). Data only; the table is in
-- schemas/10_crm/10-07_settings.sql. Off by default: an org has to
-- deliberately enable automatic outbound messaging to every new contact,
-- confirmed with the user 2026-10-25 -- a new org should not start
-- sending automated WhatsApp messages before anyone configured anything.
insert into crm.setting_definitions (
  key, category, label, description, schema, platform_default, scopes,
  is_locked, edit_permission, pack_item_kind, pack_item_key, pack_item_path,
  sort_order
) values
  ('messaging.instant_welcome', 'messaging', 'Instant welcome',
   'On a contact''s first message, send a language-choice (English/Hindi) greeting before anything else.',
   '{"type": "boolean"}', 'false', '{tenant}', false, 'organization.manage',
   null, null, '{}', 40);
