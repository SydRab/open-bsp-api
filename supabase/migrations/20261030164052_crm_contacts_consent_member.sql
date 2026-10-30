alter table "crm"."contacts_consent" drop constraint "contacts_consent_source_check";

alter table "crm"."contacts_consent" add constraint "contacts_consent_source_check" CHECK ((source = ANY (ARRAY['keyword'::text, 'admin'::text, 'signup_default'::text, 'api'::text, 'csv_import'::text]))) not valid;

alter table "crm"."contacts_consent" validate constraint "contacts_consent_source_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.set_contact_consent(p_organization_id uuid, p_organization_address text, p_service public.service, p_address text, p_status text, p_source text DEFAULT 'csv_import'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(p_organization_id, 'contacts.edit');

  perform crm.record_consent_event(
    p_organization_id, p_organization_address, p_service, p_address,
    p_status, p_source
  );
end;
$function$
;

-- db diff cannot derive privilege changes for a brand-new function (the
-- same gap already present, unnoticed, on export_contacts/set_contact_tag/
-- report_status_funnel from earlier P3 migrations -- each still enforces
-- its own permission check internally, so this is a discoverability/
-- defense-in-depth gap, not a tenant-isolation one, but still worth
-- closing for anything new): CREATE FUNCTION defaults to PUBLIC execute,
-- so without this it would stay reachable at /rest/v1/rpc for anon. Match
-- 10-40_grants.sql's declared end state by hand.
revoke execute on function crm.set_contact_consent(uuid, text, public.service, text, text, text) from public;
grant execute on function crm.set_contact_consent(uuid, text, public.service, text, text, text) to authenticated;

