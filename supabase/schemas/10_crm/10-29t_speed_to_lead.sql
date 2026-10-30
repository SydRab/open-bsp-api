-- [crm] P3-06: speed-to-lead. The SLA clock itself lives on crm.leads
-- (first_response_due_at/first_responded_at, 10-29m) -- this file is just
-- the alert sink: a durable, per-agent notification record, unlike P2-09f's
-- browser-popup-only mechanism (client-side `Notification`, nothing
-- survives a closed tab). In-app only for v1, confirmed with the user:
-- email and push both need new third-party infrastructure (a provider/
-- API key, VAPID keys + a service worker) that doesn't exist anywhere in
-- either repo yet -- explicit follow-on work once a provider is chosen.
create table crm.notifications (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  -- The recipient. Always a human member -- an AI agent never needs a
  -- bell icon.
  agent_id uuid not null,
  kind text not null,
  title text not null,
  body text,
  -- The lead this notification is about, if any. Soft enough to survive
  -- the lead itself being deleted -- on delete cascade, since a
  -- notification about a gone lead is noise, not history (crm.audit_log
  -- is the durable record of what happened).
  lead_id uuid,
  read_at timestamp with time zone,
  created_at timestamp with time zone default now() not null
);

alter table only crm.notifications
add constraint notifications_pkey primary key (id);

alter table only crm.notifications
add constraint notifications_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.notifications
add constraint notifications_agent_fkey
foreign key (organization_id, agent_id)
references public.agents(organization_id, id) on delete cascade;

-- Not a composite FK -- crm.leads has no unique(organization_id, id)
-- (crm.lead_qualification_state, P3-04, hits the same constraint and
-- uses the same plain id-only FK).
alter table only crm.notifications
add constraint notifications_lead_fkey
foreign key (lead_id) references crm.leads(id) on delete cascade;

alter table only crm.notifications
add constraint notifications_kind_check
check (kind in (
  'lead_sla_breached', 'lead_escalated_to_manager', 'lead_auto_reassigned',
  -- [crm] P3-07d
  'task_due',
  -- [crm] P3-08
  'trial_booked'
));

-- The bell icon's own query: this agent's unread notifications, newest
-- first.
create index notifications_agent_unread_idx
on crm.notifications (organization_id, agent_id, created_at desc)
where read_at is null;
