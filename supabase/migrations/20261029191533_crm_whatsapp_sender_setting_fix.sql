-- Fix caught by testing: a {"type": "string"} setting's platform_default
-- must itself be a valid string per its own schema -- jsonb null failed
-- "every platform default passes its own schema." Empty string means
-- "unset," matching the fix in crm.sweep_task_reminders' fallback check.
update crm.setting_definitions
set platform_default = '""'
where key = 'notifications.whatsapp_sender_address';
