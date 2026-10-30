-- Trial booking settings (P3-08). Data only; the table is in
-- schemas/10_crm/10-07_settings.sql.
--
-- trial.auto_offer defaults off -- same "an org must deliberately turn on
-- an automatic lead-facing send" reasoning as assignment.auto_assign and
-- qualification.auto_start.
--
-- trial.schedule has no sensible platform default (there is no universal
-- "when does a trading academy run trial classes"), so crm.
-- _upcoming_trial_slots reads crm.setting_values directly rather than
-- through crm.resolve_setting's fallback chain -- same trick assignment.
-- working_hours (10-29r) already uses. The platform_default below exists
-- only to satisfy the column's NOT NULL constraint and as an example
-- shape, same as working_hours' own comment says.
insert into crm.setting_definitions (
  key, category, label, description, schema, platform_default, scopes,
  is_locked, edit_permission, pack_item_kind, pack_item_key, pack_item_path,
  sort_order
) values
  ('trial.auto_offer', 'trial', 'Auto-offer trial slots',
   'The moment a lead becomes qualified, send them a list of open trial class slots to pick from.',
   '{"type": "boolean"}', 'false', '{tenant}', false, 'organization.manage',
   null, null, '{}', 60),
  ('trial.schedule', 'trial', 'Trial class schedule',
   'When trial classes run and how many seats each one has; unset means trial booking is off.',
   '{"type": "object", "required": ["days", "times"], "additionalProperties": false,
     "properties": {
       "days": {"type": "array", "minItems": 1,
                 "items": {"type": "string", "enum": ["mon","tue","wed","thu","fri","sat","sun"]}},
       "times": {"type": "array", "minItems": 1,
                  "items": {"type": "string", "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$"}},
       "slot_duration_minutes": {"type": "number", "minimum": 15, "maximum": 240},
       "capacity_per_slot": {"type": "number", "minimum": 1, "maximum": 500}}}',
   '{"days": ["mon","wed","fri"], "times": ["10:00","18:00"],
     "slot_duration_minutes": 60, "capacity_per_slot": 10}',
   '{tenant}', false, 'organization.manage', null, null, '{}', 61),
  ('trial.reminder_hours_before', 'trial', 'Trial reminder lead time (hours)',
   'How many hours before a booked trial class to send the reminder.',
   '{"type": "number", "minimum": 1, "maximum": 72}', '3', '{tenant}', false, 'organization.manage',
   null, null, '{}', 62);
