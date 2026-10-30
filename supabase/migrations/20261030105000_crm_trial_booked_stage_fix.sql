-- Fix (P3-09): the trading_institute preset lead-stage catalog
-- (20261025134910_crm_lead_preset_catalog.sql) had no stage representing
-- "a trial class was booked" -- crm.preset_lead_stages' real keys are
-- follow_up_required/will_visit_office/demo_webinar_attended/
-- payment_pending/enrolled/dropped, none of them 'trial_booked'. P3-08's
-- own crm._advance_to_trial_booked_stage (which looks up crm.lead_stages
-- by key = 'trial_booked') and P3-09's own roadmap line ("Trial Booked ->
-- custom event") both assumed this stage exists -- it does not, and never
-- has. Caught by P3-09's own test suite: _advance_to_trial_booked_stage
-- has been a silent no-op since it shipped (P3-08's own tests never
-- actually exercised the stage-not-found branch, so this went unnoticed).
--
-- (The "Lead Inquiring -> Trial Booked -> Paid Student -> Lost" sequence
-- crm_04_packs.test.sql's own fixture shows is a DIFFERENT, unrelated
-- catalog -- crm.organization_pack_items kind='pipeline_stage', legacy
-- pack content from before P3-02 built crm.lead_stages, with no consumer
-- anywhere in the codebase. Not the same thing, despite the similar name.)
--
-- Appended at the end (sort_order 7), not spliced into the middle, so no
-- existing organization's own sort_order customization (crm.lead_stages
-- is tenant-editable from the moment it's seeded) is silently overwritten.
insert into crm.preset_lead_stages (key, name, sort_order) values
  ('trial_booked', 'Trial Booked', 7);

-- Backfill: organizations created before this fix never got this stage
-- from crm.seed_lead_catalogs. Same on-conflict-do-nothing re-seed
-- pattern already used for every other catalog backfill this session.
insert into crm.lead_stages (organization_id, key, name, is_preset, sort_order)
select o.id, 'trial_booked', 'Trial Booked', true, 7
from public.organizations o
on conflict (organization_id, key) do nothing;
