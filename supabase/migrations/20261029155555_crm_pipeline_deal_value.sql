alter table "crm"."leads" add column "deal_value" numeric;

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.set_lead_deal_value(p_lead_id uuid, p_value numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
begin
  select organization_id into v_org from crm.leads where id = p_lead_id;

  if v_org is null then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if p_value is not null and p_value < 0 then
    raise exception 'deal value cannot be negative' using errcode = '22023';
  end if;

  update crm.leads set deal_value = p_value where id = p_lead_id;

  perform crm.write_audit(
    v_org, 'lead.deal_value_changed', 'lead', p_lead_id::text,
    jsonb_build_object('deal_value', p_value)
  );
end;
$function$
;


