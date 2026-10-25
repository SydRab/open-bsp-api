-- Privileges for P3-04's new functions. db diff never emits grant/revoke
-- statements (see docs/upstream-edits.md / CLAUDE.md). The engine itself
-- (crm.z_run_qualification_engine and every internal function it calls)
-- is trigger/system-only, never called via RPC, so it only needs the
-- blanket service_role baseline re-applied -- that statement only covers
-- functions that exist when it runs, not future ones (the established
-- gotcha, re-confirmed every phase since P3-02). The scoring catalog's
-- own CRUD is member-callable, so it also needs an explicit `to
-- authenticated` grant.
revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

grant execute on function crm.set_qualification_question_score(uuid, text, text, int) to authenticated;
grant execute on function crm.delete_qualification_question_score(uuid) to authenticated;
grant execute on function crm.set_score_threshold(uuid, int, uuid, text) to authenticated;
grant execute on function crm.delete_score_threshold(uuid) to authenticated;
