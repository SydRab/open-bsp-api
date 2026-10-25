-- Privileges for P3-03's new functions. db diff never emits grant/revoke
-- statements (see docs/upstream-edits.md / CLAUDE.md). crm._ensure_lead,
-- crm.z_welcome_and_create_lead, and crm.z_apply_language_choice are
-- internal/trigger-only (never called via RPC), so they only need the
-- blanket service_role baseline from 10-40_grants.sql re-applied -- that
-- statement grants on all functions THAT EXIST AT THE TIME IT RUNS, not
-- future ones, so a brand-new function needs this re-run once.
-- crm.find_or_create_lead's signature is unchanged, so its existing
-- `to authenticated` grant (P3-02) still covers the refactored body.
revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;
