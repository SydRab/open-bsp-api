drop function if exists "crm"."set_contact_consent"(p_organization_id uuid, p_organization_address text, p_service public.service, p_address text, p_status text, p_source text);

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.record_import_attestation(p_organization_id uuid, p_row_count integer, p_marked_opted_in_count integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.set_contact_consent(p_organization_id uuid, p_organization_address text, p_service public.service, p_address text, p_status text, p_source text DEFAULT 'csv_import'::text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(p_organization_id, 'contacts.edit');

  perform crm.record_consent_event(
    p_organization_id, p_organization_address, p_service, p_address,
    p_status, p_source, null, p_note
  );
end;
$function$
;

-- db diff doesn't derive privilege changes for a brand-new function, and
-- set_contact_consent's old 6-arg signature was dropped and recreated as
-- a distinct 7-arg one above -- same known gap as every prior migration
-- this session that added or changed a function's signature. Match
-- 10-40_grants.sql's declared end state by hand.
revoke execute on function crm.record_import_attestation(uuid, int, int) from public;
grant execute on function crm.record_import_attestation(uuid, int, int) to authenticated;

revoke execute on function crm.set_contact_consent(uuid, text, public.service, text, text, text, text) from public;
grant execute on function crm.set_contact_consent(uuid, text, public.service, text, text, text, text) to authenticated;
