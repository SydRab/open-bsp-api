-- Feature flags and plan entitlements (P1-09). crm.features is the platform
-- catalog (today: the eleven modules also listed in the settings catalog,
-- 10-15/20261020220553); crm.tier_features maps a billing tier to the
-- features it includes; crm.organization_features holds per-tenant
-- overrides (a beta, a comp, a block), set by the platform only. Resolution
-- and the member-seat limit: 10-19, 10-25.
--
-- tier_id here is NOT a foreign key into billing.tiers: that catalog is
-- environment data (seeded locally in supabase/seed.sql; configured per
-- environment in staging/production, see 06-30's note on billing.
-- initialize_subscription), so a tier row is not guaranteed to exist when a
-- crm migration runs — confirmed by hand: a migration-time insert FK'd to
-- billing.tiers('free') fails, since 'free'/'starter' only exist once
-- seed.sql runs, which is after every migration. crm.tier_features works
-- with whatever tier ids billing.subscriptions actually carries ('free',
-- 'starter', 'pro' locally).

create table crm.features (
  key text not null,
  category text not null default 'modules',
  label text not null,
  description text,
  -- Platform emergency off switch: when true, the feature is unavailable to
  -- every organization regardless of plan or override.
  -- crm.set_feature_kill_switch (10-19).
  kill_switch boolean not null default false,
  sort_order int not null default 0,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.features
add constraint features_pkey primary key (key);

create table crm.tier_features (
  tier_id text not null,
  feature_key text not null,
  created_at timestamp with time zone default now() not null
);

alter table only crm.tier_features
add constraint tier_features_pkey primary key (tier_id, feature_key);

alter table only crm.tier_features
add constraint tier_features_feature_key_fkey
foreign key (feature_key) references crm.features(key) on delete cascade;

-- One active override per organization and feature; a new call to
-- crm.set_organization_feature replaces it rather than stacking a history.
create table crm.organization_features (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  feature_key text not null,
  enabled boolean not null,
  reason text,
  -- Null = no expiry; past this time the tier default applies again.
  expires_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.organization_features
add constraint organization_features_pkey primary key (id);

alter table only crm.organization_features
add constraint organization_features_organization_id_feature_key_key
unique (organization_id, feature_key);

alter table only crm.organization_features
add constraint organization_features_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.organization_features
add constraint organization_features_feature_key_fkey
foreign key (feature_key) references crm.features(key) on delete cascade;

create index organization_features_organization_id_idx
on crm.organization_features (organization_id);

create trigger set_updated_at
before update
on crm.features
for each row
execute function public.moddatetime('updated_at');

create trigger set_updated_at
before update
on crm.organization_features
for each row
execute function public.moddatetime('updated_at');
