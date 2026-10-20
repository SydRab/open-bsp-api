-- Settings and teams triggers (P1-04): updated_at and audit entries
-- (setting.changed, setting.reset, team.created, team.renamed, team.deleted,
-- team.member_added, team.member_removed). See 10-21 for the audit design.

create trigger set_updated_at
before update
on crm.teams
for each row
execute function public.moddatetime('updated_at');

create trigger set_updated_at
before update
on crm.setting_values
for each row
execute function public.moddatetime('updated_at');

create function crm.audit_setting_values() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_row crm.setting_values := case when tg_op = 'DELETE' then old else new end;
  v_where jsonb := jsonb_strip_nulls(jsonb_build_object(
    'key', v_row.setting_key,
    'scope', v_row.scope,
    'team_id', v_row.team_id,
    'agent_id', v_row.agent_id
  ));
begin
  if tg_op = 'UPDATE' and new.value is not distinct from old.value then
    return null;
  end if;

  perform crm.write_audit(
    v_row.organization_id,
    case when tg_op = 'DELETE' then 'setting.reset' else 'setting.changed' end,
    'setting',
    v_row.setting_key,
    -- Values are never null (validated), so stripping only drops the side
    -- that does not exist: no before on a first change, no after on a reset.
    v_where || jsonb_strip_nulls(jsonb_build_object(
      'before', case when tg_op <> 'INSERT' then old.value end,
      'after', case when tg_op <> 'DELETE' then new.value end
    ))
  );

  return null;
end;
$$;

create trigger audit
after insert or update or delete
on crm.setting_values
for each row
execute function crm.audit_setting_values();

create function crm.audit_teams() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'INSERT' then
    perform crm.write_audit(
      new.organization_id, 'team.created', 'team', new.id::text,
      jsonb_build_object('name', new.name)
    );
  elsif tg_op = 'DELETE' then
    perform crm.write_audit(
      old.organization_id, 'team.deleted', 'team', old.id::text,
      jsonb_build_object('name', old.name)
    );
  elsif new.name is distinct from old.name then
    perform crm.write_audit(
      new.organization_id, 'team.renamed', 'team', new.id::text,
      jsonb_build_object(
        'before', jsonb_build_object('name', old.name),
        'after', jsonb_build_object('name', new.name)
      )
    );
  end if;

  return null;
end;
$$;

create trigger audit
after insert or update or delete
on crm.teams
for each row
execute function crm.audit_teams();

-- Rows that disappear with their team (a cascade) are covered by team.deleted.
create function crm.audit_team_members() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_row crm.team_members := case when tg_op = 'DELETE' then old else new end;
  v_team text := (select t.name from crm.teams t where t.id = v_row.team_id);
begin
  if v_team is null then
    return null;
  end if;

  perform crm.write_audit(
    v_row.organization_id,
    case when tg_op = 'DELETE' then 'team.member_removed' else 'team.member_added' end,
    'member',
    v_row.agent_id::text,
    jsonb_build_object('team', v_team, 'team_id', v_row.team_id)
  );

  return null;
end;
$$;

create trigger audit
after insert or delete
on crm.team_members
for each row
execute function crm.audit_team_members();
