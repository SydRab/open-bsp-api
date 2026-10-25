-- [crm] P3-04: qualification engine tables.
--
-- The question SET already existed before this task: crm.organization_
-- pack_items of kind 'qualification_question' (P1-05/10-04, flattened by
-- crm.pack_items at 10-13) -- the trading_institute pack ships 5 real
-- questions, each naming a `field` that is itself an existing custom_field
-- definition (10-17) with its own options/labels. This task only adds the
-- orchestration: a resumable per-lead progress tracker, and a tenant-
-- editable scoring catalog (mirrors crm.lead_stages & co., 10-29l/10-29m:
-- a platform preset table + an org-scoped editable copy).
--
-- Scope cuts, stated plainly (confirmed with the user before building):
--   * delivery is buttons/lists only (every current question's field fits
--     within WhatsApp's 3-button/10-row limits) -- Flow delivery (already
--     built generically, P2-06) is deferred to whichever future question
--     needs a richer form;
--   * only recognized button/list taps advance the flow; anything else
--     re-prompts the same question (crm._send_nudge, 10-29q) up to
--     qualification.max_nudges, then the lead is left open for a human --
--     no automatic drop;
--   * auto-start is opt-in (qualification.auto_start, off by default),
--     same reasoning as messaging.instant_welcome (P3-03): an org must
--     deliberately turn on automatic outbound messaging.

-- One row per lead: which question (if any) is pending, and the nudge
-- budget already spent on it. Answers themselves are NOT duplicated here --
-- they land in crm.contacts.custom_fields (10-17), the existing mechanism --
-- this table only tracks position, so a process restarting or a contact
-- replying out of order can resume correctly.
create table crm.lead_qualification_state (
  lead_id uuid not null,
  organization_id uuid not null,
  -- The pack item key (crm.organization_pack_items.item_key) of the
  -- question currently awaiting a reply. Null once completed.
  current_question_key text,
  asked_at timestamp with time zone,
  nudge_count int not null default 0,
  last_nudged_at timestamp with time zone,
  completed_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.lead_qualification_state
add constraint lead_qualification_state_pkey primary key (lead_id);

alter table only crm.lead_qualification_state
add constraint lead_qualification_state_lead_fkey
foreign key (lead_id) references crm.leads(id) on delete cascade;

alter table only crm.lead_qualification_state
add constraint lead_qualification_state_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

-- The cron sweep (crm.sweep_qualification_nudges, 10-29q) scans for stalled
-- rows across every org.
create index lead_qualification_state_pending_idx
on crm.lead_qualification_state (asked_at)
where completed_at is null;

create index lead_qualification_state_organization_id_idx
on crm.lead_qualification_state (organization_id);

create trigger set_updated_at
before update
on crm.lead_qualification_state
for each row
execute function public.moddatetime('updated_at');

-- Scoring catalog: points per (field, answer value), and the score bands
-- that map a total to a lead quality + qualified/unqualified. Keyed by the
-- custom field's own key (not the question's pack-item key) because that's
-- where the answer is actually stored (crm.contacts.custom_fields) and
-- survives regardless of which question asked it.
create table crm.qualification_question_scores (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  field_key text not null,
  answer_value text not null,
  points int not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.qualification_question_scores
add constraint qualification_question_scores_pkey primary key (id);

alter table only crm.qualification_question_scores
add constraint qualification_question_scores_key
unique (organization_id, field_key, answer_value);

alter table only crm.qualification_question_scores
add constraint qualification_question_scores_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

create trigger set_updated_at
before update
on crm.qualification_question_scores
for each row
execute function public.moddatetime('updated_at');

create table crm.qualification_score_thresholds (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  -- The lead's total score maps to the highest-min_score band it clears.
  min_score int not null,
  quality_id uuid,
  status text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.qualification_score_thresholds
add constraint qualification_score_thresholds_pkey primary key (id);

alter table only crm.qualification_score_thresholds
add constraint qualification_score_thresholds_key
unique (organization_id, min_score);

alter table only crm.qualification_score_thresholds
add constraint qualification_score_thresholds_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.qualification_score_thresholds
add constraint qualification_score_thresholds_quality_fkey
foreign key (organization_id, quality_id)
references crm.lead_qualities(organization_id, id);

alter table only crm.qualification_score_thresholds
add constraint qualification_score_thresholds_status_check
check (status in ('qualified', 'unqualified'));

create trigger set_updated_at
before update
on crm.qualification_score_thresholds
for each row
execute function public.moddatetime('updated_at');

-- Platform defaults, scoped by pack (a future non-trading vertical pack
-- would need its own rows here) -- copied into each org's editable copy by
-- crm.seed_qualification_scoring (10-29q), the same shape crm.
-- seed_lead_catalogs (P3-02) already uses for the other lead catalogs.
create table crm.preset_qualification_question_scores (
  pack_key text not null,
  field_key text not null,
  answer_value text not null,
  points int not null
);

alter table only crm.preset_qualification_question_scores
add constraint preset_qualification_question_scores_pkey
primary key (pack_key, field_key, answer_value);

alter table only crm.preset_qualification_question_scores
add constraint preset_qualification_question_scores_pack_fkey
foreign key (pack_key) references crm.vertical_packs(key);

create table crm.preset_qualification_score_thresholds (
  pack_key text not null,
  min_score int not null,
  quality_key text not null,
  status text not null
);

alter table only crm.preset_qualification_score_thresholds
add constraint preset_qualification_score_thresholds_pkey
primary key (pack_key, min_score);

alter table only crm.preset_qualification_score_thresholds
add constraint preset_qualification_score_thresholds_pack_fkey
foreign key (pack_key) references crm.vertical_packs(key);

alter table only crm.preset_qualification_score_thresholds
add constraint preset_qualification_score_thresholds_quality_fkey
foreign key (quality_key) references crm.preset_lead_qualities(key);

alter table only crm.preset_qualification_score_thresholds
add constraint preset_qualification_score_thresholds_status_check
check (status in ('qualified', 'unqualified'));
