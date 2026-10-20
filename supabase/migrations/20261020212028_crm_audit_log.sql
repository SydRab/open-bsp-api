
  create table "crm"."audit_log" (
    "id" bigint generated always as identity not null,
    "organization_id" uuid not null,
    "created_at" timestamp with time zone not null default now(),
    "actor_type" text not null,
    "actor_user_id" uuid,
    "actor_agent_id" uuid,
    "actor_api_key_id" uuid,
    "action" text not null,
    "target_type" text,
    "target_id" text,
    "details" jsonb not null default '{}'::jsonb,
    "request_id" text
      );


alter table "crm"."audit_log" enable row level security;

CREATE INDEX audit_log_organization_id_action_idx ON crm.audit_log USING btree (organization_id, action);

CREATE INDEX audit_log_organization_id_actor_idx ON crm.audit_log USING btree (organization_id, actor_agent_id);

CREATE INDEX audit_log_organization_id_id_idx ON crm.audit_log USING btree (organization_id, id DESC);

CREATE UNIQUE INDEX audit_log_pkey ON crm.audit_log USING btree (id);

alter table "crm"."audit_log" add constraint "audit_log_pkey" PRIMARY KEY using index "audit_log_pkey";

alter table "crm"."audit_log" add constraint "audit_log_action_check" CHECK ((action ~ '^[a-z_]+\.[a-z_]+$'::text)) not valid;

alter table "crm"."audit_log" validate constraint "audit_log_action_check";

alter table "crm"."audit_log" add constraint "audit_log_actor_type_check" CHECK ((actor_type = ANY (ARRAY['user'::text, 'api_key'::text, 'service'::text, 'system'::text]))) not valid;

alter table "crm"."audit_log" validate constraint "audit_log_actor_type_check";

alter table "crm"."audit_log" add constraint "audit_log_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."audit_log" validate constraint "audit_log_organization_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.audit_agents()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_action text;
begin
  if new.user_id is null then
    return null;
  end if;

  if tg_op = 'INSERT' then
    v_action := 'member.joined';
  elsif old.deleted_at is null and new.deleted_at is not null then
    v_action := 'member.deactivated';
  elsif old.deleted_at is not null and new.deleted_at is null then
    v_action := 'member.reactivated';
  else
    return null;
  end if;

  perform crm.write_audit(
    new.organization_id, v_action, 'member', new.id::text,
    jsonb_build_object('name', new.name)
  );

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_invitation_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.write_audit(
    new.organization_id, 'invitation.created', 'invitation', new.id::text,
    jsonb_strip_nulls(jsonb_build_object(
      'email', new.email,
      'tier', new.role,
      'role', (
        select r.key
        from crm.invitation_roles ir
        join crm.roles r on r.id = ir.role_id
        where ir.invitation_id = new.id
      )
    ))
  );

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_invitation_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status is distinct from old.status
    and new.status in ('accepted', 'rejected', 'revoked') then
    perform crm.write_audit(
      new.organization_id, 'invitation.' || new.status, 'invitation',
      new.id::text,
      jsonb_build_object('email', new.email)
    );
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_member_address_access()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    perform crm.write_audit(
      old.organization_id, 'member.number_access_revoked', 'member',
      old.agent_id::text,
      jsonb_build_object('service', old.service, 'address', old.address)
    );
  else
    perform crm.write_audit(
      new.organization_id, 'member.number_access_granted', 'member',
      new.agent_id::text,
      jsonb_build_object('service', new.service, 'address', new.address)
    );
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_member_permission_overrides()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    perform crm.write_audit(
      old.organization_id, 'member.permission_override_removed', 'member',
      old.agent_id::text,
      jsonb_build_object('permission', old.permission)
    );
  elsif tg_op = 'INSERT' or new.granted is distinct from old.granted then
    perform crm.write_audit(
      new.organization_id, 'member.permission_override_set', 'member',
      new.agent_id::text,
      jsonb_build_object('permission', new.permission, 'granted', new.granted)
    );
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_member_roles()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' or new.role_id is distinct from old.role_id then
    perform crm.write_audit(
      new.organization_id, 'member.role_changed', 'member', new.agent_id::text,
      jsonb_build_object(
        'before', case when tg_op = 'UPDATE' then jsonb_build_object(
          'role', (select r.key from crm.roles r where r.id = old.role_id)
        ) end,
        'after', jsonb_build_object(
          'role', (select r.key from crm.roles r where r.id = new.role_id)
        )
      )
    );
  end if;

  if tg_op = 'UPDATE' and new.lead_scope is distinct from old.lead_scope then
    perform crm.write_audit(
      new.organization_id, 'member.lead_scope_changed', 'member',
      new.agent_id::text,
      jsonb_build_object(
        'before', jsonb_build_object('lead_scope', old.lead_scope),
        'after', jsonb_build_object('lead_scope', new.lead_scope)
      )
    );
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_organization_pack_items()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.value is not distinct from old.value
    or new.pack_value is distinct from old.pack_value then
    return null;
  end if;

  perform crm.write_audit(
    new.organization_id,
    case
      when new.value is not distinct from new.pack_value then 'pack.item_reset'
      else 'pack.item_updated'
    end,
    'pack_item',
    new.id::text,
    jsonb_build_object(
      'kind', new.kind,
      'key', new.item_key,
      'before', old.value,
      'after', new.value
    )
  );

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_organization_packs()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' then
    perform crm.write_audit(
      new.organization_id, 'pack.applied', 'pack', new.pack_key,
      jsonb_build_object('pack', new.pack_key, 'version', new.version)
    );
  elsif new.version is distinct from old.version then
    perform crm.write_audit(
      new.organization_id, 'pack.upgraded', 'pack', new.pack_key,
      jsonb_build_object(
        'pack', new.pack_key,
        'before', jsonb_build_object('version', old.version),
        'after', jsonb_build_object('version', new.version)
      )
    );
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_organization_profiles()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_before jsonb := '{}'::jsonb;
  v_after jsonb := '{}'::jsonb;
begin
  if tg_op = 'INSERT' then
    perform crm.write_audit(
      new.organization_id, 'organization.created', 'organization',
      new.organization_id::text,
      jsonb_build_object(
        'slug', new.slug, 'timezone', new.timezone, 'locale', new.locale
      )
    );
    return null;
  end if;

  if new.status is distinct from old.status then
    perform crm.write_audit(
      new.organization_id,
      case
        when new.status = 'suspended' then 'organization.suspended'
        when new.status = 'pending_deletion' then 'organization.deletion_requested'
        when old.status = 'suspended' then 'organization.reactivated'
        else 'organization.deletion_cancelled'
      end,
      'organization',
      new.organization_id::text,
      jsonb_strip_nulls(jsonb_build_object(
        'reason', new.suspended_reason,
        'purge_after', new.purge_after
      ))
    );
  end if;

  if new.slug is distinct from old.slug then
    v_before := v_before || jsonb_build_object('slug', old.slug);
    v_after := v_after || jsonb_build_object('slug', new.slug);
  end if;
  if new.timezone is distinct from old.timezone then
    v_before := v_before || jsonb_build_object('timezone', old.timezone);
    v_after := v_after || jsonb_build_object('timezone', new.timezone);
  end if;
  if new.locale is distinct from old.locale then
    v_before := v_before || jsonb_build_object('locale', old.locale);
    v_after := v_after || jsonb_build_object('locale', new.locale);
  end if;

  if v_after <> '{}'::jsonb then
    perform crm.write_audit(
      new.organization_id, 'organization.profile_updated', 'organization',
      new.organization_id::text,
      jsonb_build_object('before', v_before, 'after', v_after)
    );
  end if;

  if new.require_mfa_for_admins is distinct from old.require_mfa_for_admins then
    perform crm.write_audit(
      new.organization_id, 'organization.mfa_requirement_changed',
      'organization', new.organization_id::text,
      jsonb_build_object('required', new.require_mfa_for_admins)
    );
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_organizations()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.name is distinct from old.name then
    perform crm.write_audit(
      new.id, 'organization.profile_updated', 'organization', new.id::text,
      jsonb_build_object(
        'before', jsonb_build_object('name', old.name),
        'after', jsonb_build_object('name', new.name)
      )
    );
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_role_permissions()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' then
    perform crm.write_audit(
      new.organization_id, 'role.permission_granted', 'role', new.role_id::text,
      jsonb_build_object(
        'permission', new.permission,
        'role', (select r.key from crm.roles r where r.id = new.role_id)
      )
    );
  elsif exists (select 1 from crm.roles r where r.id = old.role_id) then
    perform crm.write_audit(
      old.organization_id, 'role.permission_revoked', 'role', old.role_id::text,
      jsonb_build_object(
        'permission', old.permission,
        'role', (select r.key from crm.roles r where r.id = old.role_id)
      )
    );
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.before_change_on_audit_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' and current_setting('crm.purging', true) = 'on' then
    return old;
  end if;

  raise exception 'the audit log is append-only'
    using errcode = '42501';
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.get_audit_log(p_organization_id uuid, p_before_id bigint DEFAULT NULL::bigint, p_limit integer DEFAULT 50, p_area text DEFAULT NULL::text, p_actor uuid DEFAULT NULL::uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(id bigint, created_at timestamp with time zone, actor_type text, actor_agent_id uuid, actor_name text, action text, target_type text, target_id text, target_name text, details jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(p_organization_id, 'audit.view');

  return query
  select
    l.id,
    l.created_at,
    l.actor_type,
    l.actor_agent_id,
    coalesce(actor.name, ak.name),
    l.action,
    l.target_type,
    l.target_id,
    coalesce(member.name, r.name),
    l.details
  from crm.audit_log l
  left join public.agents actor on actor.id = l.actor_agent_id
  left join public.api_keys ak on ak.id = l.actor_api_key_id
  left join public.agents member
    on l.target_type = 'member'
   and member.organization_id = l.organization_id
   and member.id::text = l.target_id
  left join crm.roles r
    on l.target_type = 'role'
   and r.organization_id = l.organization_id
   and r.id::text = l.target_id
  where l.organization_id = p_organization_id
    and (p_before_id is null or l.id < p_before_id)
    and (p_area is null or split_part(l.action, '.', 1) = p_area)
    and (p_actor is null or l.actor_agent_id = p_actor)
    and (p_from is null or l.created_at >= p_from)
    and (p_to is null or l.created_at < p_to)
  order by l.id desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.write_audit(p_organization_id uuid, p_action text, p_target_type text DEFAULT NULL::text, p_target_id text DEFAULT NULL::text, p_details jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_headers json;
  v_api_key text;
  v_actor_type text;
  v_user_id uuid := auth.uid();
  v_agent_id uuid;
  v_api_key_id uuid;
begin
  if current_setting('crm.purging', true) = 'on'
    or current_setting('crm.audit_suppress', true) = 'on'
    or not exists (
      select 1 from public.organizations o where o.id = p_organization_id
    ) then
    return;
  end if;

  v_headers := nullif(current_setting('request.headers', true), '')::json;

  if v_user_id is not null then
    v_actor_type := 'user';
    select a.id into v_agent_id
    from public.agents a
    where a.organization_id = p_organization_id
      and a.user_id = v_user_id;
  else
    v_api_key := v_headers->>'api-key';

    if v_api_key is not null then
      -- Only the key's id is stored, never the key.
      select k.id into v_api_key_id
      from public.api_keys k
      where k.key = v_api_key;
    end if;

    if v_api_key_id is not null then
      v_actor_type := 'api_key';
    elsif auth.role() = 'service_role' then
      v_actor_type := 'service';
    else
      v_actor_type := 'system';
    end if;
  end if;

  insert into crm.audit_log (
    organization_id, actor_type, actor_user_id, actor_agent_id,
    actor_api_key_id, action, target_type, target_id, details, request_id
  ) values (
    p_organization_id, v_actor_type, v_user_id, v_agent_id,
    v_api_key_id, p_action, p_target_type, p_target_id,
    coalesce(p_details, '{}'::jsonb),
    left(coalesce(v_headers->>'x-request-id', v_headers->>'sb-request-id'), 100)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.create_preset_roles(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform set_config('crm.audit_suppress', 'on', true);

  insert into crm.roles (
    organization_id, key, name, description, tier, lead_scope, is_preset,
    is_locked, sort_order
  )
  select
    p_organization_id, pr.key, pr.name, pr.description, pr.tier,
    pr.lead_scope, true, pr.key = 'owner', pr.sort_order
  from crm.preset_roles pr
  on conflict (organization_id, key) do nothing;

  insert into crm.role_permissions (organization_id, role_id, permission)
  select r.organization_id, r.id, prp.permission
  from crm.roles r
  join crm.preset_role_permissions prp on prp.role_key = r.key
  where r.organization_id = p_organization_id
    and r.key <> 'owner'
  on conflict do nothing;

  insert into crm.role_permissions (organization_id, role_id, permission)
  select r.organization_id, r.id, pm.key
  from crm.roles r
  cross join crm.permissions pm
  where r.organization_id = p_organization_id
    and r.key = 'owner'
  on conflict do nothing;

  perform set_config('crm.audit_suppress', 'off', true);
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.purge_organizations()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_count int;
begin
  -- Lets these organizations' audit rows go with them (the one exception
  -- to append-only, see 10-05) and keeps the cascade from writing new ones.
  perform set_config('crm.purging', 'on', true);

  delete from public.organizations o
  using crm.organization_profiles p
  where p.organization_id = o.id
    and p.status = 'pending_deletion'
    and p.purge_after <= now();

  get diagnostics v_count = row_count;

  perform set_config('crm.purging', 'off', true);
  return v_count;
end;
$function$
;

grant select on table "crm"."audit_log" to "authenticated";

grant select on table "crm"."audit_log" to "service_role";


  create policy "audit viewers can read their orgs audit log"
  on "crm"."audit_log"
  as permissive
  for select
  to authenticated
using ((organization_id IN ( SELECT crm.get_permitted_orgs('audit.view'::text) AS get_permitted_orgs)));


CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON crm.audit_log FOR EACH ROW EXECUTE FUNCTION crm.before_change_on_audit_log();

CREATE TRIGGER append_only_truncate BEFORE TRUNCATE ON crm.audit_log FOR EACH STATEMENT EXECUTE FUNCTION crm.before_change_on_audit_log();

CREATE TRIGGER audit AFTER INSERT OR DELETE ON crm.member_address_access FOR EACH ROW EXECUTE FUNCTION crm.audit_member_address_access();

CREATE TRIGGER audit AFTER INSERT OR DELETE OR UPDATE ON crm.member_permission_overrides FOR EACH ROW EXECUTE FUNCTION crm.audit_member_permission_overrides();

CREATE TRIGGER audit AFTER INSERT OR UPDATE OF role_id, lead_scope ON crm.member_roles FOR EACH ROW EXECUTE FUNCTION crm.audit_member_roles();

CREATE TRIGGER audit AFTER UPDATE OF value ON crm.organization_pack_items FOR EACH ROW EXECUTE FUNCTION crm.audit_organization_pack_items();

CREATE TRIGGER audit AFTER INSERT OR UPDATE OF version ON crm.organization_packs FOR EACH ROW EXECUTE FUNCTION crm.audit_organization_packs();

CREATE TRIGGER audit AFTER INSERT OR UPDATE ON crm.organization_profiles FOR EACH ROW EXECUTE FUNCTION crm.audit_organization_profiles();

CREATE TRIGGER audit AFTER INSERT OR DELETE ON crm.role_permissions FOR EACH ROW EXECUTE FUNCTION crm.audit_role_permissions();

CREATE TRIGGER crm_audit_membership AFTER INSERT OR UPDATE OF deleted_at ON public.agents FOR EACH ROW EXECUTE FUNCTION crm.audit_agents();

CREATE CONSTRAINT TRIGGER crm_audit_invitation_created AFTER INSERT ON public.invitations DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION crm.audit_invitation_created();

CREATE TRIGGER crm_audit_invitation_status AFTER UPDATE OF status ON public.invitations FOR EACH ROW EXECUTE FUNCTION crm.audit_invitation_status();

CREATE TRIGGER crm_audit_organization AFTER UPDATE OF name ON public.organizations FOR EACH ROW EXECUTE FUNCTION crm.audit_organizations();


