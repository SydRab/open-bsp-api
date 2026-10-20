-- Permission catalog and the eight preset roles (P1-02). Data only; the
-- tables are in schemas/10_crm/10-01_catalog.sql.
--
-- Adding a permission later: insert it here-style in a new migration, add it
-- to the presets that should have it, and grant it to every organization's
-- owner role (the owner role always holds every permission):
--   insert into crm.role_permissions (organization_id, role_id, permission)
--   select organization_id, id, '<key>' from crm.roles where key = 'owner';

insert into crm.permissions (key, category, description, min_tier, sort_order) values
  -- Organization
  ('organization.manage', 'organization', 'Edit the organization profile, settings and pack', 'admin', 10),
  ('organization.delete', 'organization', 'Request deletion of the organization', 'owner', 11),
  ('billing.view', 'organization', 'See plan, usage and invoices', 'member', 12),
  -- Team
  ('members.view', 'team', 'See the member list', 'member', 20),
  ('members.invite', 'team', 'Invite people and revoke invitations', 'member', 21),
  ('members.manage', 'team', 'Change roles, scopes and deactivate members', 'member', 22),
  ('roles.manage', 'team', 'Turn role permissions on and off', 'admin', 23),
  ('audit.view', 'team', 'Read the audit log', 'member', 24),
  -- Inbox
  ('conversations.view', 'inbox', 'Read conversations and messages', 'member', 30),
  ('messages.send', 'inbox', 'Send messages to contacts', 'member', 31),
  -- Contacts
  ('contacts.view', 'contacts', 'See contacts and leads', 'member', 40),
  ('contacts.edit', 'contacts', 'Add and edit contacts and leads', 'member', 41),
  ('contacts.export', 'contacts', 'Export contacts', 'member', 42),
  -- Pipeline
  ('pipeline.view', 'pipeline', 'See the pipeline and deals', 'member', 50),
  ('deals.edit', 'pipeline', 'Create deals and move them between stages', 'member', 51),
  ('deals.view_all', 'pipeline', 'See every deal, not only assigned ones', 'member', 52),
  -- Marketing
  ('templates.manage', 'marketing', 'Create and edit message templates', 'member', 60),
  ('broadcasts.create', 'marketing', 'Create broadcasts and sequences', 'member', 61),
  ('broadcasts.approve', 'marketing', 'Approve broadcasts and AI content before sending', 'member', 62),
  -- Payments
  ('payments.view', 'payments', 'See fees, payments and receipts', 'member', 70),
  ('payments.manage', 'payments', 'Record payments and manage fee plans', 'member', 71),
  -- Classroom
  ('classroom.manage', 'classroom', 'Manage batches, assignments and quizzes', 'member', 80),
  -- Reports
  ('reports.view', 'reports', 'See reports and analytics', 'member', 90),
  -- Integrations (upstream gates these by tier too)
  ('integrations.manage', 'integrations', 'Connect WhatsApp numbers and other channels', 'admin', 100),
  ('ai_agents.manage', 'integrations', 'Create and configure AI agents', 'admin', 101),
  ('api_keys.manage', 'integrations', 'Create and revoke API keys', 'owner', 102),
  ('webhooks.manage', 'integrations', 'Manage outgoing webhooks', 'owner', 103);

insert into crm.preset_roles (key, name, description, tier, lead_scope, sort_order) values
  ('owner', 'Owner', 'Full control, including billing and deleting the organization', 'owner', 'all', 1),
  ('admin', 'Admin', 'Runs the organization: settings, team, integrations', 'admin', 'all', 2),
  ('sales_manager', 'Sales Manager', 'Leads the sales team and sees every lead', 'member', 'all', 3),
  ('sales_rep', 'Sales Rep', 'Works their own leads and conversations', 'member', 'own', 4),
  ('marketing', 'Marketing', 'Runs templates, broadcasts and campaigns', 'member', 'all', 5),
  ('teacher', 'Teacher', 'Teaches batches and talks to their students', 'member', 'team', 6),
  ('finance', 'Finance', 'Handles fees, payments and receipts', 'member', 'all', 7),
  ('viewer', 'Viewer', 'Read-only access', 'member', 'all', 8);

-- The owner role is not listed: it always holds every permission.
insert into crm.preset_role_permissions (role_key, permission)
select 'admin', key from crm.permissions
where key not in ('organization.delete', 'api_keys.manage', 'webhooks.manage');

insert into crm.preset_role_permissions (role_key, permission) values
  ('sales_manager', 'members.view'),
  ('sales_manager', 'conversations.view'),
  ('sales_manager', 'messages.send'),
  ('sales_manager', 'contacts.view'),
  ('sales_manager', 'contacts.edit'),
  ('sales_manager', 'contacts.export'),
  ('sales_manager', 'pipeline.view'),
  ('sales_manager', 'deals.edit'),
  ('sales_manager', 'deals.view_all'),
  ('sales_manager', 'payments.view'),
  ('sales_manager', 'reports.view'),

  ('sales_rep', 'members.view'),
  ('sales_rep', 'conversations.view'),
  ('sales_rep', 'messages.send'),
  ('sales_rep', 'contacts.view'),
  ('sales_rep', 'contacts.edit'),
  ('sales_rep', 'pipeline.view'),
  ('sales_rep', 'deals.edit'),

  ('marketing', 'members.view'),
  ('marketing', 'conversations.view'),
  ('marketing', 'contacts.view'),
  ('marketing', 'contacts.export'),
  ('marketing', 'templates.manage'),
  ('marketing', 'broadcasts.create'),
  ('marketing', 'reports.view'),

  ('teacher', 'members.view'),
  ('teacher', 'conversations.view'),
  ('teacher', 'messages.send'),
  ('teacher', 'contacts.view'),
  ('teacher', 'classroom.manage'),

  ('finance', 'members.view'),
  ('finance', 'contacts.view'),
  ('finance', 'payments.view'),
  ('finance', 'payments.manage'),
  ('finance', 'billing.view'),
  ('finance', 'reports.view'),

  ('viewer', 'members.view'),
  ('viewer', 'conversations.view'),
  ('viewer', 'contacts.view'),
  ('viewer', 'pipeline.view'),
  ('viewer', 'reports.view');
