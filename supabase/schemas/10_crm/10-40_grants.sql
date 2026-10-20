-- Privileges. Last but one in 10_crm because `on all … in schema` only
-- covers objects that already exist.
--
-- Tables: API roles read (rows narrowed by 10-30) and update only the
-- columns a plain policy can safely govern. All other writes go through the
-- SECURITY DEFINER functions.
grant select on all tables in schema crm to anon, authenticated;
grant all on all tables in schema crm to service_role;

grant update (slug, timezone, locale) on crm.organization_profiles to authenticated;
grant update (value) on crm.organization_pack_items to authenticated;

-- Functions: Postgres grants EXECUTE to PUBLIC by default, which would put
-- every function behind /rest/v1/rpc for anyone (see 06-40 for the same
-- reasoning on billing). Revoke, then grant back what each caller needs.
revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

-- Used inside RLS policies and by the UI.
grant execute on function crm.get_permitted_orgs(text) to anon, authenticated;
grant execute on function crm.has_permission(uuid, text) to anon, authenticated;
grant execute on function crm.get_hidden_addresses() to anon, authenticated;
grant execute on function crm.tier_rank(public.role) to anon, authenticated;
grant execute on function crm.my_permissions(uuid) to authenticated;
grant execute on function crm.get_my_organization_statuses() to authenticated;

-- Member actions. Each checks its own permission.
grant execute on function crm.request_organization_deletion(uuid) to authenticated;
grant execute on function crm.cancel_organization_deletion(uuid) to authenticated;
grant execute on function crm.set_require_mfa_for_admins(uuid, boolean) to authenticated;
grant execute on function crm.invite_member(uuid, text, text) to authenticated;
grant execute on function crm.revoke_invitation(uuid) to authenticated;
grant execute on function crm.set_member_role(uuid, text) to authenticated;
grant execute on function crm.deactivate_member(uuid) to authenticated;
grant execute on function crm.set_member_lead_scope(uuid, text) to authenticated;
grant execute on function crm.set_member_permission_override(uuid, text, boolean) to authenticated;
grant execute on function crm.set_member_address_access(uuid, public.service, text, boolean) to authenticated;
grant execute on function crm.set_role_permission(uuid, text, boolean) to authenticated;
grant execute on function crm.reset_role_permissions(uuid) to authenticated;
grant execute on function crm.upgrade_organization_pack(uuid, int) to authenticated;
grant execute on function crm.reset_pack_item(uuid) to authenticated;

-- Platform only (service_role): suspend_organization, reactivate_organization,
-- purge_organizations, apply_pack, create_preset_roles, generate_slug.
