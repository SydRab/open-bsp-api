-- Feature override audit (P1-09). Tier-feature catalog edits and kill-switch
-- toggles are platform reference data with no single organization to log
-- them against, so only per-organization overrides are audited here.

create function crm.audit_organization_features() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_row crm.organization_features := case when tg_op = 'DELETE' then old else new end;
begin
  if tg_op = 'UPDATE'
    and new.enabled is not distinct from old.enabled
    and new.expires_at is not distinct from old.expires_at
    and new.reason is not distinct from old.reason then
    return null;
  end if;

  perform crm.write_audit(
    v_row.organization_id,
    case when tg_op = 'DELETE' then 'feature.override_cleared' else 'feature.override_set' end,
    'feature',
    v_row.feature_key,
    case when tg_op = 'DELETE' then '{}'::jsonb else jsonb_strip_nulls(jsonb_build_object(
      'enabled', v_row.enabled, 'reason', v_row.reason, 'expires_at', v_row.expires_at
    )) end
  );

  return null;
end;
$$;

create trigger audit
after insert or update or delete
on crm.organization_features
for each row
execute function crm.audit_organization_features();
