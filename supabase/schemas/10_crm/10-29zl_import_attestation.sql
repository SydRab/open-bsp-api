-- [crm] P4-01: a durable record of the CSV import wizard's attestation
-- checkbox ("I confirm this list was obtained lawfully...", P3-11c) --
-- today that checkbox is pure client-side React state, never persisted,
-- so nothing records who attested, when, or how many rows. One audit
-- entry per import RUN (not per row -- the attestation covers the whole
-- file, same as the checkbox itself gates the whole import), written by
-- the wizard once after its row loop finishes. No target_type/target_id:
-- an import run is not about one contact or lead, it is its own event.
create function crm.record_import_attestation(
  p_organization_id uuid,
  p_row_count int,
  p_marked_opted_in_count int
) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform crm.require_permission(p_organization_id, 'contacts.edit');

  perform crm.write_audit(
    p_organization_id, 'contacts.import_attested', null, null,
    jsonb_build_object(
      'row_count', p_row_count,
      'marked_opted_in_count', p_marked_opted_in_count
    )
  );
end;
$$;
