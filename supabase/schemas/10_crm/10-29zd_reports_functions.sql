-- [crm] P3-10a: pipeline reports (funnel, source/ad performance,
-- conversion rates). Gated on `reports.view` -- a permission that has sat
-- in the catalog unused since P1-02 (seeded by default for sales_manager/
-- marketing/admin/owner, not sales_rep), exactly reserved for this task.
-- A binary gate like `audit.view`, not further scoped by the caller's own
-- lead_scope: reports are inherently cross-rep aggregates, not an
-- individual lead-working view.
--
-- `status` is treated as the funnel (crm.leads' own fixed, non-tenant-
-- editable lifecycle, per its own schema comment) rather than `stage_id`
-- (the tenant's own funnel vocabulary, never guaranteed sequential -- a
-- lead can skip or revisit a stage). Conversion rates are computed by the
-- caller from these raw counts, not returned as pre-divided floats.
create function crm.report_status_funnel(
  p_organization_id uuid,
  p_from timestamp with time zone default null,
  p_to timestamp with time zone default null
) returns table (status text, lead_count bigint)
language plpgsql
stable
security definer
set search_path to ''
as $$
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
$$;

-- One row per (source, ad id) -- ad_source_id is null for organic/manual
-- leads, and for ad-sourced leads whose referral never carried a
-- ctwa_clid-bearing source_id (same "not every referral has one" shape
-- P3-09 already accounts for). total_deal_value only sums converted
-- leads -- a deal_value on a still-open lead is an estimate, not revenue.
create function crm.report_source_performance(
  p_organization_id uuid,
  p_from timestamp with time zone default null,
  p_to timestamp with time zone default null
) returns table (
  source text,
  ad_source_id text,
  lead_count bigint,
  qualified_count bigint,
  converted_count bigint,
  dropped_count bigint,
  total_deal_value numeric
)
language plpgsql
stable
security definer
set search_path to ''
as $$
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
$$;
