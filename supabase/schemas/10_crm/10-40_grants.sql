-- Privileges. Last but one in 10_crm because `on all … in schema` only
-- covers objects that already exist.
--
-- Tables: API roles read (rows narrowed by 10-30) and update only the
-- columns a plain policy can safely govern. All other writes go through the
-- SECURITY DEFINER functions.
grant select on all tables in schema crm to anon, authenticated;
grant all on all tables in schema crm to service_role;

-- Profile (P1-01) and business details (P1-07).
grant update (
  slug, timezone, locale,
  legal_name, address, support_email, support_phone, website, registrations
) on crm.organization_profiles to authenticated;
grant update (value) on crm.organization_pack_items to authenticated;

-- Functions: Postgres grants EXECUTE to PUBLIC by default, which would put
-- every function behind /rest/v1/rpc for anyone (see 06-40 for the same
-- reasoning on billing). Revoke, then grant back what each caller needs.
revoke execute on all functions in schema crm from public;
grant execute on all functions in schema crm to service_role;

-- Used inside RLS policies and by the UI.
grant execute on function crm.get_permitted_orgs(text) to anon, authenticated;
grant execute on function crm.has_permission(uuid, text) to anon, authenticated;
grant execute on function crm.needs_mfa_step_up(uuid) to authenticated;
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
grant execute on function crm.get_my_invitation_roles() to authenticated;
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

-- Audit log (P1-08): read-only for every API role, and only signed-in members
-- (through the policy in 10-30) and the platform. Nobody writes but
-- crm.write_audit, which runs as the owner.
revoke all on crm.audit_log from anon, authenticated, service_role;
grant select on crm.audit_log to authenticated, service_role;

grant execute on function crm.get_audit_log(uuid, bigint, int, text, uuid, timestamp with time zone, timestamp with time zone) to authenticated;
-- crm.write_audit: service_role only (edge functions), via the grant above.

-- Settings and teams (P1-04). Tables are read-only (select, from the grant
-- above); writes go through these functions, each checking its permission.
grant execute on function crm.get_setting(uuid, text, uuid) to anon, authenticated;
grant execute on function crm.get_settings(uuid) to anon, authenticated;
grant execute on function crm.set_setting(uuid, text, jsonb, text, uuid) to authenticated;
grant execute on function crm.reset_setting(uuid, text, text, uuid) to authenticated;
grant execute on function crm.create_team(uuid, text) to authenticated;
grant execute on function crm.rename_team(uuid, text) to authenticated;
grant execute on function crm.delete_team(uuid) to authenticated;
grant execute on function crm.set_team_member(uuid, uuid, boolean) to authenticated;
-- Internal (service_role only): resolve_setting, setting_target,
-- assert_can_read_settings, validate_setting_value.

-- Tags (P2-09b).
grant execute on function crm.create_tag(uuid, text) to authenticated;
grant execute on function crm.rename_tag(uuid, text) to authenticated;
grant execute on function crm.set_tag_color(uuid, text) to authenticated;
grant execute on function crm.delete_tag(uuid) to authenticated;
grant execute on function crm.set_conversation_tag(uuid, uuid, boolean) to authenticated;

-- Assignments (P2-09c).
grant execute on function crm.assign_conversation(uuid, uuid) to authenticated;
grant execute on function crm.unassign_conversation(uuid) to authenticated;

-- Canned replies (P2-09e).
grant execute on function crm.create_canned_reply(uuid, text, text) to authenticated;
grant execute on function crm.update_canned_reply(uuid, text, text) to authenticated;
grant execute on function crm.delete_canned_reply(uuid) to authenticated;

-- Lead model (P3-02). seed_lead_catalogs: platform only (service_role, via
-- the blanket grant above) -- called from the org-creation trigger.
grant execute on function crm.create_lead_stage(uuid, text) to authenticated;
grant execute on function crm.update_lead_stage(uuid, text, int) to authenticated;
grant execute on function crm.delete_lead_stage(uuid) to authenticated;
grant execute on function crm.create_lead_quality(uuid, text) to authenticated;
grant execute on function crm.update_lead_quality(uuid, text, int) to authenticated;
grant execute on function crm.delete_lead_quality(uuid) to authenticated;
grant execute on function crm.create_lead_drop_reason(uuid, text) to authenticated;
grant execute on function crm.update_lead_drop_reason(uuid, text, int) to authenticated;
grant execute on function crm.delete_lead_drop_reason(uuid) to authenticated;
grant execute on function crm.find_or_create_lead(uuid, uuid, text) to authenticated;
grant execute on function crm.set_lead_stage(uuid, uuid) to authenticated;
grant execute on function crm.set_lead_quality(uuid, uuid) to authenticated;
grant execute on function crm.set_lead_status(uuid, text, uuid) to authenticated;

-- Disclaimers (P1-07). render_with_disclaimer is what senders call (edge
-- functions as service_role; also members and keys, for previews).
grant execute on function crm.get_disclaimers(uuid) to anon, authenticated;
grant execute on function crm.set_disclaimer(uuid, text, text, text) to authenticated;
grant execute on function crm.render_with_disclaimer(uuid, text, text, text) to anon, authenticated;
-- Internal: current_disclaimer, disclaimer_text_error.

-- Contacts and custom fields (P1-06).
grant update (custom_fields) on crm.contacts to authenticated;
grant execute on function crm.create_custom_field(uuid, text, text, text, jsonb, jsonb, boolean) to authenticated;
grant execute on function crm.update_custom_field(uuid, jsonb, jsonb, boolean) to authenticated;
grant execute on function crm.archive_custom_field(uuid, boolean) to authenticated;
grant execute on function crm.set_contact_fields(uuid, jsonb) to authenticated;
grant execute on function crm.filter_contacts(uuid, jsonb, int, int) to anon, authenticated;
grant execute on function crm.format_custom_field(uuid, text, text, jsonb, text) to anon, authenticated;
-- Used by the functions above, which run as the caller.
grant execute on function crm.clean_custom_fields(jsonb) to anon, authenticated;
grant execute on function crm.custom_field_matches(jsonb, jsonb) to anon, authenticated;

-- Feature flags and plan entitlements (P1-09). Tables are read-only via the
-- blanket select grant above (10-30 RLS narrows rows); writes go through
-- these functions. set_organization_feature, clear_organization_feature and
-- set_feature_kill_switch are platform only (service_role, by the blanket
-- grant above) and check auth.role() themselves too.
grant execute on function crm.has_feature(uuid, text) to anon, authenticated;
grant execute on function crm.require_feature(uuid, text) to anon, authenticated;
grant execute on function crm.get_features(uuid) to anon, authenticated;

-- Super-admin console (P1-10). Every function here is reachable only by
-- service_role (the crm-admin edge function) via the blanket grant above,
-- except is_platform_admin, which the UI also calls directly to decide
-- whether to show the console at all (self-check only; see its own guard).
grant execute on function crm.is_platform_admin(uuid) to anon, authenticated;
