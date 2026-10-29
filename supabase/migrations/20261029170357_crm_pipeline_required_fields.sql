
  create table "crm"."lead_stage_required_fields" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "stage_id" uuid not null,
    "field_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."lead_stage_required_fields" enable row level security;

alter table "crm"."leads" add column "custom_fields" jsonb not null default '{}'::jsonb;

CREATE UNIQUE INDEX lead_stage_required_fields_pkey ON crm.lead_stage_required_fields USING btree (id);

CREATE UNIQUE INDEX lead_stage_required_fields_stage_id_field_id_key ON crm.lead_stage_required_fields USING btree (stage_id, field_id);

CREATE INDEX lead_stage_required_fields_stage_id_idx ON crm.lead_stage_required_fields USING btree (stage_id);

alter table "crm"."lead_stage_required_fields" add constraint "lead_stage_required_fields_pkey" PRIMARY KEY using index "lead_stage_required_fields_pkey";

alter table "crm"."lead_stage_required_fields" add constraint "lead_stage_required_fields_field_fkey" FOREIGN KEY (field_id) REFERENCES crm.organization_pack_items(id) ON DELETE CASCADE not valid;

alter table "crm"."lead_stage_required_fields" validate constraint "lead_stage_required_fields_field_fkey";

alter table "crm"."lead_stage_required_fields" add constraint "lead_stage_required_fields_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."lead_stage_required_fields" validate constraint "lead_stage_required_fields_organization_id_fkey";

alter table "crm"."lead_stage_required_fields" add constraint "lead_stage_required_fields_stage_fkey" FOREIGN KEY (organization_id, stage_id) REFERENCES crm.lead_stages(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."lead_stage_required_fields" validate constraint "lead_stage_required_fields_stage_fkey";

alter table "crm"."lead_stage_required_fields" add constraint "lead_stage_required_fields_stage_id_field_id_key" UNIQUE using index "lead_stage_required_fields_stage_id_field_id_key";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._set_lead_stage(p_lead_id uuid, p_organization_id uuid, p_stage_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_missing text;
begin
  if p_stage_id is not null and not exists (
    select 1 from crm.lead_stages where id = p_stage_id and organization_id = p_organization_id
  ) then
    raise exception 'stage not found' using errcode = '22023';
  end if;

  if p_stage_id is not null then
    select string_agg(d.value->'label'->>'en', ', ' order by d.sort_order)
    into v_missing
    from crm.lead_stage_required_fields rf
    join crm.organization_pack_items d on d.id = rf.field_id
    join crm.leads l on l.id = p_lead_id
    where rf.stage_id = p_stage_id
      and not coalesce((d.value->>'archived')::boolean, false)
      and not l.custom_fields ? d.item_key;
    if v_missing is not null then
      raise exception 'required for this stage: %', v_missing using errcode = '22023';
    end if;
  end if;

  update crm.leads set stage_id = p_stage_id where id = p_lead_id;

  perform crm.write_audit(
    p_organization_id, 'lead.stage_changed', 'lead', p_lead_id::text,
    jsonb_build_object('stage_id', p_stage_id)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.bulk_set_lead_stage(p_lead_ids uuid[], p_stage_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
  v_lead_id uuid;
begin
  if p_lead_ids is null or array_length(p_lead_ids, 1) is null then
    raise exception 'no leads given' using errcode = '22023';
  end if;

  select organization_id into v_org from crm.leads where id = p_lead_ids[1];
  if v_org is null then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if (select count(*) from crm.leads where id = any(p_lead_ids) and organization_id = v_org)
     <> array_length(p_lead_ids, 1) then
    raise exception 'one or more leads were not found in this organization'
      using errcode = '22023';
  end if;

  foreach v_lead_id in array p_lead_ids loop
    perform crm._set_lead_stage(v_lead_id, v_org, p_stage_id);
  end loop;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_lead_fields(p_lead_id uuid, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads;
  v_merged jsonb;
  v_missing text;
begin
  select * into v_lead from crm.leads l where l.id = p_lead_id;
  if not found then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;
  if not crm.has_permission(v_lead.organization_id, 'deals.edit') then
    raise exception 'permission deals.edit required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_values) is distinct from 'object' then
    raise exception 'values must be an object' using errcode = '22023';
  end if;

  v_merged := crm.clean_custom_fields(v_lead.custom_fields || p_values);

  select string_agg(d.value->'label'->>'en', ', ' order by d.sort_order)
  into v_missing
  from crm.organization_pack_items d
  where d.organization_id = v_lead.organization_id
    and d.kind = 'custom_field'
    and d.value->>'entity' = 'deal'
    and coalesce((d.value->>'required')::boolean, false)
    and not coalesce((d.value->>'archived')::boolean, false)
    and not v_merged ? d.item_key;
  if v_missing is not null then
    raise exception 'required: %', v_missing using errcode = '22023';
  end if;

  update crm.leads set custom_fields = v_merged
  where id = p_lead_id
  returning * into v_lead;
  if not found then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  return v_lead.custom_fields;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_stage_required_fields(p_stage_id uuid, p_field_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
begin
  select organization_id into v_org from crm.lead_stages where id = p_stage_id;
  if v_org is null then
    raise exception 'stage not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_org, 'organization.manage');

  if exists (
    select 1 from unnest(coalesce(p_field_ids, '{}'::uuid[])) f(id)
    where not exists (
      select 1 from crm.organization_pack_items d
      where d.id = f.id and d.organization_id = v_org
        and d.kind = 'custom_field' and d.value->>'entity' = 'deal'
    )
  ) then
    raise exception 'one or more fields were not found' using errcode = '22023';
  end if;

  delete from crm.lead_stage_required_fields where stage_id = p_stage_id;

  insert into crm.lead_stage_required_fields (organization_id, stage_id, field_id)
  select v_org, p_stage_id, f.id from unnest(coalesce(p_field_ids, '{}'::uuid[])) f(id);

  perform crm.write_audit(
    v_org, 'lead_stage.required_fields_changed', 'lead_stage', p_stage_id::text,
    jsonb_build_object('field_ids', to_jsonb(p_field_ids))
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
  perform crm._set_lead_stage(p_lead_id, v_org, p_stage_id);
end;
$function$
;

grant select on table "crm"."lead_stage_required_fields" to "anon";

grant select on table "crm"."lead_stage_required_fields" to "authenticated";

grant delete on table "crm"."lead_stage_required_fields" to "service_role";

grant insert on table "crm"."lead_stage_required_fields" to "service_role";

grant references on table "crm"."lead_stage_required_fields" to "service_role";

grant select on table "crm"."lead_stage_required_fields" to "service_role";

grant trigger on table "crm"."lead_stage_required_fields" to "service_role";

grant truncate on table "crm"."lead_stage_required_fields" to "service_role";

grant update on table "crm"."lead_stage_required_fields" to "service_role";


  create policy "members can read their orgs stage required fields"
  on "crm"."lead_stage_required_fields"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



