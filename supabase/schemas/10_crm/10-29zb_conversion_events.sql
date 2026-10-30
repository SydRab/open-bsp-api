-- [crm] P3-09: conversion feedback to Meta. Two tables:
--   crm.lead_event_mappings -- which lead transition (a fixed `status`
--     value, or one of the tenant's own editable `stage`s) reports which
--     Meta event name. Exactly one of (trigger_status, trigger_stage_id)
--     is set, discriminated by trigger_type, same "a transition requires
--     a value first" shape crm.leads' own drop_reason check already uses.
--   crm.outbox_events -- one row per conversion event actually queued for
--     Meta, mirroring crm.webhook_events' exact dedupe/attempts/claim/
--     replay shape (10-29a, P2-01) but reversed in direction and
--     tenant-owned (RLS, a real delivery-log UI) rather than platform-only.
create table crm.lead_event_mappings (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  trigger_type text not null,
  trigger_status text,
  trigger_stage_id uuid,
  meta_event_name text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.lead_event_mappings
add constraint lead_event_mappings_pkey primary key (id);

alter table only crm.lead_event_mappings
add constraint lead_event_mappings_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

-- crm.lead_stages has unique(organization_id, id) (P3-02) -- unlike
-- crm.leads, a composite FK is possible here.
alter table only crm.lead_event_mappings
add constraint lead_event_mappings_stage_fkey
foreign key (organization_id, trigger_stage_id)
references crm.lead_stages(organization_id, id) on delete cascade;

alter table only crm.lead_event_mappings
add constraint lead_event_mappings_trigger_type_check
check (trigger_type in ('status', 'stage'));

alter table only crm.lead_event_mappings
add constraint lead_event_mappings_trigger_status_check
check ((trigger_type = 'status') = (trigger_status is not null));

alter table only crm.lead_event_mappings
add constraint lead_event_mappings_trigger_stage_check
check ((trigger_type = 'stage') = (trigger_stage_id is not null));

alter table only crm.lead_event_mappings
add constraint lead_event_mappings_trigger_status_value_check
check (trigger_status is null or trigger_status in ('open', 'qualified', 'unqualified', 'converted', 'dropped'));

alter table only crm.lead_event_mappings
add constraint lead_event_mappings_meta_event_name_check
check (length(trim(meta_event_name)) between 1 and 40);

-- One mapping per status value / per stage, per org.
create unique index lead_event_mappings_status_key
on crm.lead_event_mappings (organization_id, trigger_status)
where trigger_type = 'status';

create unique index lead_event_mappings_stage_key
on crm.lead_event_mappings (organization_id, trigger_stage_id)
where trigger_type = 'stage';

create trigger set_updated_at
before update
on crm.lead_event_mappings
for each row
execute function public.moddatetime('updated_at');

-- Plain (not composite) lead_id -- crm.leads has no unique(organization_id,
-- id), same recurring limitation crm.tasks/lead_notes/trial_bookings hit.
create table crm.outbox_events (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  lead_id uuid not null,
  -- The org's own connected number whose Meta dataset this goes to --
  -- resolved once at enqueue time from the lead's most recent
  -- conversation, not re-derived at send time.
  organization_address text not null,
  event_name text not null,
  event_time timestamp with time zone not null,
  value numeric,
  currency text,
  ctwa_clid text not null,
  processed_at timestamp with time zone,
  processing_error text,
  attempts int default 0 not null,
  last_attempt_at timestamp with time zone,
  created_at timestamp with time zone default now() not null
);

alter table only crm.outbox_events
add constraint outbox_events_pkey primary key (id);

alter table only crm.outbox_events
add constraint outbox_events_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.outbox_events
add constraint outbox_events_lead_fkey
foreign key (lead_id) references crm.leads(id) on delete cascade;

create index outbox_events_lead_id_idx
on crm.outbox_events (organization_id, lead_id);

-- The sender cron's own scan: unprocessed, under the retry cap. Same
-- shape as crm.webhook_events' own pending index.
create index outbox_events_pending_idx
on crm.outbox_events (organization_id, created_at)
where processed_at is null and attempts < 5;
