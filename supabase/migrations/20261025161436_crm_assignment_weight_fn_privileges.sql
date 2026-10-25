-- crm.set_team_member_weight was added after the main P3-05 privileges
-- migration already ran, so it needs its own `to authenticated` grant --
-- db diff never emits these (see docs/upstream-edits.md / CLAUDE.md).
grant execute on function crm.set_team_member_weight(uuid, uuid, int) to authenticated;
