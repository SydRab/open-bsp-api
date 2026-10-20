-- Disclaimer versions (P1-07). Each organization keeps a short and a full
-- disclaimer per language (en, hi). Every edit adds a version; nothing is
-- overwritten, so a sent message can always be traced to the exact wording
-- it carried (crm.render_with_disclaimer returns the version it used).
--
-- Until an organization writes its own, the pack's text applies
-- (organization_pack_items: compliance / disclaimer_short, disclaimer_full).
--
--   short: WhatsApp messages and broadcasts; fits a template footer (60).
--   full:  public pages, receipts, the "DISCLAIMER" keyword reply.
--
-- Written only through crm.set_disclaimer (10-16).

create table crm.disclaimer_versions (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  kind text not null,
  locale text not null,
  version int not null,
  text text not null,
  -- The agent who wrote it (null for the platform).
  created_by uuid,
  created_at timestamp with time zone default now() not null
);

alter table only crm.disclaimer_versions
add constraint disclaimer_versions_pkey primary key (id);

alter table only crm.disclaimer_versions
add constraint disclaimer_versions_version_key
unique (organization_id, kind, locale, version);

alter table only crm.disclaimer_versions
add constraint disclaimer_versions_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.disclaimer_versions
add constraint disclaimer_versions_kind_check
check (kind in ('short', 'full'));

alter table only crm.disclaimer_versions
add constraint disclaimer_versions_locale_check
check (locale in ('en', 'hi'));

alter table only crm.disclaimer_versions
add constraint disclaimer_versions_version_check
check (version > 0);
