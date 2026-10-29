-- [crm] P3-07d: tasks and follow-up reminders, the last named item on
-- P3-07's roadmap line. Lead-scoped (not a standalone to-do list) --
-- that's what "follow-up reminders" means in context, and every other
-- P3-07 piece is lead-scoped too. The reminder itself is sent by
-- crm.sweep_task_reminders (10-29w), WhatsApp-delivered per the
-- WhatsApp-first notification policy, through the tenant's own connected
-- number (never a global credential) -- see docs/ and CLAUDE.md.
create table crm.tasks (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  lead_id uuid not null,
  assigned_to uuid,
  title text not null,
  due_at timestamp with time zone not null,
  completed_at timestamp with time zone,
  -- Set once the reminder sweep has processed this task (in-app always,
  -- WhatsApp only if the assignee has a number and an approved alert
  -- template exists) -- never re-sent after, regardless of channel.
  reminder_sent_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.tasks
add constraint tasks_pkey primary key (id);

alter table only crm.tasks
add constraint tasks_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

-- Plain (not composite) -- crm.leads has no unique(organization_id, id),
-- same limitation hit repeatedly since P3-04.
alter table only crm.tasks
add constraint tasks_lead_fkey
foreign key (lead_id) references crm.leads(id) on delete cascade;

alter table only crm.tasks
add constraint tasks_assigned_to_fkey
foreign key (organization_id, assigned_to)
references public.agents(organization_id, id);

alter table only crm.tasks
add constraint tasks_title_check
check (length(trim(title)) between 1 and 200);

create index tasks_lead_id_idx
on crm.tasks (lead_id);

-- The reminder sweep's own query: due, not completed, not yet reminded.
create index tasks_due_idx
on crm.tasks (organization_id, due_at)
where completed_at is null and reminder_sent_at is null;

create trigger set_updated_at
before update
on crm.tasks
for each row
execute function public.moddatetime('updated_at');
