-- Audit log functions (P1-08). Table: 10-05. Triggers: 10-21.

-- The single writer. Works out who is acting from the request, so callers
-- only say what happened.
--
-- Called by the audit triggers, and by edge functions through the service
-- role for events the database cannot see (token connects, exports). Not
-- callable by members or API keys: they could forge entries.
--
-- Writes nothing while crm.purge_organizations runs, when a seeding step has
-- asked for quiet (crm.audit_suppress, set by crm.create_preset_roles), or
-- when the organization no longer exists (rows cascading from its deletion).
create function crm.write_audit(
  p_organization_id uuid,
  p_action text,
  p_target_type text default null,
  p_target_id text default null,
  p_details jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_headers json;
  v_api_key text;
  v_actor_type text;
  v_user_id uuid := auth.uid();
  v_agent_id uuid;
  v_api_key_id uuid;
begin
  if current_setting('crm.purging', true) = 'on'
    or current_setting('crm.audit_suppress', true) = 'on'
    or not exists (
      select 1 from public.organizations o where o.id = p_organization_id
    ) then
    return;
  end if;

  v_headers := nullif(current_setting('request.headers', true), '')::json;

  if v_user_id is not null then
    v_actor_type := 'user';
    select a.id into v_agent_id
    from public.agents a
    where a.organization_id = p_organization_id
      and a.user_id = v_user_id;
  else
    v_api_key := v_headers->>'api-key';

    if v_api_key is not null then
      -- Only the key's id is stored, never the key.
      select k.id into v_api_key_id
      from public.api_keys k
      where k.key = v_api_key;
    end if;

    if v_api_key_id is not null then
      v_actor_type := 'api_key';
    elsif auth.role() = 'service_role' then
      v_actor_type := 'service';
    else
      v_actor_type := 'system';
    end if;
  end if;

  insert into crm.audit_log (
    organization_id, actor_type, actor_user_id, actor_agent_id,
    actor_api_key_id, action, target_type, target_id, details, request_id
  ) values (
    p_organization_id, v_actor_type, v_user_id, v_agent_id,
    v_api_key_id, p_action, p_target_type, p_target_id,
    coalesce(p_details, '{}'::jsonb),
    left(coalesce(v_headers->>'x-request-id', v_headers->>'sb-request-id'), 100)
  );
end;
$$;

-- One page of an organization's audit log for the Activity page, newest
-- first, with the names the UI shows. Pages with p_before_id (the last id
-- of the previous page). Filters are optional:
--   p_area      the part before the dot, e.g. 'member', 'role';
--   p_actor     the acting member's agent id;
--   p_from/p_to a time window.
create function crm.get_audit_log(
  p_organization_id uuid,
  p_before_id bigint default null,
  p_limit int default 50,
  p_area text default null,
  p_actor uuid default null,
  p_from timestamp with time zone default null,
  p_to timestamp with time zone default null
) returns table (
  id bigint,
  created_at timestamp with time zone,
  actor_type text,
  actor_agent_id uuid,
  actor_name text,
  action text,
  target_type text,
  target_id text,
  target_name text,
  details jsonb
)
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(p_organization_id, 'audit.view');

  return query
  select
    l.id,
    l.created_at,
    l.actor_type,
    l.actor_agent_id,
    coalesce(actor.name, ak.name),
    l.action,
    l.target_type,
    l.target_id,
    coalesce(member.name, r.name),
    l.details
  from crm.audit_log l
  left join public.agents actor on actor.id = l.actor_agent_id
  left join public.api_keys ak on ak.id = l.actor_api_key_id
  left join public.agents member
    on l.target_type = 'member'
   and member.organization_id = l.organization_id
   and member.id::text = l.target_id
  left join crm.roles r
    on l.target_type = 'role'
   and r.organization_id = l.organization_id
   and r.id::text = l.target_id
  where l.organization_id = p_organization_id
    and (p_before_id is null or l.id < p_before_id)
    and (p_area is null or split_part(l.action, '.', 1) = p_area)
    and (p_actor is null or l.actor_agent_id = p_actor)
    and (p_from is null or l.created_at >= p_from)
    and (p_to is null or l.created_at < p_to)
  order by l.id desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

-- Append-only guard (trigger in 10-21). Deleting is allowed only while
-- crm.purge_organizations hard-deletes organizations after their grace
-- period; updating never is.
create function crm.before_change_on_audit_log() returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if tg_op = 'DELETE' and current_setting('crm.purging', true) = 'on' then
    return old;
  end if;

  raise exception 'the audit log is append-only'
    using errcode = '42501';
end;
$$;
