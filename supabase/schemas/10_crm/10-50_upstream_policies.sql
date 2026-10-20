-- crm permissions on UPSTREAM tables (ADR 0002 §5). Each policy here is
-- RESTRICTIVE: Postgres ANDs it with the upstream permissive policies, so it
-- can only take access away — never grant what the upstream tier does not.
-- Upstream files stay untouched.
--
-- Service-role and SECURITY DEFINER paths (webhooks, dispatchers, triggers)
-- bypass RLS and are unaffected.

-- Organizations: editing needs organization.manage; deleting is never done
-- through the API any more — it is crm.request_organization_deletion (soft,
-- 30-day grace) followed by crm.purge_organizations (platform).
create policy "crm: updating an org needs organization.manage"
on public.organizations
as restrictive
for update
to authenticated, anon
using (id in (select crm.get_permitted_orgs('organization.manage')));

create policy "crm: orgs are deleted through the deletion request"
on public.organizations
as restrictive
for delete
to authenticated, anon
using (false);

-- Conversations and messages: reading needs conversations.view, and a
-- number-scoped member sees only their numbers. Internal `local` chat stays
-- open to every member for both. Sending needs messages.send.
create policy "crm: reading conversations needs conversations.view"
on public.conversations
as restrictive
for select
to authenticated, anon
using (
  service = 'local'::public.service
  or (
    organization_id in (select crm.get_permitted_orgs('conversations.view'))
    and (organization_id, service, organization_address) not in (
      select h.organization_id, h.service, h.address
      from crm.get_hidden_addresses() h
    )
  )
);

create policy "crm: reading messages needs conversations.view"
on public.messages
as restrictive
for select
to authenticated, anon
using (
  service = 'local'::public.service
  or (
    organization_id in (select crm.get_permitted_orgs('conversations.view'))
    and (organization_id, service, organization_address) not in (
      select h.organization_id, h.service, h.address
      from crm.get_hidden_addresses() h
    )
  )
);

create policy "crm: sending needs messages.send"
on public.messages
as restrictive
for insert
to authenticated, anon
with check (
  service = 'local'::public.service
  or organization_id in (select crm.get_permitted_orgs('messages.send'))
);

-- Contacts: reading needs contacts.view or conversations.view (the inbox
-- shows contact names); writing needs contacts.edit.
create policy "crm: reading contacts needs contacts.view"
on public.contacts_addresses
as restrictive
for select
to authenticated, anon
using (
  (
    organization_id in (select crm.get_permitted_orgs('contacts.view'))
    or organization_id in (select crm.get_permitted_orgs('conversations.view'))
  )
  and (organization_id, service, organization_address) not in (
    select h.organization_id, h.service, h.address
    from crm.get_hidden_addresses() h
  )
);

create policy "crm: adding contacts needs contacts.edit"
on public.contacts_addresses
as restrictive
for insert
to authenticated, anon
with check (organization_id in (select crm.get_permitted_orgs('contacts.edit')));

create policy "crm: editing contacts needs contacts.edit"
on public.contacts_addresses
as restrictive
for update
to authenticated, anon
using (organization_id in (select crm.get_permitted_orgs('contacts.edit')));

create policy "crm: deleting contacts needs contacts.edit"
on public.contacts_addresses
as restrictive
for delete
to authenticated, anon
using (organization_id in (select crm.get_permitted_orgs('contacts.edit')));

-- Connected numbers: a number-scoped member sees only their numbers.
create policy "crm: number access scope"
on public.organizations_addresses
as restrictive
for select
to authenticated, anon
using (
  (organization_id, service, address) not in (
    select h.organization_id, h.service, h.address
    from crm.get_hidden_addresses() h
  )
);

-- AI agents: creating and removing them needs ai_agents.manage.
create policy "crm: creating ai agents needs ai_agents.manage"
on public.agents
as restrictive
for insert
to authenticated, anon
with check (
  user_id is not null
  or organization_id in (select crm.get_permitted_orgs('ai_agents.manage'))
);

create policy "crm: deleting ai agents needs ai_agents.manage"
on public.agents
as restrictive
for delete
to authenticated, anon
using (
  user_id is not null
  or organization_id in (select crm.get_permitted_orgs('ai_agents.manage'))
);
