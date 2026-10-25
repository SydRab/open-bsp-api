
  create table "crm"."lead_drop_reasons" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "key" text not null,
    "name" text not null,
    "is_preset" boolean not null default true,
    "sort_order" integer not null default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."lead_drop_reasons" enable row level security;


  create table "crm"."lead_qualities" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "key" text not null,
    "name" text not null,
    "is_preset" boolean not null default true,
    "sort_order" integer not null default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."lead_qualities" enable row level security;


  create table "crm"."lead_stages" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "key" text not null,
    "name" text not null,
    "is_preset" boolean not null default true,
    "sort_order" integer not null default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."lead_stages" enable row level security;


  create table "crm"."leads" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "contact_id" uuid not null,
    "source" text not null,
    "status" text not null default 'open'::text,
    "stage_id" uuid,
    "quality_id" uuid,
    "drop_reason_id" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."leads" enable row level security;


  create table "crm"."preset_lead_drop_reasons" (
    "key" text not null,
    "name" text not null,
    "sort_order" integer not null default 0
      );



  create table "crm"."preset_lead_qualities" (
    "key" text not null,
    "name" text not null,
    "sort_order" integer not null default 0
      );



  create table "crm"."preset_lead_stages" (
    "key" text not null,
    "name" text not null,
    "sort_order" integer not null default 0
      );


CREATE UNIQUE INDEX lead_drop_reasons_organization_id_id_key ON crm.lead_drop_reasons USING btree (organization_id, id);

CREATE UNIQUE INDEX lead_drop_reasons_organization_id_key_key ON crm.lead_drop_reasons USING btree (organization_id, key);

CREATE UNIQUE INDEX lead_drop_reasons_pkey ON crm.lead_drop_reasons USING btree (id);

CREATE UNIQUE INDEX lead_qualities_organization_id_id_key ON crm.lead_qualities USING btree (organization_id, id);

CREATE UNIQUE INDEX lead_qualities_organization_id_key_key ON crm.lead_qualities USING btree (organization_id, key);

CREATE UNIQUE INDEX lead_qualities_pkey ON crm.lead_qualities USING btree (id);

CREATE UNIQUE INDEX lead_stages_organization_id_id_key ON crm.lead_stages USING btree (organization_id, id);

CREATE UNIQUE INDEX lead_stages_organization_id_key_key ON crm.lead_stages USING btree (organization_id, key);

CREATE UNIQUE INDEX lead_stages_pkey ON crm.lead_stages USING btree (id);

CREATE UNIQUE INDEX leads_organization_id_contact_id_key ON crm.leads USING btree (organization_id, contact_id);

CREATE INDEX leads_organization_id_idx ON crm.leads USING btree (organization_id);

CREATE INDEX leads_organization_id_status_idx ON crm.leads USING btree (organization_id, status);

CREATE UNIQUE INDEX leads_pkey ON crm.leads USING btree (id);

CREATE UNIQUE INDEX preset_lead_drop_reasons_pkey ON crm.preset_lead_drop_reasons USING btree (key);

CREATE UNIQUE INDEX preset_lead_qualities_pkey ON crm.preset_lead_qualities USING btree (key);

CREATE UNIQUE INDEX preset_lead_stages_pkey ON crm.preset_lead_stages USING btree (key);

alter table "crm"."lead_drop_reasons" add constraint "lead_drop_reasons_pkey" PRIMARY KEY using index "lead_drop_reasons_pkey";

alter table "crm"."lead_qualities" add constraint "lead_qualities_pkey" PRIMARY KEY using index "lead_qualities_pkey";

alter table "crm"."lead_stages" add constraint "lead_stages_pkey" PRIMARY KEY using index "lead_stages_pkey";

alter table "crm"."leads" add constraint "leads_pkey" PRIMARY KEY using index "leads_pkey";

alter table "crm"."preset_lead_drop_reasons" add constraint "preset_lead_drop_reasons_pkey" PRIMARY KEY using index "preset_lead_drop_reasons_pkey";

alter table "crm"."preset_lead_qualities" add constraint "preset_lead_qualities_pkey" PRIMARY KEY using index "preset_lead_qualities_pkey";

alter table "crm"."preset_lead_stages" add constraint "preset_lead_stages_pkey" PRIMARY KEY using index "preset_lead_stages_pkey";

alter table "crm"."lead_drop_reasons" add constraint "lead_drop_reasons_name_check" CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 60))) not valid;

alter table "crm"."lead_drop_reasons" validate constraint "lead_drop_reasons_name_check";

alter table "crm"."lead_drop_reasons" add constraint "lead_drop_reasons_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."lead_drop_reasons" validate constraint "lead_drop_reasons_organization_id_fkey";

alter table "crm"."lead_drop_reasons" add constraint "lead_drop_reasons_organization_id_id_key" UNIQUE using index "lead_drop_reasons_organization_id_id_key";

alter table "crm"."lead_drop_reasons" add constraint "lead_drop_reasons_organization_id_key_key" UNIQUE using index "lead_drop_reasons_organization_id_key_key";

alter table "crm"."lead_qualities" add constraint "lead_qualities_name_check" CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 60))) not valid;

alter table "crm"."lead_qualities" validate constraint "lead_qualities_name_check";

alter table "crm"."lead_qualities" add constraint "lead_qualities_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."lead_qualities" validate constraint "lead_qualities_organization_id_fkey";

alter table "crm"."lead_qualities" add constraint "lead_qualities_organization_id_id_key" UNIQUE using index "lead_qualities_organization_id_id_key";

alter table "crm"."lead_qualities" add constraint "lead_qualities_organization_id_key_key" UNIQUE using index "lead_qualities_organization_id_key_key";

alter table "crm"."lead_stages" add constraint "lead_stages_name_check" CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 60))) not valid;

alter table "crm"."lead_stages" validate constraint "lead_stages_name_check";

alter table "crm"."lead_stages" add constraint "lead_stages_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."lead_stages" validate constraint "lead_stages_organization_id_fkey";

alter table "crm"."lead_stages" add constraint "lead_stages_organization_id_id_key" UNIQUE using index "lead_stages_organization_id_id_key";

alter table "crm"."lead_stages" add constraint "lead_stages_organization_id_key_key" UNIQUE using index "lead_stages_organization_id_key_key";

alter table "crm"."leads" add constraint "leads_contact_fkey" FOREIGN KEY (organization_id, contact_id) REFERENCES crm.contacts(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."leads" validate constraint "leads_contact_fkey";

alter table "crm"."leads" add constraint "leads_drop_reason_fkey" FOREIGN KEY (organization_id, drop_reason_id) REFERENCES crm.lead_drop_reasons(organization_id, id) not valid;

alter table "crm"."leads" validate constraint "leads_drop_reason_fkey";

alter table "crm"."leads" add constraint "leads_drop_reason_required_check" CHECK (((status = 'dropped'::text) = (drop_reason_id IS NOT NULL))) not valid;

alter table "crm"."leads" validate constraint "leads_drop_reason_required_check";

alter table "crm"."leads" add constraint "leads_organization_id_contact_id_key" UNIQUE using index "leads_organization_id_contact_id_key";

alter table "crm"."leads" add constraint "leads_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."leads" validate constraint "leads_organization_id_fkey";

alter table "crm"."leads" add constraint "leads_quality_fkey" FOREIGN KEY (organization_id, quality_id) REFERENCES crm.lead_qualities(organization_id, id) not valid;

alter table "crm"."leads" validate constraint "leads_quality_fkey";

alter table "crm"."leads" add constraint "leads_source_check" CHECK ((source = ANY (ARRAY['ctwa_ad'::text, 'ctwa_post'::text, 'organic'::text, 'manual'::text]))) not valid;

alter table "crm"."leads" validate constraint "leads_source_check";

alter table "crm"."leads" add constraint "leads_stage_fkey" FOREIGN KEY (organization_id, stage_id) REFERENCES crm.lead_stages(organization_id, id) not valid;

alter table "crm"."leads" validate constraint "leads_stage_fkey";

alter table "crm"."leads" add constraint "leads_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'qualified'::text, 'unqualified'::text, 'converted'::text, 'dropped'::text]))) not valid;

alter table "crm"."leads" validate constraint "leads_status_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.create_lead_drop_reason(p_organization_id uuid, p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_base text;
  v_key text;
  v_suffix int := 0;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  v_base := trim(both '_' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '_', 'g'));
  if v_base = '' then
    v_base := 'reason';
  end if;

  v_key := v_base;
  while exists (
    select 1 from crm.lead_drop_reasons
    where organization_id = p_organization_id and key = v_key
  ) loop
    v_suffix := v_suffix + 1;
    v_key := v_base || '_' || v_suffix;
  end loop;

  insert into crm.lead_drop_reasons (organization_id, key, name, is_preset, sort_order)
  values (
    p_organization_id, v_key, trim(p_name), false,
    coalesce(
      (select max(sort_order) + 1 from crm.lead_drop_reasons where organization_id = p_organization_id),
      0
    )
  )
  returning id into v_id;

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.create_lead_quality(p_organization_id uuid, p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_base text;
  v_key text;
  v_suffix int := 0;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  v_base := trim(both '_' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '_', 'g'));
  if v_base = '' then
    v_base := 'quality';
  end if;

  v_key := v_base;
  while exists (
    select 1 from crm.lead_qualities
    where organization_id = p_organization_id and key = v_key
  ) loop
    v_suffix := v_suffix + 1;
    v_key := v_base || '_' || v_suffix;
  end loop;

  insert into crm.lead_qualities (organization_id, key, name, is_preset, sort_order)
  values (
    p_organization_id, v_key, trim(p_name), false,
    coalesce(
      (select max(sort_order) + 1 from crm.lead_qualities where organization_id = p_organization_id),
      0
    )
  )
  returning id into v_id;

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.create_lead_stage(p_organization_id uuid, p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_base text;
  v_key text;
  v_suffix int := 0;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  v_base := trim(both '_' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '_', 'g'));
  if v_base = '' then
    v_base := 'stage';
  end if;

  v_key := v_base;
  while exists (
    select 1 from crm.lead_stages
    where organization_id = p_organization_id and key = v_key
  ) loop
    v_suffix := v_suffix + 1;
    v_key := v_base || '_' || v_suffix;
  end loop;

  insert into crm.lead_stages (organization_id, key, name, is_preset, sort_order)
  values (
    p_organization_id, v_key, trim(p_name), false,
    coalesce(
      (select max(sort_order) + 1 from crm.lead_stages where organization_id = p_organization_id),
      0
    )
  )
  returning id into v_id;

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.delete_lead_drop_reason(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select organization_id from crm.lead_drop_reasons where id = p_id),
    'organization.manage'
  );

  delete from crm.lead_drop_reasons where id = p_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.delete_lead_quality(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select organization_id from crm.lead_qualities where id = p_id),
    'organization.manage'
  );

  delete from crm.lead_qualities where id = p_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.delete_lead_stage(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select organization_id from crm.lead_stages where id = p_id),
    'organization.manage'
  );

  delete from crm.lead_stages where id = p_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.find_or_create_lead(p_organization_id uuid, p_contact_id uuid, p_source text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads;
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'deals.edit');

  select * into v_lead from crm.leads
  where organization_id = p_organization_id and contact_id = p_contact_id;

  if found then
    -- Reopen rule: dropped/unqualified can come back to open (a lead
    -- messaging again is still working the same pursuit). converted is
    -- terminal -- a repeat inquiry from an already-enrolled contact is a
    -- different scenario (upsell/renewal) this phase's strict
    -- one-lead-per-contact dedupe isn't designed for.
    if v_lead.status in ('dropped', 'unqualified') then
      update crm.leads
      set status = 'open', drop_reason_id = null
      where id = v_lead.id;

      perform crm.write_audit(
        p_organization_id, 'lead.reopened', 'lead', v_lead.id::text,
        jsonb_build_object('from_status', v_lead.status)
      );
    end if;

    return v_lead.id;
  end if;

  insert into crm.leads (organization_id, contact_id, source)
  values (p_organization_id, p_contact_id, p_source)
  returning id into v_id;

  perform crm.write_audit(
    p_organization_id, 'lead.created', 'lead', v_id::text,
    jsonb_build_object('source', p_source)
  );

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.seed_lead_catalogs(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into crm.lead_stages (organization_id, key, name, is_preset, sort_order)
  select p_organization_id, key, name, true, sort_order
  from crm.preset_lead_stages
  on conflict (organization_id, key) do nothing;

  insert into crm.lead_qualities (organization_id, key, name, is_preset, sort_order)
  select p_organization_id, key, name, true, sort_order
  from crm.preset_lead_qualities
  on conflict (organization_id, key) do nothing;

  insert into crm.lead_drop_reasons (organization_id, key, name, is_preset, sort_order)
  select p_organization_id, key, name, true, sort_order
  from crm.preset_lead_drop_reasons
  on conflict (organization_id, key) do nothing;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_lead_quality(p_lead_id uuid, p_quality_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
begin
  select organization_id into v_org from crm.leads where id = p_lead_id;

  if v_org is null then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if p_quality_id is not null and not exists (
    select 1 from crm.lead_qualities where id = p_quality_id and organization_id = v_org
  ) then
    raise exception 'quality not found' using errcode = '22023';
  end if;

  update crm.leads set quality_id = p_quality_id where id = p_lead_id;

  perform crm.write_audit(
    v_org, 'lead.quality_changed', 'lead', p_lead_id::text,
    jsonb_build_object('quality_id', p_quality_id)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_lead_stage(p_lead_id uuid, p_stage_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
begin
  select organization_id into v_org from crm.leads where id = p_lead_id;

  if v_org is null then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if p_stage_id is not null and not exists (
    select 1 from crm.lead_stages where id = p_stage_id and organization_id = v_org
  ) then
    raise exception 'stage not found' using errcode = '22023';
  end if;

  update crm.leads set stage_id = p_stage_id where id = p_lead_id;

  perform crm.write_audit(
    v_org, 'lead.stage_changed', 'lead', p_lead_id::text,
    jsonb_build_object('stage_id', p_stage_id)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_lead_status(p_lead_id uuid, p_status text, p_drop_reason_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads;
begin
  select * into v_lead from crm.leads where id = p_lead_id;

  if not found then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_lead.organization_id, 'deals.edit');

  if v_lead.status = 'converted' and p_status <> 'converted' then
    raise exception 'a converted lead cannot change status' using errcode = '22023';
  end if;

  if p_status = 'dropped' then
    if p_drop_reason_id is null then
      raise exception 'a drop reason is required' using errcode = '22023';
    end if;
    if not exists (
      select 1 from crm.lead_drop_reasons
      where id = p_drop_reason_id and organization_id = v_lead.organization_id
    ) then
      raise exception 'drop reason not found' using errcode = '22023';
    end if;
  end if;

  update crm.leads
  set
    status = p_status,
    drop_reason_id = case when p_status = 'dropped' then p_drop_reason_id else null end
  where id = p_lead_id;

  perform crm.write_audit(
    v_lead.organization_id, 'lead.status_changed', 'lead', p_lead_id::text,
    jsonb_build_object('from_status', v_lead.status, 'to_status', p_status)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.update_lead_drop_reason(p_id uuid, p_name text, p_sort_order integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select organization_id from crm.lead_drop_reasons where id = p_id),
    'organization.manage'
  );

  update crm.lead_drop_reasons
  set name = trim(p_name), sort_order = p_sort_order
  where id = p_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.update_lead_quality(p_id uuid, p_name text, p_sort_order integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select organization_id from crm.lead_qualities where id = p_id),
    'organization.manage'
  );

  update crm.lead_qualities
  set name = trim(p_name), sort_order = p_sort_order
  where id = p_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.update_lead_stage(p_id uuid, p_name text, p_sort_order integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select organization_id from crm.lead_stages where id = p_id),
    'organization.manage'
  );

  update crm.lead_stages
  set name = trim(p_name), sort_order = p_sort_order
  where id = p_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.after_insert_on_organizations()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into crm.organization_profiles (organization_id, slug)
  values (new.id, crm.generate_slug(new.name));

  perform crm.create_preset_roles(new.id);
  perform crm.apply_default_pack(new.id);
  -- [crm] P3-02
  perform crm.seed_lead_catalogs(new.id);

  return null;
end;
$function$
;

grant select on table "crm"."lead_drop_reasons" to "anon";

grant select on table "crm"."lead_drop_reasons" to "authenticated";

grant delete on table "crm"."lead_drop_reasons" to "service_role";

grant insert on table "crm"."lead_drop_reasons" to "service_role";

grant references on table "crm"."lead_drop_reasons" to "service_role";

grant select on table "crm"."lead_drop_reasons" to "service_role";

grant trigger on table "crm"."lead_drop_reasons" to "service_role";

grant truncate on table "crm"."lead_drop_reasons" to "service_role";

grant update on table "crm"."lead_drop_reasons" to "service_role";

grant select on table "crm"."lead_qualities" to "anon";

grant select on table "crm"."lead_qualities" to "authenticated";

grant delete on table "crm"."lead_qualities" to "service_role";

grant insert on table "crm"."lead_qualities" to "service_role";

grant references on table "crm"."lead_qualities" to "service_role";

grant select on table "crm"."lead_qualities" to "service_role";

grant trigger on table "crm"."lead_qualities" to "service_role";

grant truncate on table "crm"."lead_qualities" to "service_role";

grant update on table "crm"."lead_qualities" to "service_role";

grant select on table "crm"."lead_stages" to "anon";

grant select on table "crm"."lead_stages" to "authenticated";

grant delete on table "crm"."lead_stages" to "service_role";

grant insert on table "crm"."lead_stages" to "service_role";

grant references on table "crm"."lead_stages" to "service_role";

grant select on table "crm"."lead_stages" to "service_role";

grant trigger on table "crm"."lead_stages" to "service_role";

grant truncate on table "crm"."lead_stages" to "service_role";

grant update on table "crm"."lead_stages" to "service_role";

grant select on table "crm"."leads" to "anon";

grant select on table "crm"."leads" to "authenticated";

grant delete on table "crm"."leads" to "service_role";

grant insert on table "crm"."leads" to "service_role";

grant references on table "crm"."leads" to "service_role";

grant select on table "crm"."leads" to "service_role";

grant trigger on table "crm"."leads" to "service_role";

grant truncate on table "crm"."leads" to "service_role";

grant update on table "crm"."leads" to "service_role";

grant select on table "crm"."preset_lead_drop_reasons" to "anon";

grant select on table "crm"."preset_lead_drop_reasons" to "authenticated";

grant delete on table "crm"."preset_lead_drop_reasons" to "service_role";

grant insert on table "crm"."preset_lead_drop_reasons" to "service_role";

grant references on table "crm"."preset_lead_drop_reasons" to "service_role";

grant select on table "crm"."preset_lead_drop_reasons" to "service_role";

grant trigger on table "crm"."preset_lead_drop_reasons" to "service_role";

grant truncate on table "crm"."preset_lead_drop_reasons" to "service_role";

grant update on table "crm"."preset_lead_drop_reasons" to "service_role";

grant select on table "crm"."preset_lead_qualities" to "anon";

grant select on table "crm"."preset_lead_qualities" to "authenticated";

grant delete on table "crm"."preset_lead_qualities" to "service_role";

grant insert on table "crm"."preset_lead_qualities" to "service_role";

grant references on table "crm"."preset_lead_qualities" to "service_role";

grant select on table "crm"."preset_lead_qualities" to "service_role";

grant trigger on table "crm"."preset_lead_qualities" to "service_role";

grant truncate on table "crm"."preset_lead_qualities" to "service_role";

grant update on table "crm"."preset_lead_qualities" to "service_role";

grant select on table "crm"."preset_lead_stages" to "anon";

grant select on table "crm"."preset_lead_stages" to "authenticated";

grant delete on table "crm"."preset_lead_stages" to "service_role";

grant insert on table "crm"."preset_lead_stages" to "service_role";

grant references on table "crm"."preset_lead_stages" to "service_role";

grant select on table "crm"."preset_lead_stages" to "service_role";

grant trigger on table "crm"."preset_lead_stages" to "service_role";

grant truncate on table "crm"."preset_lead_stages" to "service_role";

grant update on table "crm"."preset_lead_stages" to "service_role";


  create policy "members can read their orgs lead drop reasons"
  on "crm"."lead_drop_reasons"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "members can read their orgs lead qualities"
  on "crm"."lead_qualities"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "members can read their orgs lead stages"
  on "crm"."lead_stages"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "members can read their orgs leads"
  on "crm"."leads"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.lead_drop_reasons FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.lead_qualities FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.lead_stages FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');


