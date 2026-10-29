set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.set_lead_fields(p_lead_id uuid, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads;
  v_merged jsonb;
  v_missing text;
begin
  select * into v_lead from crm.leads l where l.id = p_lead_id;
  if not found then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;
  if not crm.has_permission(v_lead.organization_id, 'deals.edit') then
    raise exception 'permission deals.edit required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_values) is distinct from 'object' then
    raise exception 'values must be an object' using errcode = '22023';
  end if;

  v_merged := crm.clean_custom_fields(v_lead.custom_fields || p_values);

  select string_agg(d.value->'label'->>'en', ', ' order by d.sort_order)
  into v_missing
  from crm.organization_pack_items d
  where d.organization_id = v_lead.organization_id
    and d.kind = 'custom_field'
    and d.value->>'entity' = 'deal'
    and coalesce((d.value->>'required')::boolean, false)
    and not coalesce((d.value->>'archived')::boolean, false)
    and not v_merged ? d.item_key;
  if v_missing is not null then
    raise exception 'required: %', v_missing using errcode = '22023';
  end if;

  update crm.leads set custom_fields = v_merged
  where id = p_lead_id
  returning * into v_lead;
  if not found then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  return v_lead.custom_fields;
end;
$function$
;


