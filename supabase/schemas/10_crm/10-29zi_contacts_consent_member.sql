-- [crm] P3-11c: a member-facing wrapper around crm.record_consent_event
-- (P2-05, 10-29d -- service-role only by that file's own header, "no
-- member-facing UI exists yet"). CSV import is that UI's first caller: an
-- admin importing a contact list from elsewhere is recording consent on
-- the org's behalf, the same kind of event the inbound STOP handler and
-- the dispatcher already record for themselves, just through a different
-- door. Gated on `contacts.edit`, the same bar crm.set_contact_tag and
-- crm.set_contact_fields already use for touching a contact's own
-- metadata. p_source defaults to 'csv_import' (today's only caller) but
-- stays a parameter so a future manual "mark as opted in" action can reuse
-- this with p_source = 'admin' instead of writing its own wrapper.
--
-- [crm] P4-01: p_note added -- the "proof text/URL/form id" the consent
-- ledger roadmap line asks for. No new column: crm.contacts_consent's own
-- `note` already existed (P2-05) and sat unused by every caller until now
-- -- one free-text field covers proof text, a URL, or a form id equally
-- well, so a dedicated column per format would be three ways to store the
-- same kind of value. The manual "record consent" action (P4-01, ui/ui)
-- is this parameter's first real caller.
create function crm.set_contact_consent(
  p_organization_id uuid,
  p_organization_address text,
  p_service public.service,
  p_address text,
  p_status text,
  p_source text default 'csv_import',
  p_note text default null
) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(p_organization_id, 'contacts.edit');

  perform crm.record_consent_event(
    p_organization_id, p_organization_address, p_service, p_address,
    p_status, p_source, null, p_note
  );
end;
$$;
