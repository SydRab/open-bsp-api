-- Lead pipeline catalog (P3-02): stages, qualities, and drop reasons are
-- dynamic, tenant-scoped, and admin-editable -- never hardcoded enums --
-- same shape as the permission/preset-role catalog (10-01): a platform
-- default here, copied into each new org (crm.seed_lead_catalogs,
-- 10-29n_leads_functions.sql) the same way crm.create_preset_roles copies
-- crm.preset_roles. Not tenant-owned -- one copy for the platform.
--
-- Call-outcome statuses (Connected/RNR/NATC/...) are a deliberate scope cut:
-- no task names call logging yet, so there is nothing to attach that
-- catalog to. Add it alongside whichever task does, mirroring this exact
-- shape.
create table crm.preset_lead_stages (
  key text not null,
  name text not null,
  sort_order int not null default 0
);

alter table only crm.preset_lead_stages
add constraint preset_lead_stages_pkey primary key (key);

create table crm.preset_lead_qualities (
  key text not null,
  name text not null,
  sort_order int not null default 0
);

alter table only crm.preset_lead_qualities
add constraint preset_lead_qualities_pkey primary key (key);

create table crm.preset_lead_drop_reasons (
  key text not null,
  name text not null,
  sort_order int not null default 0
);

alter table only crm.preset_lead_drop_reasons
add constraint preset_lead_drop_reasons_pkey primary key (key);
