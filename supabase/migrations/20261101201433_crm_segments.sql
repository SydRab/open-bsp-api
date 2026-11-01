
  create table "crm"."segment_members" (
    "organization_id" uuid not null,
    "segment_id" uuid not null,
    "contact_id" uuid not null,
    "added_at" timestamp with time zone not null default now()
      );


alter table "crm"."segment_members" enable row level security;


  create table "crm"."segments" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "name" text not null,
    "type" text not null,
    "criteria" jsonb not null default '[]'::jsonb,
    "refreshed_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."segments" enable row level security;

CREATE UNIQUE INDEX segment_members_pkey ON crm.segment_members USING btree (segment_id, contact_id);

CREATE INDEX segments_organization_id_idx ON crm.segments USING btree (organization_id);

CREATE UNIQUE INDEX segments_pkey ON crm.segments USING btree (id);

alter table "crm"."segment_members" add constraint "segment_members_pkey" PRIMARY KEY using index "segment_members_pkey";

alter table "crm"."segments" add constraint "segments_pkey" PRIMARY KEY using index "segments_pkey";

alter table "crm"."segment_members" add constraint "segment_members_contact_id_fkey" FOREIGN KEY (contact_id) REFERENCES crm.contacts(id) ON DELETE CASCADE not valid;

alter table "crm"."segment_members" validate constraint "segment_members_contact_id_fkey";

alter table "crm"."segment_members" add constraint "segment_members_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."segment_members" validate constraint "segment_members_organization_id_fkey";

alter table "crm"."segment_members" add constraint "segment_members_segment_id_fkey" FOREIGN KEY (segment_id) REFERENCES crm.segments(id) ON DELETE CASCADE not valid;

alter table "crm"."segment_members" validate constraint "segment_members_segment_id_fkey";

alter table "crm"."segments" add constraint "segments_name_check" CHECK (((length(TRIM(BOTH FROM name)) > 0) AND (length(name) <= 100))) not valid;

alter table "crm"."segments" validate constraint "segments_name_check";

alter table "crm"."segments" add constraint "segments_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."segments" validate constraint "segments_organization_id_fkey";

alter table "crm"."segments" add constraint "segments_type_check" CHECK ((type = ANY (ARRAY['static'::text, 'dynamic'::text]))) not valid;

alter table "crm"."segments" validate constraint "segments_type_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._filter_contact_rows(p_organization_id uuid, p_conditions jsonb)
 RETURNS SETOF crm.contacts
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_condition jsonb;
  v_field text;
  v_op text;
  v_equal jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(p_conditions) is distinct from 'array' then
    raise exception 'conditions must be a list' using errcode = '22023';
  end if;

  for v_condition in select * from jsonb_array_elements(p_conditions) loop
    v_field := v_condition->>'field';
    v_op := v_condition->>'op';

    if v_field = 'tag' then
      if v_op not in ('has', 'not_has') then
        raise exception 'unknown filter operator % for field tag', v_op using errcode = '22023';
      end if;
    elsif v_field = 'stage' then
      if v_op not in ('eq', 'neq', 'is_empty', 'is_not_empty') then
        raise exception 'unknown filter operator % for field stage', v_op using errcode = '22023';
      end if;
    elsif v_field = 'last_contact_days' then
      if v_op not in ('lte', 'gte', 'is_empty') then
        raise exception 'unknown filter operator % for field last_contact_days', v_op
          using errcode = '22023';
      end if;
    else
      if not exists (
        select 1 from crm.organization_pack_items i
        where i.organization_id = p_organization_id
          and i.kind = 'custom_field'
          and i.item_key = v_field
          and i.value->>'entity' = 'contact'
      ) then
        raise exception 'unknown field %', v_field using errcode = '22023';
      end if;
      if v_op not in (
        'eq', 'neq', 'in', 'contains', 'gt', 'gte', 'lt', 'lte', 'is_empty', 'is_not_empty'
      ) then
        raise exception 'unknown filter operator %', v_op using errcode = '22023';
      end if;
      if v_op = 'eq' then
        v_equal := v_equal || jsonb_build_object(v_field, v_condition->'value');
      end if;
    end if;
  end loop;

  return query
  select c.*
  from crm.contacts c
  left join crm.leads l
    on l.organization_id = p_organization_id and l.contact_id = c.id
  left join lateral (
    select max(conv.last_inbound_at) as last_inbound_at
    from crm.contact_addresses ca
    join public.conversations conv
      on conv.organization_id = ca.organization_id
     and conv.service = ca.service
     and conv.address = ca.address
    where ca.organization_id = p_organization_id and ca.contact_id = c.id
  ) recency on true
  where c.organization_id = p_organization_id
    -- Equality custom-field conditions use the GIN index.
    and c.custom_fields @> v_equal
    and not exists (
      select 1 from jsonb_array_elements(p_conditions) cond
      where cond->>'field' not in ('tag', 'stage', 'last_contact_days')
        and not crm.custom_field_matches(c.custom_fields, cond)
    )
    and not exists (
      select 1 from jsonb_array_elements(p_conditions) cond
      where cond->>'field' = 'tag'
        and (
          (
            cond->>'op' = 'has' and not exists (
              select 1 from crm.contact_tags ct
              where ct.contact_id = c.id and ct.tag_id = (cond->>'value')::uuid
            )
          )
          or (
            cond->>'op' = 'not_has' and exists (
              select 1 from crm.contact_tags ct
              where ct.contact_id = c.id and ct.tag_id = (cond->>'value')::uuid
            )
          )
        )
    )
    and not exists (
      select 1 from jsonb_array_elements(p_conditions) cond
      where cond->>'field' = 'stage'
        and (
          (cond->>'op' = 'eq' and l.stage_id is distinct from (cond->>'value')::uuid)
          or (cond->>'op' = 'neq' and l.stage_id = (cond->>'value')::uuid)
          or (cond->>'op' = 'is_empty' and l.stage_id is not null)
          or (cond->>'op' = 'is_not_empty' and l.stage_id is null)
        )
    )
    and not exists (
      select 1 from jsonb_array_elements(p_conditions) cond
      where cond->>'field' = 'last_contact_days'
        and (
          (
            cond->>'op' = 'lte' and (
              recency.last_inbound_at is null
              or recency.last_inbound_at < now() - ((cond->>'value')::int || ' days')::interval
            )
          )
          or (
            cond->>'op' = 'gte' and (
              recency.last_inbound_at is null
              or recency.last_inbound_at > now() - ((cond->>'value')::int || ' days')::interval
            )
          )
          or (cond->>'op' = 'is_empty' and recency.last_inbound_at is not null)
        )
    );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.create_segment(p_organization_id uuid, p_name text, p_type text, p_criteria jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'broadcasts.create');

  if p_type not in ('static', 'dynamic') then
    raise exception 'type must be static or dynamic' using errcode = '22023';
  end if;

  -- Validates the criteria (crm._filter_contact_rows raises on an unknown
  -- field/op) before a row is ever written.
  perform 1 from crm._filter_contact_rows(p_organization_id, p_criteria) limit 1;

  insert into crm.segments (organization_id, name, type, criteria)
  values (p_organization_id, trim(p_name), p_type, p_criteria)
  returning id into v_id;

  if p_type = 'static' then
    perform crm.refresh_segment(v_id);
  end if;

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.delete_segment(p_segment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_organization_id uuid;
begin
  select organization_id into v_organization_id from crm.segments where id = p_segment_id;
  if v_organization_id is null then
    raise exception 'segment not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_organization_id, 'broadcasts.create');

  delete from crm.segments where id = p_segment_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.get_segment_contacts(p_segment_id uuid, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS SETOF crm.contacts
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_segment crm.segments;
begin
  select * into v_segment from crm.segments where id = p_segment_id;
  if not found then
    raise exception 'segment not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_segment.organization_id, 'broadcasts.create');

  if v_segment.type = 'dynamic' then
    return query
    select * from crm._filter_contact_rows(v_segment.organization_id, v_segment.criteria)
    order by created_at desc, id
    limit least(greatest(coalesce(p_limit, 100), 1), 1000)
    offset greatest(coalesce(p_offset, 0), 0);
  else
    return query
    select c.*
    from crm.segment_members sm
    join crm.contacts c on c.id = sm.contact_id
    where sm.segment_id = p_segment_id
    order by sm.added_at desc, c.id
    limit least(greatest(coalesce(p_limit, 100), 1), 1000)
    offset greatest(coalesce(p_offset, 0), 0);
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.preview_segment_count(p_organization_id uuid, p_criteria jsonb DEFAULT '[]'::jsonb)
 RETURNS TABLE(total_count bigint, opted_in_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(p_organization_id, 'broadcasts.create');

  return query
  select
    count(*),
    count(*) filter (where consent.status = 'opted_in')
  from crm._filter_contact_rows(p_organization_id, p_criteria) c
  left join lateral (
    select ca2.service, ca2.address
    from crm.contact_addresses ca2
    where ca2.contact_id = c.id and ca2.organization_id = p_organization_id
    order by ca2.created_at desc
    limit 1
  ) ca on true
  left join lateral (
    select conv2.organization_address
    from public.conversations conv2
    where conv2.organization_id = p_organization_id
      and conv2.service = ca.service and conv2.address = ca.address
    order by conv2.last_inbound_at desc nulls last
    limit 1
  ) conv on true
  left join lateral (
    select cc.status
    from crm.contacts_consent cc
    where cc.organization_id = p_organization_id
      and cc.organization_address = conv.organization_address
      and cc.service = ca.service and cc.address = ca.address
    order by cc.seq desc
    limit 1
  ) consent on true;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.refresh_segment(p_segment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_segment crm.segments;
begin
  select * into v_segment from crm.segments where id = p_segment_id;
  if not found then
    raise exception 'segment not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_segment.organization_id, 'broadcasts.create');

  if v_segment.type <> 'static' then
    return;
  end if;

  delete from crm.segment_members where segment_id = p_segment_id;

  insert into crm.segment_members (organization_id, segment_id, contact_id)
  select v_segment.organization_id, p_segment_id, c.id
  from crm._filter_contact_rows(v_segment.organization_id, v_segment.criteria) c;

  update crm.segments set refreshed_at = now() where id = p_segment_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.update_segment(p_segment_id uuid, p_name text, p_criteria jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_segment crm.segments;
begin
  select * into v_segment from crm.segments where id = p_segment_id;
  if not found then
    raise exception 'segment not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_segment.organization_id, 'broadcasts.create');
  perform 1 from crm._filter_contact_rows(v_segment.organization_id, p_criteria) limit 1;

  update crm.segments
  set name = trim(p_name), criteria = p_criteria
  where id = p_segment_id;

  -- A static segment's old membership was built from the old criteria --
  -- never left stale once the criteria it was built from has changed.
  if v_segment.type = 'static' then
    perform crm.refresh_segment(p_segment_id);
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.filter_contacts(p_organization_id uuid, p_conditions jsonb DEFAULT '[]'::jsonb, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS SETOF crm.contacts
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(p_organization_id, 'broadcasts.create');

  return query
  select * from crm._filter_contact_rows(p_organization_id, p_conditions)
  order by created_at desc, id
  limit least(greatest(coalesce(p_limit, 100), 1), 1000)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$function$
;

grant select on table "crm"."segment_members" to "anon";

grant select on table "crm"."segment_members" to "authenticated";

grant delete on table "crm"."segment_members" to "service_role";

grant insert on table "crm"."segment_members" to "service_role";

grant references on table "crm"."segment_members" to "service_role";

grant select on table "crm"."segment_members" to "service_role";

grant trigger on table "crm"."segment_members" to "service_role";

grant truncate on table "crm"."segment_members" to "service_role";

grant update on table "crm"."segment_members" to "service_role";

grant select on table "crm"."segments" to "anon";

grant select on table "crm"."segments" to "authenticated";

grant delete on table "crm"."segments" to "service_role";

grant insert on table "crm"."segments" to "service_role";

grant references on table "crm"."segments" to "service_role";

grant select on table "crm"."segments" to "service_role";

grant trigger on table "crm"."segments" to "service_role";

grant truncate on table "crm"."segments" to "service_role";

grant update on table "crm"."segments" to "service_role";


  create policy "members can read their orgs segment members"
  on "crm"."segment_members"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "members can read their orgs segments"
  on "crm"."segments"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.segments FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

-- db diff doesn't derive privilege changes for a brand-new function --
-- same known gap as every prior migration this session that added one.
-- crm.filter_contacts itself needed no new grant here (CREATE OR REPLACE
-- with an unchanged signature preserves its existing grant to anon,
-- authenticated, confirmed by this migration having no DROP FUNCTION for
-- it). _filter_contact_rows is internal (never called directly over
-- RPC) -- service_role only, matching the P3-12 precedent for an
-- internal helper a security definer function calls.
revoke execute on function crm._filter_contact_rows(uuid, jsonb) from public;
grant execute on function crm._filter_contact_rows(uuid, jsonb) to service_role;

revoke execute on function crm.create_segment(uuid, text, text, jsonb) from public;
grant execute on function crm.create_segment(uuid, text, text, jsonb) to authenticated;

revoke execute on function crm.update_segment(uuid, text, jsonb) from public;
grant execute on function crm.update_segment(uuid, text, jsonb) to authenticated;

revoke execute on function crm.delete_segment(uuid) from public;
grant execute on function crm.delete_segment(uuid) to authenticated;

revoke execute on function crm.refresh_segment(uuid) from public;
grant execute on function crm.refresh_segment(uuid) to authenticated;

revoke execute on function crm.preview_segment_count(uuid, jsonb) from public;
grant execute on function crm.preview_segment_count(uuid, jsonb) to authenticated;

revoke execute on function crm.get_segment_contacts(uuid, int, int) from public;
grant execute on function crm.get_segment_contacts(uuid, int, int) to authenticated;


