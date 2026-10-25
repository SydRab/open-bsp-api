-- Lead pipeline preset catalog (P3-02). Data only; the tables are in
-- schemas/10_crm/10-29l_lead_catalog.sql. Copied into each new org by
-- crm.seed_lead_catalogs (10-29n), the same way crm.preset_roles is copied
-- by crm.create_preset_roles. Tailored for high-touch trading/education
-- sales workflows (the product's first vertical), not a generic default --
-- an org can edit, add, or delete any of these freely once seeded.

insert into crm.preset_lead_stages (key, name, sort_order) values
  ('follow_up_required', 'Follow-up Required', 1),
  ('will_visit_office', 'Will Visit Office', 2),
  ('demo_webinar_attended', 'Demo / Webinar Attended', 3),
  ('payment_pending', 'Payment Pending / Link Sent', 4),
  ('enrolled', 'Enrolled', 5),
  ('dropped', 'Dropped', 6);

insert into crm.preset_lead_qualities (key, name, sort_order) values
  ('high_intent', 'High Intent (Has Capital & Ready to Learn)', 1),
  ('medium_intent', 'Medium Intent (Interested, needs nurturing)', 2),
  ('low_intent', 'Low Intent (Looking for free tips/signals only)', 3),
  ('junk_invalid', 'Junk / Invalid', 4);

insert into crm.preset_lead_drop_reasons (key, name, sort_order) values
  ('pricing_issue', 'Pricing Issue', 1),
  ('want_free_signals', 'Want Free Signals (No Learning Intent)', 2),
  ('no_capital', 'No Capital / Low Funds', 3),
  ('enrolled_competitor', 'Enrolled with Competitor', 4),
  ('distance_issue', 'Distance Issue', 5),
  ('timing_issue', 'Timing Issue', 6),
  ('need_offline_only', 'Need Offline Only', 7),
  ('turned_cold', 'Turned Cold', 8),
  ('not_interested', 'Not Interested', 9);
