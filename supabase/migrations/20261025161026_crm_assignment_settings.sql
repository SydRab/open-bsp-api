-- Assignment engine settings (P3-05). Data only; the table is in
-- schemas/10_crm/10-07_settings.sql. auto_assign off by default -- same
-- reasoning as messaging.instant_welcome / qualification.auto_start: an
-- org must deliberately turn on automatic lead routing. capacity_cap and
-- reassign_timeout_hours are tenant-editable defaults for the engine.
-- working_hours is team-scoped only ({team}, not {tenant}) -- a team with
-- no value set is simply unrestricted (crm._pick_assignee reads it
-- directly via crm.setting_values, bypassing the usual platform-default
-- fallback on purpose); the platform_default below exists only to satisfy
-- the column's NOT NULL constraint and as an example shape.
insert into crm.setting_definitions (
  key, category, label, description, schema, platform_default, scopes,
  is_locked, edit_permission, pack_item_kind, pack_item_key, pack_item_path,
  sort_order
) values
  ('assignment.auto_assign', 'assignment', 'Auto-assign qualified leads',
   'The moment a lead becomes qualified, route it to a team automatically.',
   '{"type": "boolean"}', 'false', '{tenant}', false, 'organization.manage',
   null, null, '{}', 50),
  ('assignment.capacity_cap', 'assignment', 'Capacity cap',
   'The most open leads one rep may hold at once before being skipped in rotation.',
   '{"type": "number", "minimum": 1, "maximum": 1000}', '20', '{tenant}', false, 'organization.manage',
   null, null, '{}', 51),
  ('assignment.reassign_timeout_hours', 'assignment', 'Reassignment timeout (hours)',
   'If an assigned rep has not acted on a lead within this many hours, route it to someone else.',
   '{"type": "number", "minimum": 1, "maximum": 168}', '24', '{tenant}', false, 'organization.manage',
   null, null, '{}', 52),
  ('assignment.working_hours', 'assignment', 'Working hours',
   'When this team is available for automatic assignment; unset means always available.',
   '{"type": "object", "required": ["days", "start", "end"], "additionalProperties": false,
     "properties": {
       "days": {"type": "array", "minItems": 1,
                 "items": {"type": "string", "enum": ["mon","tue","wed","thu","fri","sat","sun"]}},
       "start": {"type": "string", "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$"},
       "end": {"type": "string", "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$"}}}',
   '{"days": ["mon","tue","wed","thu","fri"], "start": "09:00", "end": "18:00"}',
   '{team}', false, 'organization.manage', null, null, '{}', 53);
