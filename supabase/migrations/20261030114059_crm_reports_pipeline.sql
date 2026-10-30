set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.report_source_performance(p_organization_id uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(source text, ad_source_id text, lead_count bigint, qualified_count bigint, converted_count bigint, dropped_count bigint, total_deal_value numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(p_organization_id, 'reports.view');

  return query
  select
    l.source,
    case
      when l.source in ('ctwa_ad', 'ctwa_post') then c.first_touch_referral->>'source_id'
      else null
    end as ad_source_id,
    count(*)::bigint,
    count(*) filter (where l.status = 'qualified')::bigint,
    count(*) filter (where l.status = 'converted')::bigint,
    count(*) filter (where l.status = 'dropped')::bigint,
    coalesce(sum(l.deal_value) filter (where l.status = 'converted'), 0)
  from crm.leads l
  join crm.contacts c on c.id = l.contact_id
  where l.organization_id = p_organization_id
    and (p_from is null or l.created_at >= p_from)
    and (p_to is null or l.created_at < p_to)
  group by 1, 2
  order by 3 desc;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.report_status_funnel(p_organization_id uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(status text, lead_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(p_organization_id, 'reports.view');

  return query
  select l.status, count(*)::bigint
  from crm.leads l
  where l.organization_id = p_organization_id
    and (p_from is null or l.created_at >= p_from)
    and (p_to is null or l.created_at < p_to)
  group by l.status;
end;
$function$
;


