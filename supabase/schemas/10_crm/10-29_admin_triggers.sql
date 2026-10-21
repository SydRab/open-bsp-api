-- Super-admin console triggers (P1-10). Tables: 10-27.

-- Append-only, no exceptions: unlike crm.audit_log this table is not
-- organization-scoped, so there is no purge to carve an exception for.
create function crm.before_change_on_platform_audit_log() returns trigger
language plpgsql
set search_path to ''
as $$
begin
  raise exception 'the platform audit log is append-only' using errcode = '42501';
end;
$$;

create trigger append_only
before update or delete
on crm.platform_audit_log
for each row
execute function crm.before_change_on_platform_audit_log();

create trigger append_only_truncate
before truncate
on crm.platform_audit_log
for each statement
execute function crm.before_change_on_platform_audit_log();

-- A support-access grant or its revocation also shows in the organization's
-- own audit log: the tenant can see when the platform looked at their
-- configuration, and why — the platform-wide record is in
-- crm.platform_audit_log (written by crm.grant_support_access /
-- revoke_support_access themselves).
create function crm.audit_support_access_grants() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'INSERT' then
    perform crm.write_audit(
      new.organization_id, 'support_access.granted', 'support_access', new.id::text,
      jsonb_build_object('reason', new.reason, 'expires_at', new.expires_at)
    );
  elsif new.revoked_at is not null and old.revoked_at is null then
    perform crm.write_audit(
      new.organization_id, 'support_access.revoked', 'support_access', new.id::text, '{}'::jsonb
    );
  end if;

  return null;
end;
$$;

create trigger audit
after insert or update of revoked_at
on crm.support_access_grants
for each row
execute function crm.audit_support_access_grants();
