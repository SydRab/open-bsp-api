-- Audit log (P1-08): an append-only record of who changed what in an
-- organization. Rows are written only by crm.write_audit (10-14), mostly from
-- the triggers in 10-21; later phases call it for stage changes, disclaimer
-- edits, exports and token connects.
--
-- Append-only: no API role can insert, update or delete rows (10-40), and a
-- trigger refuses update, delete and truncate even for the table owner. The
-- one exception is crm.purge_organizations: when an organization is
-- hard-deleted after its grace period, its audit rows go with it (the
-- tenant's right to erasure under DPDP). See 10-11 and 10-21.
--
-- What goes in `details`: ids, keys and the changed fields. Never message
-- text, contact phone numbers or tokens.

create table crm.audit_log (
  id bigint generated always as identity not null,
  organization_id uuid not null,
  created_at timestamp with time zone default now() not null,
  -- user: a signed-in member; api_key: an organization API key; service: the
  -- platform (edge functions, the super-admin console); system: database
  -- jobs, migrations and anything else without a caller.
  actor_type text not null,
  actor_user_id uuid,
  -- The actor's membership in this organization, when they have one. No
  -- foreign key: entries outlive the rows they mention.
  actor_agent_id uuid,
  actor_api_key_id uuid,
  -- `area.verb`, e.g. member.role_changed, role.permission_granted.
  action text not null,
  target_type text,
  target_id text,
  details jsonb default '{}'::jsonb not null,
  request_id text
);

alter table only crm.audit_log
add constraint audit_log_pkey primary key (id);

alter table only crm.audit_log
add constraint audit_log_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.audit_log
add constraint audit_log_actor_type_check
check (actor_type in ('user', 'api_key', 'service', 'system'));

alter table only crm.audit_log
add constraint audit_log_action_check
check (action ~ '^[a-z_]+\.[a-z_]+$');

create index audit_log_organization_id_id_idx
on crm.audit_log (organization_id, id desc);

create index audit_log_organization_id_action_idx
on crm.audit_log (organization_id, action);

create index audit_log_organization_id_actor_idx
on crm.audit_log (organization_id, actor_agent_id);
