-- The feature catalog, tier entitlements, and billing's Pro tier (P1-09).
-- Data only; the tables are in schemas/10_crm/10-18_feature_flags.sql.
--
-- Today's features are exactly the eleven modules from the settings catalog
-- (20261020220553_crm_settings_catalog.sql) — Rules & modules decides
-- whether an organization has turned a module on; this decides whether its
-- plan lets it. Labels match that catalog's.
--
-- Tier mapping approved 2026-10-21: Free = the always-on basics; Starter
-- adds the messaging and operations modules; the new Pro tier (billing.tiers,
-- level 2, no price yet — pricing is a business decision, not this
-- migration's) adds AI and news. crm.tier_features has no foreign key to
-- billing.tiers (see 10-18's note), so this insert does not depend on
-- 'free'/'starter' already existing.

insert into crm.features (key, label, sort_order) values
  ('inbox', 'Inbox', 10),
  ('contacts', 'Contacts', 20),
  ('pipeline', 'Pipeline', 30),
  ('broadcasts', 'Broadcasts', 40),
  ('sequences', 'Sequences', 50),
  ('webinars', 'Webinars', 60),
  ('payments', 'Payments', 70),
  ('classroom', 'Classroom', 80),
  ('telegram', 'Telegram', 90),
  ('ai_agents', 'AI agents', 100),
  ('news_digest', 'News digest', 110);

insert into billing.tiers (id, name, level) values
  ('pro', 'Pro', 2);

-- A gauge product (billing.products.kind), like organizations_addresses:
-- counts while true, not cumulatively. crm.track_member_usage (10-25) keeps
-- it in step with active human members (public.agents, user_id set,
-- deleted_at null). Tier caps for 'free' and 'starter' are in
-- supabase/seed.sql next to their sibling caps, for the same reason
-- crm.tier_features avoids a foreign key to billing.tiers — those tier rows
-- do not exist yet when this migration runs. Pro gets no row: no row means
-- unlimited (billing.tiers_products' own convention).
insert into billing.products (id, name, unit, kind) values
  ('members', 'Members', 'count', 'gauge');

insert into crm.tier_features (tier_id, feature_key)
select 'free', k from unnest(array['inbox', 'contacts', 'pipeline']) k
union all
select 'starter', k from unnest(array[
  'inbox', 'contacts', 'pipeline',
  'broadcasts', 'sequences', 'webinars', 'payments', 'classroom', 'telegram'
]) k
union all
select 'pro', key from crm.features;
