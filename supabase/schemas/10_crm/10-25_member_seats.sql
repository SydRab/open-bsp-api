-- Member seat limits (P1-09). Active human members (user_id set, not
-- deactivated) count against the organization's tier as the billing
-- 'members' product — a gauge, the same shape as 'organizations_addresses'
-- (06-30_functions.sql, billing.update_account_usage), which this mirrors.
--
-- public.agents never really gets a DELETE in normal operation
-- (public.mark_agent_deleted converts one into a mark, 02-03), so INSERT and
-- UPDATE OF deleted_at are the real paths; DELETE only reaches here when the
-- whole organization is cascading away, with nothing left to credit back.
create function crm.track_member_usage() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  _org_id uuid := coalesce(new.organization_id, old.organization_id);
  _old int := 0;
  _new int := 0;
begin
  if tg_op <> 'INSERT' then
    _old := (old.user_id is not null and old.deleted_at is null)::int;
  end if;

  if tg_op <> 'DELETE' then
    _new := (new.user_id is not null and new.deleted_at is null)::int;
  end if;

  if _new = _old then
    return null;
  end if;

  -- Cascade from an organization delete: its billing rows are going too.
  if not exists (select 1 from public.organizations where id = _org_id) then
    return null;
  end if;

  -- Only a brand-new active member is checked against the cap. Revival
  -- (crm.invite_member already gives the inviting admin an early, friendlier
  -- check, 10-12) goes through the same INSERT-or-UPDATE-of-deleted_at path,
  -- so a reinstated member is checked too — unlike a reconnecting WhatsApp
  -- account, this is always a deliberate action with a human to tell.
  if _new > _old then
    perform billing.check_limit(_org_id, 'members');
  end if;

  perform billing.update_usage(_org_id, 'members', _new - _old);
  return null;
end;
$$;

create trigger crm_track_member_usage
after insert or update of deleted_at or delete
on public.agents
for each row
execute function crm.track_member_usage();
