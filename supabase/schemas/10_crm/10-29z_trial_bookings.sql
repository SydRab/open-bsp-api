-- [crm] P3-08: trial booking. One row per booked (or since-cancelled)
-- slot -- a reschedule is a cancel + a fresh row, not an update, so the
-- history of what a lead actually picked stays intact (crm.audit_log
-- already records the transitions; this table is the current/queryable
-- state, same split P3-07d's crm.tasks and crm.audit_log already have).
--
-- There is no separate "slot" catalog table: a slot is just a (day, time)
-- computed on demand from the trial.schedule tenant setting (crm.
-- _upcoming_trial_slots, 10-29za) -- an admin edits one recurring weekly
-- pattern instead of creating slot rows forever, same "defaults with no
-- setup" reasoning P3-07d's seeded template used. Capacity is enforced by
-- counting booked rows for the same slot_start, not a separate seats
-- counter.
create table crm.trial_bookings (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  lead_id uuid not null,
  slot_start timestamp with time zone not null,
  slot_end timestamp with time zone not null,
  status text not null default 'booked',
  confirmed_at timestamp with time zone default now() not null,
  cancelled_at timestamp with time zone,
  reminder_sent_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.trial_bookings
add constraint trial_bookings_pkey primary key (id);

alter table only crm.trial_bookings
add constraint trial_bookings_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

-- Plain (not composite) -- crm.leads has no unique(organization_id, id),
-- same recurring limitation crm.tasks and crm.lead_notes already hit.
alter table only crm.trial_bookings
add constraint trial_bookings_lead_fkey
foreign key (lead_id) references crm.leads(id) on delete cascade;

alter table only crm.trial_bookings
add constraint trial_bookings_status_check
check (status in ('booked', 'cancelled', 'completed'));

alter table only crm.trial_bookings
add constraint trial_bookings_cancelled_at_check
check ((status = 'cancelled') = (cancelled_at is not null));

create index trial_bookings_lead_id_idx
on crm.trial_bookings (organization_id, lead_id);

-- Capacity check for a candidate slot (crm._upcoming_trial_slots) and the
-- reminder sweep's due-and-unsent scan both filter on this.
create index trial_bookings_slot_idx
on crm.trial_bookings (organization_id, slot_start)
where status = 'booked';

create trigger set_updated_at
before update
on crm.trial_bookings
for each row
execute function public.moddatetime('updated_at');
