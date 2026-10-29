-- Speed-to-lead settings (P3-06). Data only; the table is in
-- schemas/10_crm/10-07_settings.sql. Defaults confirmed with the user
-- 2026-10-29: 15 minutes to first response, escalate to managers 15
-- minutes past that (30 total), auto-reassign 30 minutes past the
-- manager escalation (60 total) -- fast-follow-up norms for trading
-- leads, all tenant-editable.
insert into crm.setting_definitions (
  key, category, label, description, schema, platform_default, scopes,
  is_locked, edit_permission, pack_item_kind, pack_item_key, pack_item_path,
  sort_order
) values
  ('speed_to_lead.first_response_sla_minutes', 'speed_to_lead', 'First-response SLA (minutes)',
   'How long an assigned rep has to send the first reply before the lead is flagged as unanswered.',
   '{"type": "number", "minimum": 1, "maximum": 1440}', '15', '{tenant}', false, 'organization.manage',
   null, null, '{}', 60),
  ('speed_to_lead.manager_escalation_minutes', 'speed_to_lead', 'Manager escalation (minutes)',
   'How much longer past the SLA before managers are notified.',
   '{"type": "number", "minimum": 1, "maximum": 1440}', '15', '{tenant}', false, 'organization.manage',
   null, null, '{}', 61),
  ('speed_to_lead.reassign_escalation_minutes', 'speed_to_lead', 'Auto-reassign escalation (minutes)',
   'How much longer past the manager escalation before the lead is automatically reassigned.',
   '{"type": "number", "minimum": 1, "maximum": 1440}', '30', '{tenant}', false, 'organization.manage',
   null, null, '{}', 62);
