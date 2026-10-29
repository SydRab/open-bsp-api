-- Lead model (P3-02). crm.contacts (P1-06) is the person; crm.leads is one
-- "pursuit" of them -- at most one per contact, ever (unique
-- (organization_id, contact_id) below is what "dedupe by WhatsApp ID"
-- means in practice, since contact_id is already deduped by WhatsApp ID
-- via crm.contact_addresses). Its own schema comment already names this
-- table as what P3-02 would extend ("Merging one person across services
-- is P3-02"), confirming crm.contacts over a new, separate "person" entity.
--
-- status vs stage, the roadmap's own distinction: status (open/qualified/
-- unqualified/converted/dropped) is a FIXED engine lifecycle -- later
-- phases (qualification, conversion feedback) key off these exact values,
-- so it is not tenant-editable. stage/quality/drop_reason are the tenant's
-- own funnel vocabulary (crm.lead_stages & co., 10-29l/10-29n), genuinely
-- customizable because nothing in the engine cares which specific one is
-- chosen.
--
-- Scope cuts, stated plainly: nothing creates a crm.leads row automatically
-- yet (no trigger on crm.contacts or public.messages) -- that wiring
-- belongs to whichever task first needs a lead to exist (P3-03's instant
-- welcome, or P3-04's qualification engine), which should call
-- crm.find_or_create_lead (10-29n) explicitly. No settings UI for the
-- catalogs either -- P3-07 (Pipeline UI) or a dedicated settings screen is
-- the natural home.
create table crm.lead_stages (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  key text not null,
  name text not null,
  is_preset boolean not null default true,
  sort_order int not null default 0,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.lead_stages
add constraint lead_stages_pkey primary key (id);

alter table only crm.lead_stages
add constraint lead_stages_organization_id_id_key unique (organization_id, id);

alter table only crm.lead_stages
add constraint lead_stages_organization_id_key_key unique (organization_id, key);

alter table only crm.lead_stages
add constraint lead_stages_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.lead_stages
add constraint lead_stages_name_check
check (length(trim(name)) between 1 and 60);

create table crm.lead_qualities (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  key text not null,
  name text not null,
  is_preset boolean not null default true,
  sort_order int not null default 0,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.lead_qualities
add constraint lead_qualities_pkey primary key (id);

alter table only crm.lead_qualities
add constraint lead_qualities_organization_id_id_key unique (organization_id, id);

alter table only crm.lead_qualities
add constraint lead_qualities_organization_id_key_key unique (organization_id, key);

alter table only crm.lead_qualities
add constraint lead_qualities_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.lead_qualities
add constraint lead_qualities_name_check
check (length(trim(name)) between 1 and 60);

create table crm.lead_drop_reasons (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  key text not null,
  name text not null,
  is_preset boolean not null default true,
  sort_order int not null default 0,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.lead_drop_reasons
add constraint lead_drop_reasons_pkey primary key (id);

alter table only crm.lead_drop_reasons
add constraint lead_drop_reasons_organization_id_id_key unique (organization_id, id);

alter table only crm.lead_drop_reasons
add constraint lead_drop_reasons_organization_id_key_key unique (organization_id, key);

alter table only crm.lead_drop_reasons
add constraint lead_drop_reasons_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.lead_drop_reasons
add constraint lead_drop_reasons_name_check
check (length(trim(name)) between 1 and 60);

create table crm.leads (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  contact_id uuid not null,
  -- How this pursuit started. Derived from crm.contacts' own first_touch_
  -- referral (P3-01) at creation time, not re-derived later.
  source text not null,
  status text not null default 'open',
  stage_id uuid,
  quality_id uuid,
  drop_reason_id uuid,
  -- [crm] P3-04: the qualification engine's computed total (crm.
  -- qualification_question_scores, 10-29p). Null until qualification
  -- completes; a manual quality/status override afterwards does not clear
  -- it -- it stays as a record of what the engine computed.
  score int,
  -- [crm] P3-05: who currently owns this lead (crm._pick_assignee,
  -- 10-29s). Null = unassigned, visible for manual pickup -- the engine
  -- leaves it that way rather than guessing when a pool is exhausted.
  assigned_to uuid,
  assigned_at timestamp with time zone,
  -- [crm] P3-06: the first-response SLA clock (crm.z_set_response_deadline,
  -- 10-29u) -- set from assigned_at + speed_to_lead.first_response_sla_
  -- minutes whenever assigned_to changes and nobody has responded yet.
  -- Null until a lead has an assignee: there's nobody to escalate from
  -- before that.
  first_response_due_at timestamp with time zone,
  -- Set once by crm.z_record_first_response (10-29u) on the first human-
  -- sent (not the welcome/qualification engine's own automated) message
  -- in this lead's conversation after assignment. Immutable afterwards --
  -- this is about the FIRST response only, not an ongoing SLA.
  first_responded_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.leads
add constraint leads_pkey primary key (id);

-- The dedupe: at most one lead per contact, ever. Reopening (crm.
-- set_lead_status, 10-29n) reuses this same row rather than inserting a
-- second one.
alter table only crm.leads
add constraint leads_organization_id_contact_id_key unique (organization_id, contact_id);

alter table only crm.leads
add constraint leads_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.leads
add constraint leads_contact_fkey
foreign key (organization_id, contact_id)
references crm.contacts(organization_id, id) on delete cascade;

alter table only crm.leads
add constraint leads_stage_fkey
foreign key (organization_id, stage_id)
references crm.lead_stages(organization_id, id);

alter table only crm.leads
add constraint leads_quality_fkey
foreign key (organization_id, quality_id)
references crm.lead_qualities(organization_id, id);

alter table only crm.leads
add constraint leads_drop_reason_fkey
foreign key (organization_id, drop_reason_id)
references crm.lead_drop_reasons(organization_id, id);

alter table only crm.leads
add constraint leads_assigned_to_fkey
foreign key (organization_id, assigned_to)
references public.agents(organization_id, id);

alter table only crm.leads
add constraint leads_source_check
check (source in ('ctwa_ad', 'ctwa_post', 'organic', 'manual'));

alter table only crm.leads
add constraint leads_status_check
check (status in ('open', 'qualified', 'unqualified', 'converted', 'dropped'));

-- A drop reason names why a lead was dropped -- required exactly then, not
-- a free-floating value on an open lead.
alter table only crm.leads
add constraint leads_drop_reason_required_check
check ((status = 'dropped') = (drop_reason_id is not null));

create index leads_organization_id_idx
on crm.leads (organization_id);

create index leads_organization_id_status_idx
on crm.leads (organization_id, status);

-- [crm] P3-05: capacity-cap counts ("how many open leads does this agent
-- already hold") and "my leads" views both filter on this.
create index leads_assigned_to_idx
on crm.leads (organization_id, assigned_to)
where assigned_to is not null;

create trigger set_updated_at
before update
on crm.lead_stages
for each row
execute function public.moddatetime('updated_at');

create trigger set_updated_at
before update
on crm.lead_qualities
for each row
execute function public.moddatetime('updated_at');

create trigger set_updated_at
before update
on crm.lead_drop_reasons
for each row
execute function public.moddatetime('updated_at');

create trigger set_updated_at
before update
on crm.leads
for each row
execute function public.moddatetime('updated_at');
