-- P1-12: RLS test suite. Three things this file adds that no single phase
-- file owns:
--   1. A structural check, generic over every table in public/crm/billing
--      with an organization_id column (present AND future ones) — RLS must
--      be enabled and at least one policy must actually reference
--      organization_id. Catches a new tenant table shipped with no scoping
--      at all, by shape alone, with zero hardcoding.
--   2. A coverage manifest: every organization_id table must be named here.
--      A brand-new one that isn't fails this test with a clear diff —
--      "add it here and write its isolation test" — rather than shipping
--      silently untested (CLAUDE.md: "No table ships without this").
--   3. Real two-tenant data isolation tests for every table that didn't
--      have a direct one yet in crm_01..crm_10 (an audit of all ten files
--      found these gaps), plus a cross-role permission matrix comparing
--      crm.has_permission against the preset catalog for all eight roles.
--
-- Tables already covered by their own phase's test file (crm.organization_
-- profiles, crm.roles, crm.role_permissions, crm.member_roles, crm.
-- organization_packs/_pack_items, crm.audit_log, crm.disclaimer_versions,
-- crm.setting_values, crm.contacts, crm.organization_features, crm.
-- support_access_grants) are not repeated here — only listed in the
-- manifest (#2) so the structural/coverage check still accounts for them.
begin;
\ir _helpers.psql

select plan(33);

-- Fixtures: two unrelated tenants. Org A gets one member per preset role
-- (the cross-role matrix) and a full set of rows across the gap tables
-- (the isolation tests); org B's owner has no relationship to org A at all
-- and is who every isolation check below queries as.
select tests.create_user('iso.owner.a@test.local');
select tests.create_user('iso.admin.a@test.local');
select tests.create_user('iso.sales_manager.a@test.local');
select tests.create_user('iso.sales_rep.a@test.local');
select tests.create_user('iso.marketing.a@test.local');
select tests.create_user('iso.teacher.a@test.local');
select tests.create_user('iso.finance.a@test.local');
select tests.create_user('iso.viewer.a@test.local');
select tests.create_user('iso.owner.b@test.local');

select tests.create_org('iso.owner.a@test.local', 'Isolation A') as org_a \gset
select tests.create_org('iso.owner.b@test.local', 'Isolation B') as org_b \gset
select tests.add_member(:'org_a', 'iso.admin.a@test.local', 'admin');
select tests.add_member(:'org_a', 'iso.sales_manager.a@test.local', 'sales_manager');
select tests.add_member(:'org_a', 'iso.sales_rep.a@test.local', 'sales_rep');
select tests.add_member(:'org_a', 'iso.marketing.a@test.local', 'marketing');
select tests.add_member(:'org_a', 'iso.teacher.a@test.local', 'teacher');
select tests.add_member(:'org_a', 'iso.finance.a@test.local', 'finance');
select tests.add_member(:'org_a', 'iso.viewer.a@test.local', 'viewer');

select tests.as_postgres();
select tests.agent_id(:'org_a', 'iso.owner.a@test.local') as owner_a_agent \gset

insert into public.organizations_addresses (organization_id, service, address, status) values
  (:'org_a', 'whatsapp', '111', 'connected');
insert into public.contacts_addresses (organization_id, organization_address, service, address) values
  (:'org_a', '111', 'whatsapp', '919000000001');
insert into public.conversations (id, organization_id, organization_address, address, service, name) values
  ('00000000-0000-0000-0000-0000000000c9', :'org_a', '111', '919000000001', 'whatsapp', 'Isolation lead');
insert into public.messages (organization_id, conversation_id, service, organization_address, content) values
  (:'org_a', '00000000-0000-0000-0000-0000000000c9', 'whatsapp', '111', '{}'::jsonb);
insert into public.conversations_agents (organization_id, service, organization_address, conversation_id, agent_id) values
  (:'org_a', 'whatsapp', '111', '00000000-0000-0000-0000-0000000000c9', :'owner_a_agent');
insert into public.api_keys (organization_id, key, role, name) values
  (:'org_a', 'iso-test-key', 'member', 'Isolation key');
insert into public.webhooks (organization_id, table_name, operations, url) values
  (:'org_a', 'messages', '{insert}', 'https://example.com/hook');
insert into public.onboarding_tokens (name, organization_id, expires_at, service) values
  ('Isolation token', :'org_a', now() + interval '1 day', 'whatsapp');
insert into public.logs (organization_id, level, category, message) values
  (:'org_a', 'error', 'test', 'Isolation test log line');
insert into crm.member_address_access (agent_id, organization_id, service, address) values
  (:'owner_a_agent', :'org_a', 'whatsapp', '111');
insert into billing.invoices (id, organization_id, status, subtotal) values
  ('00000000-0000-0000-0000-0000000000ba', :'org_a', 'draft', 100);
insert into billing.payments (invoice_id, organization_id, amount, status) values
  ('00000000-0000-0000-0000-0000000000ba', :'org_a', 100, 'pending');
insert into billing.ledger (organization_id, product_id, type, quantity) values
  (:'org_a', 'members', 'grant', 1);

select tests.as_user('iso.owner.a@test.local');
select crm.create_team(:'org_a', 'Isolation Team') as team_a \gset
select crm.set_member_permission_override(
  tests.agent_id(:'org_a', 'iso.viewer.a@test.local'), 'messages.send', true
);
select crm.invite_member(:'org_a', 'invitee@test.local', 'viewer');

-- Structural: every table with organization_id has RLS enabled and at
-- least one policy that scopes by it — directly, via a helper like
-- crm.get_permitted_orgs whose own definition does, OR (public.
-- conversations_agents, the one allowed exception) by joining to a table
-- that is itself organization_id-scoped, confirmed by hand from its actual
-- policies: every read/write there requires a matching row in
-- public.conversations, whose own RLS already does the org scoping.
select is_empty(
  $$
  select n.nspname || '.' || c.relname
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relkind = 'r'
    and n.nspname in ('public', 'crm', 'billing')
    and n.nspname || '.' || c.relname <> 'public.conversations_agents'
    and exists (
      select 1 from information_schema.columns col
      where col.table_schema = n.nspname and col.table_name = c.relname
        and col.column_name = 'organization_id'
    )
    and not (
      c.relrowsecurity
      and exists (
        select 1 from pg_policies p
        where p.schemaname = n.nspname and p.tablename = c.relname
          and (p.qual ilike '%organization_id%' or p.with_check ilike '%organization_id%')
      )
    )
  $$,
  'every table with organization_id has RLS enabled and a policy scoped by it'
);

-- Coverage manifest: every table with organization_id must be listed here.
-- Add a new one and its isolation test (here, or in its own phase file)
-- together, or this fails with a diff naming exactly what is missing.
select results_eq(
  $$
  select (n.nspname::text || '.' || c.relname::text)::text collate "C"
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relkind = 'r'
    and n.nspname in ('public', 'crm', 'billing')
    and exists (
      select 1 from information_schema.columns col
      where col.table_schema = n.nspname and col.table_name = c.relname
        and col.column_name = 'organization_id'
    )
  order by 1
  $$,
  $$
  select t.tbl::text collate "C" from (values
    ('billing.invoices'), ('billing.ledger'), ('billing.payments'),
    ('billing.subscriptions'), ('billing.usage'), ('crm.audit_log'), ('crm.canned_replies'), ('crm.contact_addresses'),
    ('crm.contacts'), ('crm.contacts_consent'), ('crm.conversation_assignments'), ('crm.conversation_tags'), ('crm.disclaimer_versions'), ('crm.invitation_roles'),
    ('crm.member_address_access'), ('crm.member_permission_overrides'),
    ('crm.member_roles'), ('crm.organization_features'),
    ('crm.organization_pack_items'), ('crm.organization_packs'),
    ('crm.organization_profiles'), ('crm.role_permissions'), ('crm.roles'),
    ('crm.send_rate_buckets'), ('crm.setting_values'), ('crm.support_access_grants'),
    ('crm.tags'), ('crm.team_members'), ('crm.teams'), ('crm.templates'), ('public.agents'),
    ('public.api_keys'), ('public.contacts_addresses'),
    ('public.conversations'), ('public.conversations_agents'),
    ('public.invitations'), ('public.logs'), ('public.messages'),
    ('public.onboarding_tokens'), ('public.organizations_addresses'),
    ('public.webhooks')
  ) as t(tbl)
  order by 1
  $$,
  'every tenant table is on the P1-12 coverage manifest'
);

-- Isolation: tenant B's owner, unrelated to org A, sees none of org A's
-- rows in any of these tables (previously untested, found by a P1-12 audit
-- of crm_01..crm_10).
select tests.as_user('iso.owner.b@test.local');

select is_empty(
  format('select 1 from public.agents where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s agents'
);
select is_empty(
  format('select 1 from public.api_keys where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s API keys'
);
select is_empty(
  format('select 1 from public.conversations where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s conversations'
);
select is_empty(
  format('select 1 from public.messages where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s messages'
);
select is_empty(
  format('select 1 from public.conversations_agents where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s conversation memberships'
);
select is_empty(
  format('select 1 from public.contacts_addresses where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s contact addresses'
);
select is_empty(
  format('select 1 from public.organizations_addresses where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s connected numbers'
);
select is_empty(
  format('select 1 from public.logs where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s logs'
);
select is_empty(
  format('select 1 from public.onboarding_tokens where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s onboarding tokens'
);
select is_empty(
  format('select 1 from public.webhooks where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s webhooks'
);
select is_empty(
  format('select 1 from public.organizations where id = %L', :'org_a'),
  'tenant B cannot read tenant A''s organization row'
);

-- A guessed/leaked id is not enough to write into another tenant either —
-- the single highest-sensitivity table (chat content) gets a write check,
-- not just a read one.
select throws_ok(
  format(
    $$ insert into public.messages (organization_id, conversation_id, service, organization_address, content)
       values (%L, '00000000-0000-0000-0000-0000000000c9', 'whatsapp', '111', '{}'::jsonb) $$,
    :'org_a'
  ),
  '42501',
  null,
  'tenant B cannot insert a message into tenant A''s conversation'
);

select is_empty(
  format('select 1 from crm.contact_addresses where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s crm contact addresses'
);
select is_empty(
  format('select 1 from crm.member_address_access where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s member address access rows'
);
select is_empty(
  format(
    'select 1 from crm.member_permission_overrides where agent_id = %L',
    tests.agent_id(:'org_a', 'iso.viewer.a@test.local')
  ),
  'tenant B cannot read tenant A''s member permission overrides'
);
select is_empty(
  format('select 1 from crm.teams where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s teams'
);
select is_empty(
  format(
    'select 1 from crm.team_members where team_id = %L',
    :'team_a'
  ),
  'tenant B cannot read tenant A''s team membership'
);
select is_empty(
  format('select 1 from crm.invitation_roles where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s invitation roles'
);
select is_empty(
  format('select 1 from billing.usage where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s billing usage'
);
select is_empty(
  format('select 1 from billing.subscriptions where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s subscription'
);
select is_empty(
  format('select 1 from billing.invoices where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s invoices'
);
select is_empty(
  format('select 1 from billing.payments where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s payments'
);
select is_empty(
  format('select 1 from billing.ledger where organization_id = %L', :'org_a'),
  'tenant B cannot read tenant A''s ledger entries'
);

-- Cross-role: for every preset role, what a fresh member of that role
-- actually holds in a real organization matches the preset catalog exactly
-- (owner is implicit — not in crm.preset_role_permissions, holds
-- everything). Catches drift between the catalog and enforcement that a
-- one-off "can X" assertion would not.
select tests.as_user('iso.owner.a@test.local');
select results_eq(
  format('select crm.my_permissions(%L) order by 1', :'org_a'),
  'select key from crm.permissions order by 1',
  'owner holds every permission'
);

select tests.as_user('iso.admin.a@test.local');
select results_eq(
  format('select crm.my_permissions(%L) order by 1', :'org_a'),
  $$ select permission from crm.preset_role_permissions where role_key = 'admin' order by 1 $$,
  'admin holds exactly the admin preset'
);

select tests.as_user('iso.sales_manager.a@test.local');
select results_eq(
  format('select crm.my_permissions(%L) order by 1', :'org_a'),
  $$ select permission from crm.preset_role_permissions where role_key = 'sales_manager' order by 1 $$,
  'sales manager holds exactly the sales_manager preset'
);

select tests.as_user('iso.sales_rep.a@test.local');
select results_eq(
  format('select crm.my_permissions(%L) order by 1', :'org_a'),
  $$ select permission from crm.preset_role_permissions where role_key = 'sales_rep' order by 1 $$,
  'sales rep holds exactly the sales_rep preset'
);

select tests.as_user('iso.marketing.a@test.local');
select results_eq(
  format('select crm.my_permissions(%L) order by 1', :'org_a'),
  $$ select permission from crm.preset_role_permissions where role_key = 'marketing' order by 1 $$,
  'marketing holds exactly the marketing preset'
);

select tests.as_user('iso.teacher.a@test.local');
select results_eq(
  format('select crm.my_permissions(%L) order by 1', :'org_a'),
  $$ select permission from crm.preset_role_permissions where role_key = 'teacher' order by 1 $$,
  'teacher holds exactly the teacher preset'
);

select tests.as_user('iso.finance.a@test.local');
select results_eq(
  format('select crm.my_permissions(%L) order by 1', :'org_a'),
  $$ select permission from crm.preset_role_permissions where role_key = 'finance' order by 1 $$,
  'finance holds exactly the finance preset'
);

-- The viewer has one override (messages.send, set above) — holds the
-- preset plus that one extra permission, not the bare preset.
select tests.as_user('iso.viewer.a@test.local');
select results_eq(
  format('select crm.my_permissions(%L) order by 1', :'org_a'),
  $$
  select permission from crm.preset_role_permissions where role_key = 'viewer'
  union
  select 'messages.send'
  order by 1
  $$,
  'viewer holds the viewer preset plus its one override'
);

select * from finish();
rollback;
