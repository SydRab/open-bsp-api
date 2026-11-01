-- [crm] P4-04: billing.costs (upstream OpenBSP's own rate table, see
-- supabase/seed.sql) only had WhatsApp rows for 'ar' (Argentina) -- an
-- upstream leftover, same Argentina-default pattern already found and
-- fixed once this project (P3-11c's phone placeholder example). This CRM
-- is India-only, so crm.estimate_campaign_cost (10-29zn_campaigns.sql)
-- looks up '<category>/in'.
--
-- Meta's own authoritative rate-card files (linked from
-- https://developers.facebook.com/docs/whatsapp/pricing, which itself
-- confirms per-message -- not per-conversation -- billing as of this
-- writing) were not reachable at build time. These figures are
-- third-party-sourced (multiple pricing trackers agreed closely, within a
-- few percent of each other, as of late 2026) and are APPROXIMATE --
-- flagged here, not assumed exact. Re-verify against the organization's
-- own WhatsApp Manager billing page before relying on this for real
-- budgeting, and replace this migration's values (never edit it in place
-- once merged -- add a new one) once Meta's own CSV is actually fetched.
--
-- Hand-written DML -- `db diff` emits schema DDL only, same documented
-- exception every prior data-only migration this project uses (e.g. the
-- original whatsapp/ar seed in supabase/seed.sql itself).
insert into billing.costs (provider, product, quantity, unit, pricing) values
  ('whatsapp', 'marketing/in',      1, 'templates', '{"price": 0.8631}'),
  ('whatsapp', 'utility/in',        1, 'templates', '{"price": 0.115}'),
  ('whatsapp', 'authentication/in', 1, 'templates', '{"price": 0.115}')
on conflict (provider, product, effective_at) do nothing;
