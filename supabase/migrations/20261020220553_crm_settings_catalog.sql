-- The first settings (P1-04). Data only; the tables are in
-- schemas/10_crm/10-07_settings.sql.
--
-- Locked settings are compliance minimums the platform enforces (CLAUDE.md
-- "Compliance guardrails"), confirmed with the product owner on 2026-10-21:
-- marketing needs recorded opt-in, AI-written and news content always goes
-- through approval, and STOP / UNSUBSCRIBE always stop messages (tenants may
-- add keywords, never remove these two).
--
-- Adding a setting later: insert a row in a new migration. Labels are
-- English; the UI translates them.

insert into crm.setting_definitions (
  key, category, label, description, schema, platform_default, scopes,
  is_locked, edit_permission, pack_item_kind, pack_item_key, pack_item_path,
  sort_order
) values
  -- Messaging rules ------------------------------------------------------------
  ('messaging.quiet_hours', 'messaging', 'Quiet hours',
   'No automatic or marketing messages between these times, in the organization''s time zone.',
   '{"type": "object", "required": ["start", "end"], "additionalProperties": false,
     "properties": {
       "start": {"type": "string", "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$"},
       "end": {"type": "string", "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$"}}}',
   '{"start": "21:00", "end": "09:00"}', '{tenant}', false, 'organization.manage',
   'compliance', 'quiet_hours', '{}', 10),

  ('marketing.frequency_cap', 'messaging', 'Marketing frequency cap',
   'The most marketing messages one contact receives in a period.',
   '{"type": "object", "required": ["max_messages", "period_days"], "additionalProperties": false,
     "properties": {
       "max_messages": {"type": "integer", "minimum": 1, "maximum": 20},
       "period_days": {"type": "integer", "minimum": 1, "maximum": 30}}}',
   '{"max_messages": 2, "period_days": 7}', '{tenant}', false, 'organization.manage',
   'compliance', 'marketing_frequency_cap', '{}', 20),

  ('marketing.requires_opt_in', 'messaging', 'Marketing needs recorded opt-in',
   'Marketing messages go only to contacts with a recorded opt-in. Set by the platform.',
   '{"type": "boolean"}', 'true', '{tenant}', true, 'organization.manage',
   null, null, '{}', 30),

  ('compliance.opt_out_keywords', 'messaging', 'Opt-out keywords',
   'Replies that stop messages at once. STOP and UNSUBSCRIBE always apply.',
   '{"type": "array", "minItems": 2, "maxItems": 50, "mustContain": ["STOP", "UNSUBSCRIBE"],
     "items": {"type": "string", "minLength": 1, "maxLength": 30}}',
   '["STOP", "UNSUBSCRIBE"]', '{tenant}', false, 'organization.manage',
   'compliance', 'opt_out_keywords', '{}', 40),

  ('compliance.extra_banned_phrases', 'messaging', 'Extra banned phrases',
   'Phrases the compliance filter blocks, in addition to the pack''s list.',
   '{"type": "array", "maxItems": 200, "items": {"type": "string", "minLength": 2, "maxLength": 100}}',
   '[]', '{tenant}', false, 'organization.manage',
   null, null, '{}', 50),

  -- Approvals ------------------------------------------------------------------
  ('approval.broadcasts', 'approvals', 'Broadcasts need approval',
   'A broadcast is sent only after someone with approval rights approves it.',
   '{"type": "boolean"}', 'true', '{tenant}', false, 'organization.manage',
   'compliance', 'require_approval', '{broadcast}', 60),

  ('approval.ai_content', 'approvals', 'AI-written content needs approval',
   'AI-generated messages pass the compliance filter and the approval queue. Set by the platform.',
   '{"type": "boolean"}', 'true', '{tenant}', true, 'organization.manage',
   null, null, '{}', 70),

  ('approval.news_content', 'approvals', 'News content needs approval',
   'News and digest content passes the compliance filter and the approval queue. Set by the platform.',
   '{"type": "boolean"}', 'true', '{tenant}', true, 'organization.manage',
   null, null, '{}', 80),

  -- Disclaimer -------------------------------------------------------------------
  ('disclaimer.attach_rules', 'disclaimer', 'Attach the disclaimer to',
   'Which kinds of automatic content carry the organization''s disclaimer.',
   '{"type": "object", "additionalProperties": false,
     "required": ["broadcast", "digest", "ai_message", "receipt", "payment_confirmation"],
     "properties": {
       "broadcast": {"type": "boolean"}, "digest": {"type": "boolean"},
       "ai_message": {"type": "boolean"}, "receipt": {"type": "boolean"},
       "payment_confirmation": {"type": "boolean"}}}',
   '{"broadcast": true, "digest": true, "ai_message": true, "receipt": false, "payment_confirmation": false}',
   '{tenant}', false, 'organization.manage',
   'compliance', 'disclaimer_attach_rules', '{}', 90);

-- Modules: on/off per organization. The pack decides the starting point;
-- plan entitlements (P1-09) will decide what may be turned on.
insert into crm.setting_definitions (
  key, category, label, schema, platform_default, pack_item_kind,
  pack_item_key, sort_order
)
select
  'modules.' || m.key, 'modules', m.label, '{"type": "boolean"}',
  to_jsonb(m.key in ('inbox', 'contacts')), 'module', m.key, 100 + m.ord
from (values
  ('inbox', 'Inbox', 1), ('contacts', 'Contacts', 2), ('pipeline', 'Pipeline', 3),
  ('broadcasts', 'Broadcasts', 4), ('sequences', 'Sequences', 5),
  ('webinars', 'Webinars', 6), ('payments', 'Payments', 7),
  ('classroom', 'Classroom', 8), ('telegram', 'Telegram', 9),
  ('ai_agents', 'AI agents', 10), ('news_digest', 'News digest', 11)
) as m(key, label, ord);
