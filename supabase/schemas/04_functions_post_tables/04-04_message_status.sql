-- [crm] P2-08: a status event (sent/delivered/read/failed) for an
-- external_id we have no row for is an orphan, not a request to create
-- one -- mirrors the house convention _shared/whatsapp_templates.ts
-- already established for template status/quality webhooks ("no match is
-- a no-op, not an upsert"), generalized to messages. A plain `update ...
-- from (values ...)` only ever touches EXISTING rows by construction, so
-- this is naturally orphan-safe: unlike `upsert(rows, {onConflict:
-- "external_id"})`, which falls through to an INSERT (fabricating a
-- content-less, sender-less ghost message row) the moment no row matches.
-- Returns the external_ids that DID match, so the caller can log whichever
-- requested ids come back missing as orphans, instead of them vanishing
-- silently. service-role only -- see the companion privileges migration
-- this file's db diff needs (db diff never emits EXECUTE changes).
create function public.apply_message_statuses(p_statuses jsonb)
returns setof text
language sql
set search_path to ''
as $$
  update public.messages m
  set status = u.status_patch
  from (
    select
      (elem ->> 'external_id') as ext_id,
      (elem -> 'status') as status_patch
    from jsonb_array_elements(p_statuses) as elem
  ) u
  where m.external_id = u.ext_id
  returning m.external_id;
$$;

-- Supabase's own default privileges grant EXECUTE on every new public-schema
-- function to anon/authenticated directly (not via the `public` pseudo-role,
-- confirmed live: \df+ showed anon=X, authenticated=X individually) -- so
-- both need revoking by name, not just `from public`.
revoke execute on function public.apply_message_statuses(jsonb) from public, anon, authenticated;
grant execute on function public.apply_message_statuses(jsonb) to service_role;
