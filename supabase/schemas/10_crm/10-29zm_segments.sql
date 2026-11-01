-- [crm] P4-03: segments -- a saved filter over crm._filter_contact_rows
-- (10-17_custom_fields.sql), the base feature that function's own header
-- comment already named it for. `type` decides whether membership is
-- frozen at save/refresh time ('static', backed by crm.segment_members)
-- or re-evaluated live every time it's read ('dynamic', criteria only,
-- no membership table row ever written). `criteria` is always stored,
-- even for a static segment, so it can be refreshed later without the
-- admin re-building the filter from scratch.
create table crm.segments (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  name text not null,
  type text not null,
  criteria jsonb default '[]'::jsonb not null,
  -- Only meaningful for a static segment -- when crm.refresh_segment last
  -- (re)populated crm.segment_members. Null for a dynamic segment (there
  -- is nothing to refresh) and for a static one that hasn't been
  -- refreshed since creation yet... except creation always refreshes
  -- once, so in practice this is only ever null before that first run
  -- completes.
  refreshed_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

alter table only crm.segments add constraint segments_pkey primary key (id);

alter table only crm.segments
add constraint segments_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.segments
add constraint segments_type_check
check (type in ('static', 'dynamic'));

alter table only crm.segments
add constraint segments_name_check
check (length(trim(name)) > 0 and length(name) <= 100);

create index segments_organization_id_idx on crm.segments (organization_id);

-- A static segment's frozen membership. Nothing for a dynamic segment --
-- its membership is always re-evaluated live from crm.segments.criteria.
-- organization_id is denormalized (not derivable only via a join) --
-- every tenant-owned table carries its own, per CLAUDE.md, same
-- precedent crm.contact_tags/crm.conversation_tags already set.
create table crm.segment_members (
  organization_id uuid not null,
  segment_id uuid not null,
  contact_id uuid not null,
  added_at timestamp with time zone default now() not null
);

alter table only crm.segment_members
add constraint segment_members_pkey primary key (segment_id, contact_id);

alter table only crm.segment_members
add constraint segment_members_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only crm.segment_members
add constraint segment_members_segment_id_fkey
foreign key (segment_id) references crm.segments(id) on delete cascade;

alter table only crm.segment_members
add constraint segment_members_contact_id_fkey
foreign key (contact_id) references crm.contacts(id) on delete cascade;

create trigger set_updated_at
before update
on crm.segments
for each row
execute function public.moddatetime('updated_at');

-- CRUD, preview, and membership -----------------------------------------------------------

create function crm.create_segment(
  p_organization_id uuid,
  p_name text,
  p_type text,
  p_criteria jsonb default '[]'::jsonb
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

create function crm.update_segment(
  p_segment_id uuid,
  p_name text,
  p_criteria jsonb
) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

create function crm.delete_segment(p_segment_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- Re-evaluates a static segment's criteria right now and replaces its
-- membership snapshot. A no-op (not an error) for a dynamic segment --
-- it has no snapshot to refresh, since every read already re-evaluates
-- live.
create function crm.refresh_segment(p_segment_id uuid) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

-- The count preview: callable with any criteria BEFORE a segment is ever
-- saved (no segment_id -- the UI calls this live as the admin edits the
-- filter). opted_in_count resolves consent the same "one more internal
-- caller, no grant change" way crm.export_contacts (P3-11b) already does
-- for crm.get_consent_status (P2-05, service-role only by design) --
-- inlined as a LEFT JOIN LATERAL here rather than one call per contact,
-- since a segment can be thousands of rows.
create function crm.preview_segment_count(
  p_organization_id uuid,
  p_criteria jsonb default '[]'::jsonb
) returns table (total_count bigint, opted_in_count bigint)
language plpgsql
stable
security definer
set search_path to ''
as $$
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
$$;

-- A segment's current members, paginated -- live-evaluated for a dynamic
-- segment, read from the frozen snapshot for a static one.
create function crm.get_segment_contacts(
  p_segment_id uuid,
  p_limit int default 100,
  p_offset int default 0
) returns setof crm.contacts
language plpgsql
stable
security definer
set search_path to ''
as $$
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
$$;
