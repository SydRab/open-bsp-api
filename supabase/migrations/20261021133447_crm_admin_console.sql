
  create table "crm"."platform_admins" (
    "user_id" uuid not null,
    "granted_at" timestamp with time zone not null default now(),
    "granted_by" uuid
      );


alter table "crm"."platform_admins" enable row level security;


  create table "crm"."platform_audit_log" (
    "id" bigint generated always as identity not null,
    "created_at" timestamp with time zone not null default now(),
    "actor_user_id" uuid not null,
    "action" text not null,
    "target_type" text,
    "target_id" text,
    "details" jsonb not null default '{}'::jsonb
      );


alter table "crm"."platform_audit_log" enable row level security;


  create table "crm"."support_access_grants" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "admin_id" uuid not null,
    "reason" text not null,
    "granted_at" timestamp with time zone not null default now(),
    "expires_at" timestamp with time zone not null,
    "revoked_at" timestamp with time zone
      );


alter table "crm"."support_access_grants" enable row level security;

CREATE UNIQUE INDEX platform_admins_pkey ON crm.platform_admins USING btree (user_id);

CREATE INDEX platform_audit_log_id_idx ON crm.platform_audit_log USING btree (id DESC);

CREATE UNIQUE INDEX platform_audit_log_pkey ON crm.platform_audit_log USING btree (id);

CREATE INDEX support_access_grants_admin_id_org_idx ON crm.support_access_grants USING btree (admin_id, organization_id);

CREATE INDEX support_access_grants_organization_id_idx ON crm.support_access_grants USING btree (organization_id);

CREATE UNIQUE INDEX support_access_grants_pkey ON crm.support_access_grants USING btree (id);

alter table "crm"."platform_admins" add constraint "platform_admins_pkey" PRIMARY KEY using index "platform_admins_pkey";

alter table "crm"."platform_audit_log" add constraint "platform_audit_log_pkey" PRIMARY KEY using index "platform_audit_log_pkey";

alter table "crm"."support_access_grants" add constraint "support_access_grants_pkey" PRIMARY KEY using index "support_access_grants_pkey";

alter table "crm"."platform_admins" add constraint "platform_admins_granted_by_fkey" FOREIGN KEY (granted_by) REFERENCES auth.users(id) not valid;

alter table "crm"."platform_admins" validate constraint "platform_admins_granted_by_fkey";

alter table "crm"."platform_admins" add constraint "platform_admins_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "crm"."platform_admins" validate constraint "platform_admins_user_id_fkey";

alter table "crm"."platform_audit_log" add constraint "platform_audit_log_action_check" CHECK ((action ~ '^[a-z_]+\.[a-z_]+$'::text)) not valid;

alter table "crm"."platform_audit_log" validate constraint "platform_audit_log_action_check";

alter table "crm"."platform_audit_log" add constraint "platform_audit_log_actor_user_id_fkey" FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) not valid;

alter table "crm"."platform_audit_log" validate constraint "platform_audit_log_actor_user_id_fkey";

alter table "crm"."support_access_grants" add constraint "support_access_grants_admin_id_fkey" FOREIGN KEY (admin_id) REFERENCES auth.users(id) not valid;

alter table "crm"."support_access_grants" validate constraint "support_access_grants_admin_id_fkey";

alter table "crm"."support_access_grants" add constraint "support_access_grants_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."support_access_grants" validate constraint "support_access_grants_organization_id_fkey";

alter table "crm"."support_access_grants" add constraint "support_access_grants_reason_check" CHECK ((length(TRIM(BOTH FROM reason)) >= 3)) not valid;

alter table "crm"."support_access_grants" validate constraint "support_access_grants_reason_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.admin_get_audit_log(p_organization_id uuid, p_admin_id uuid, p_before_id bigint DEFAULT NULL::bigint, p_limit integer DEFAULT 50)
 RETURNS TABLE(id bigint, created_at timestamp with time zone, actor_type text, actor_agent_id uuid, actor_name text, action text, target_type text, target_id text, target_name text, details jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_platform_admin(p_admin_id);
  if not crm.has_active_support_access(p_organization_id, p_admin_id) then
    raise exception 'no active support-access grant for this organization'
      using errcode = '42501';
  end if;

  return query
  select
    l.id, l.created_at, l.actor_type, l.actor_agent_id,
    coalesce(actor.name, ak.name), l.action, l.target_type, l.target_id,
    coalesce(member.name, r.name), l.details
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
  order by l.id desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.admin_get_tenant_config(p_organization_id uuid, p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_platform_admin(p_admin_id);
  if not crm.has_active_support_access(p_organization_id, p_admin_id) then
    raise exception 'no active support-access grant for this organization'
      using errcode = '42501';
  end if;

  return jsonb_build_object(
    'profile', (
      select to_jsonb(p) from crm.organization_profiles p
      where p.organization_id = p_organization_id
    ),
    'roles', (
      select jsonb_agg(jsonb_build_object(
        'key', r.key, 'name', r.name,
        'permissions', (
          select jsonb_agg(rp.permission) from crm.role_permissions rp
          where rp.role_id = r.id
        )
      ))
      from crm.roles r where r.organization_id = p_organization_id
    ),
    'settings', (
      select jsonb_agg(jsonb_build_object(
        'key', d.key, 'category', d.category, 'label', d.label,
        'value', r.value, 'source', r.source, 'is_locked', d.is_locked
      ))
      from crm.setting_definitions d
      cross join lateral crm.resolve_setting(p_organization_id, d.key) r
    ),
    'features', (
      select jsonb_agg(to_jsonb(f)) from crm.get_features(p_organization_id) f
    ),
    'pack_items', (
      select jsonb_agg(jsonb_build_object(
        'kind', i.kind, 'key', i.item_key, 'value', i.value, 'customized', i.is_customized
      ))
      from crm.organization_pack_items i where i.organization_id = p_organization_id
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.admin_upgrade_organization_pack(p_organization_id uuid, p_version integer, p_admin_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_current crm.organization_packs;
  v_target int;
begin
  perform crm.require_platform_admin(p_admin_id);

  select * into v_current
  from crm.organization_packs
  where organization_id = p_organization_id;

  if not found then
    raise exception 'organization has no pack' using errcode = 'P0002';
  end if;

  v_target := coalesce(
    p_version,
    (select max(version) from crm.pack_versions where pack_key = v_current.pack_key)
  );

  perform crm.apply_pack(p_organization_id, v_current.pack_key, v_target);

  perform crm.write_platform_audit(
    p_admin_id, 'organization.pack_upgraded', 'organization', p_organization_id::text,
    jsonb_build_object('pack', v_current.pack_key, 'version', v_target)
  );

  return v_target;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.audit_support_access_grants()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.before_change_on_platform_audit_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception 'the platform audit log is append-only' using errcode = '42501';
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.get_platform_audit_log(p_before_id bigint DEFAULT NULL::bigint, p_limit integer DEFAULT 50)
 RETURNS TABLE(id bigint, created_at timestamp with time zone, actor_email text, action text, target_type text, target_id text, details jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select l.id, l.created_at, u.email, l.action, l.target_type, l.target_id, l.details
  from crm.platform_audit_log l
  join auth.users u on u.id = l.actor_user_id
  where p_before_id is null or l.id < p_before_id
  order by l.id desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
$function$
;

CREATE OR REPLACE FUNCTION crm.get_support_access(p_organization_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, organization_id uuid, organization_name text, admin_id uuid, admin_email text, reason text, granted_at timestamp with time zone, expires_at timestamp with time zone, revoked_at timestamp with time zone, active boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    g.id, g.organization_id, o.name, g.admin_id, u.email, g.reason,
    g.granted_at, g.expires_at, g.revoked_at,
    g.revoked_at is null and g.expires_at > now()
  from crm.support_access_grants g
  join public.organizations o on o.id = g.organization_id
  join auth.users u on u.id = g.admin_id
  where p_organization_id is null or g.organization_id = p_organization_id
  order by g.granted_at desc;
$function$
;

CREATE OR REPLACE FUNCTION crm.grant_platform_admin(p_email text, p_granted_by uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid;
begin
  perform crm.require_platform_admin(p_granted_by);

  select id into v_user_id from auth.users where lower(email) = lower(trim(p_email));
  if v_user_id is null then
    raise exception 'no user with that email' using errcode = 'P0002';
  end if;

  insert into crm.platform_admins (user_id, granted_by)
  values (v_user_id, p_granted_by)
  on conflict (user_id) do nothing;

  perform crm.write_platform_audit(
    p_granted_by, 'platform_admin.granted', 'user', v_user_id::text,
    jsonb_build_object('email', lower(trim(p_email)))
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.grant_support_access(p_organization_id uuid, p_admin_id uuid, p_reason text, p_hours integer DEFAULT 24)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
begin
  perform crm.require_platform_admin(p_admin_id);

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'a reason is required' using errcode = '22023';
  end if;
  if p_hours is null or p_hours < 1 or p_hours > 168 then
    raise exception 'hours must be between 1 and 168 (one week)' using errcode = '22023';
  end if;
  if not exists (select 1 from public.organizations o where o.id = p_organization_id) then
    raise exception 'organization not found' using errcode = 'P0002';
  end if;

  insert into crm.support_access_grants (organization_id, admin_id, reason, expires_at)
  values (p_organization_id, p_admin_id, trim(p_reason), now() + make_interval(hours => p_hours))
  returning id into v_id;

  perform crm.write_platform_audit(
    p_admin_id, 'support_access.granted', 'organization', p_organization_id::text,
    jsonb_build_object('reason', trim(p_reason), 'hours', p_hours)
  );

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.has_active_support_access(p_organization_id uuid, p_admin_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from crm.support_access_grants g
    where g.organization_id = p_organization_id
      and g.admin_id = p_admin_id
      and g.revoked_at is null
      and g.expires_at > now()
  );
$function$
;

CREATE OR REPLACE FUNCTION crm.is_platform_admin(p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.role() <> 'service_role' and p_user_id is distinct from auth.uid() then
    raise exception 'can only check your own admin status' using errcode = '42501';
  end if;

  return p_user_id is not null
    and exists (select 1 from crm.platform_admins a where a.user_id = p_user_id);
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.list_platform_admins()
 RETURNS TABLE(user_id uuid, email text, granted_at timestamp with time zone, granted_by uuid, granted_by_email text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select a.user_id, u.email, a.granted_at, a.granted_by, gu.email
  from crm.platform_admins a
  join auth.users u on u.id = a.user_id
  left join auth.users gu on gu.id = a.granted_by
  order by a.granted_at;
$function$
;

CREATE OR REPLACE FUNCTION crm.list_tenants(p_search text DEFAULT NULL::text)
 RETURNS TABLE(organization_id uuid, name text, slug text, status text, tier_id text, tier_name text, seats_used numeric, seats_cap numeric, pack_key text, pack_version integer, latest_pack_version integer, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    o.id, o.name, p.slug, p.status,
    s.tier_id, t.name,
    coalesce(u.quantity, 0), tp.cap,
    op.pack_key, op.version,
    (select max(pv.version) from crm.pack_versions pv where pv.pack_key = op.pack_key),
    o.created_at
  from public.organizations o
  join crm.organization_profiles p on p.organization_id = o.id
  left join billing.subscriptions s on s.organization_id = o.id
  left join billing.tiers t on t.id = s.tier_id
  left join billing.usage u
    on u.organization_id = o.id and u.product_id = 'members' and u.interval = 'lifetime'
  left join billing.tiers_products tp
    on tp.tier_id = s.tier_id and tp.product_id = 'members'
  left join crm.organization_packs op on op.organization_id = o.id
  where p_search is null
    or o.name ilike '%' || p_search || '%'
    or p.slug ilike '%' || p_search || '%'
  order by o.created_at desc;
$function$
;

CREATE OR REPLACE FUNCTION crm.require_platform_admin(p_admin_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_admin_id is null
    or not exists (select 1 from crm.platform_admins a where a.user_id = p_admin_id) then
    raise exception 'only platform admins can do this' using errcode = '42501';
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.revoke_platform_admin(p_user_id uuid, p_revoked_by uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_count int;
begin
  perform crm.require_platform_admin(p_revoked_by);

  select count(*) into v_count from crm.platform_admins;
  if v_count <= 1 and exists (
    select 1 from crm.platform_admins where user_id = p_user_id
  ) then
    raise exception 'cannot remove the last platform admin' using errcode = '22023';
  end if;

  delete from crm.platform_admins where user_id = p_user_id;
  if found then
    perform crm.write_platform_audit(p_revoked_by, 'platform_admin.revoked', 'user', p_user_id::text);
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.revoke_support_access(p_grant_id uuid, p_admin_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
begin
  perform crm.require_platform_admin(p_admin_id);

  update crm.support_access_grants
  set revoked_at = now()
  where id = p_grant_id and revoked_at is null
  returning organization_id into v_org;

  if not found then
    raise exception 'grant not found or already revoked' using errcode = 'P0002';
  end if;

  perform crm.write_platform_audit(p_admin_id, 'support_access.revoked', 'organization', v_org::text);
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_organization_tier(p_organization_id uuid, p_tier_id text, p_admin_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_before text;
begin
  perform crm.require_platform_admin(p_admin_id);

  if not exists (select 1 from billing.tiers t where t.id = p_tier_id and t.active) then
    raise exception 'unknown or inactive tier %', p_tier_id using errcode = '22023';
  end if;

  select tier_id into v_before from billing.subscriptions where organization_id = p_organization_id;

  if v_before is null then
    insert into billing.subscriptions (organization_id, tier_id)
    values (p_organization_id, p_tier_id);
  else
    update billing.subscriptions set tier_id = p_tier_id where organization_id = p_organization_id;
  end if;

  perform crm.write_platform_audit(
    p_admin_id, 'organization.tier_changed', 'organization', p_organization_id::text,
    jsonb_build_object('before', v_before, 'after', p_tier_id)
  );
  perform crm.write_audit(
    p_organization_id, 'organization.tier_changed', 'organization', p_organization_id::text,
    jsonb_build_object('before', v_before, 'after', p_tier_id)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.write_platform_audit(p_admin_id uuid, p_action text, p_target_type text DEFAULT NULL::text, p_target_id text DEFAULT NULL::text, p_details jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into crm.platform_audit_log (actor_user_id, action, target_type, target_id, details)
  values (p_admin_id, p_action, p_target_type, p_target_id, coalesce(p_details, '{}'::jsonb));
end;
$function$
;

grant select on table "crm"."platform_admins" to "anon";

grant select on table "crm"."platform_admins" to "authenticated";

grant delete on table "crm"."platform_admins" to "service_role";

grant insert on table "crm"."platform_admins" to "service_role";

grant references on table "crm"."platform_admins" to "service_role";

grant select on table "crm"."platform_admins" to "service_role";

grant trigger on table "crm"."platform_admins" to "service_role";

grant truncate on table "crm"."platform_admins" to "service_role";

grant update on table "crm"."platform_admins" to "service_role";

grant select on table "crm"."platform_audit_log" to "anon";

grant select on table "crm"."platform_audit_log" to "authenticated";

grant delete on table "crm"."platform_audit_log" to "service_role";

grant insert on table "crm"."platform_audit_log" to "service_role";

grant references on table "crm"."platform_audit_log" to "service_role";

grant select on table "crm"."platform_audit_log" to "service_role";

grant trigger on table "crm"."platform_audit_log" to "service_role";

grant truncate on table "crm"."platform_audit_log" to "service_role";

grant update on table "crm"."platform_audit_log" to "service_role";

grant select on table "crm"."support_access_grants" to "anon";

grant select on table "crm"."support_access_grants" to "authenticated";

grant delete on table "crm"."support_access_grants" to "service_role";

grant insert on table "crm"."support_access_grants" to "service_role";

grant references on table "crm"."support_access_grants" to "service_role";

grant select on table "crm"."support_access_grants" to "service_role";

grant trigger on table "crm"."support_access_grants" to "service_role";

grant truncate on table "crm"."support_access_grants" to "service_role";

grant update on table "crm"."support_access_grants" to "service_role";


  create policy "org managers can see support-access grants against their org"
  on "crm"."support_access_grants"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT crm.get_permitted_orgs('organization.manage'::text) AS get_permitted_orgs)));


CREATE TRIGGER append_only BEFORE DELETE OR UPDATE ON crm.platform_audit_log FOR EACH ROW EXECUTE FUNCTION crm.before_change_on_platform_audit_log();

CREATE TRIGGER append_only_truncate BEFORE TRUNCATE ON crm.platform_audit_log FOR EACH STATEMENT EXECUTE FUNCTION crm.before_change_on_platform_audit_log();

CREATE TRIGGER audit AFTER INSERT OR UPDATE OF revoked_at ON crm.support_access_grants FOR EACH ROW EXECUTE FUNCTION crm.audit_support_access_grants();


