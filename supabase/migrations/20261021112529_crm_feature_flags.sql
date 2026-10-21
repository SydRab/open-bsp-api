
  create table "crm"."features" (
    "key" text not null,
    "category" text not null default 'modules'::text,
    "label" text not null,
    "description" text,
    "kill_switch" boolean not null default false,
    "sort_order" integer not null default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."features" enable row level security;


  create table "crm"."organization_features" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "feature_key" text not null,
    "enabled" boolean not null,
    "reason" text,
    "expires_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."organization_features" enable row level security;


  create table "crm"."tier_features" (
    "tier_id" text not null,
    "feature_key" text not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."tier_features" enable row level security;

CREATE UNIQUE INDEX features_pkey ON crm.features USING btree (key);

CREATE UNIQUE INDEX organization_features_organization_id_feature_key_key ON crm.organization_features USING btree (organization_id, feature_key);

CREATE INDEX organization_features_organization_id_idx ON crm.organization_features USING btree (organization_id);

CREATE UNIQUE INDEX organization_features_pkey ON crm.organization_features USING btree (id);

CREATE UNIQUE INDEX tier_features_pkey ON crm.tier_features USING btree (tier_id, feature_key);

alter table "crm"."features" add constraint "features_pkey" PRIMARY KEY using index "features_pkey";

alter table "crm"."organization_features" add constraint "organization_features_pkey" PRIMARY KEY using index "organization_features_pkey";

alter table "crm"."tier_features" add constraint "tier_features_pkey" PRIMARY KEY using index "tier_features_pkey";

alter table "crm"."organization_features" add constraint "organization_features_feature_key_fkey" FOREIGN KEY (feature_key) REFERENCES crm.features(key) ON DELETE CASCADE not valid;

alter table "crm"."organization_features" validate constraint "organization_features_feature_key_fkey";

alter table "crm"."organization_features" add constraint "organization_features_organization_id_feature_key_key" UNIQUE using index "organization_features_organization_id_feature_key_key";

alter table "crm"."organization_features" add constraint "organization_features_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."organization_features" validate constraint "organization_features_organization_id_fkey";

alter table "crm"."tier_features" add constraint "tier_features_feature_key_fkey" FOREIGN KEY (feature_key) REFERENCES crm.features(key) ON DELETE CASCADE not valid;

alter table "crm"."tier_features" validate constraint "tier_features_feature_key_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.audit_organization_features()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION crm.clear_organization_feature(p_organization_id uuid, p_feature_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.role() <> 'service_role' then
    raise exception 'only the platform can override features'
      using errcode = '42501';
  end if;

  delete from crm.organization_features
  where organization_id = p_organization_id and feature_key = p_feature_key;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.get_features(p_organization_id uuid)
 RETURNS TABLE(key text, category text, label text, description text, enabled boolean, source text, override_reason text, override_expires_at timestamp with time zone, unlocks_at_tier text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tier_id text;
begin
  perform crm.assert_can_read_settings(p_organization_id);

  select s.tier_id into v_tier_id
  from billing.subscriptions s
  where s.organization_id = p_organization_id;

  return query
  select
    f.key, f.category, f.label, f.description,
    crm.has_feature(p_organization_id, f.key),
    case
      when f.kill_switch then 'kill_switch'
      when o.feature_key is not null then 'override'
      when v_tier_id is null then 'unrestricted'
      else 'tier'
    end,
    o.reason,
    o.expires_at,
    (
      select tf.tier_id from crm.tier_features tf
      join billing.tiers t on t.id = tf.tier_id
      where tf.feature_key = f.key
      order by t.level asc
      limit 1
    )
  from crm.features f
  left join crm.organization_features o
    on o.organization_id = p_organization_id
   and o.feature_key = f.key
   and (o.expires_at is null or o.expires_at > now())
  order by f.sort_order, f.key;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.has_feature(p_organization_id uuid, p_feature_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_kill_switch boolean;
  v_override boolean;
  v_tier_id text;
begin
  -- Same access rule as crm.get_setting: a signed-in caller must belong to
  -- the organization, so this cannot be used to probe another tenant's plan.
  perform crm.assert_can_read_settings(p_organization_id);

  select f.kill_switch into v_kill_switch
  from crm.features f
  where f.key = p_feature_key;
  if not found then
    raise exception 'unknown feature %', p_feature_key using errcode = '22023';
  end if;
  if v_kill_switch then
    return false;
  end if;

  select o.enabled into v_override
  from crm.organization_features o
  where o.organization_id = p_organization_id
    and o.feature_key = p_feature_key
    and (o.expires_at is null or o.expires_at > now());
  if found then
    return v_override;
  end if;

  select s.tier_id into v_tier_id
  from billing.subscriptions s
  where s.organization_id = p_organization_id;
  if not found then
    return true;
  end if;

  return exists (
    select 1 from crm.tier_features tf
    where tf.tier_id = v_tier_id and tf.feature_key = p_feature_key
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.require_feature(p_organization_id uuid, p_feature_key text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not crm.has_feature(p_organization_id, p_feature_key) then
    raise exception 'your plan does not include %', (
      select f.label from crm.features f where f.key = p_feature_key
    ) using errcode = '42501';
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_feature_kill_switch(p_feature_key text, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.role() <> 'service_role' then
    raise exception 'only the platform can use the kill switch'
      using errcode = '42501';
  end if;

  update crm.features set kill_switch = p_enabled where key = p_feature_key;
  if not found then
    raise exception 'unknown feature %', p_feature_key using errcode = '22023';
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_organization_feature(p_organization_id uuid, p_feature_key text, p_enabled boolean, p_reason text DEFAULT NULL::text, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.role() <> 'service_role' then
    raise exception 'only the platform can override features'
      using errcode = '42501';
  end if;

  if not exists (select 1 from crm.features f where f.key = p_feature_key) then
    raise exception 'unknown feature %', p_feature_key using errcode = '22023';
  end if;

  insert into crm.organization_features (
    organization_id, feature_key, enabled, reason, expires_at
  ) values (
    p_organization_id, p_feature_key, p_enabled, p_reason, p_expires_at
  )
  on conflict (organization_id, feature_key) do update
    set enabled = excluded.enabled,
        reason = excluded.reason,
        expires_at = excluded.expires_at,
        updated_at = now();
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.track_member_usage()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _org_id uuid := coalesce(new.organization_id, old.organization_id);
  _old int := 0;
  _new int := 0;
begin
  if tg_op <> 'INSERT' then
    _old := (old.user_id is not null and old.deleted_at is null)::int;
  end if;

  if tg_op <> 'DELETE' then
    _new := (new.user_id is not null and new.deleted_at is null)::int;
  end if;

  if _new = _old then
    return null;
  end if;

  -- Cascade from an organization delete: its billing rows are going too.
  if not exists (select 1 from public.organizations where id = _org_id) then
    return null;
  end if;

  -- Only a brand-new active member is checked against the cap. Revival
  -- (crm.invite_member already gives the inviting admin an early, friendlier
  -- check, 10-12) goes through the same INSERT-or-UPDATE-of-deleted_at path,
  -- so a reinstated member is checked too — unlike a reconnecting WhatsApp
  -- account, this is always a deliberate action with a human to tell.
  if _new > _old then
    perform billing.check_limit(_org_id, 'members');
  end if;

  perform billing.update_usage(_org_id, 'members', _new - _old);
  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.invite_member(p_organization_id uuid, p_email text, p_role_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_email text := lower(trim(p_email));
  v_caller public.agents;
  v_role crm.roles;
  v_invitation_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'members.invite');
  v_caller := crm.caller_agent(p_organization_id);

  -- A friendly check for the inviting admin (P1-09): the seat is only truly
  -- consumed, and the limit truly enforced, when the invitee accepts
  -- (crm.track_member_usage, 10-25).
  perform billing.check_limit(p_organization_id, 'members');

  if v_email is null or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid email address'
      using errcode = '22023';
  end if;

  select * into v_role
  from crm.roles
  where organization_id = p_organization_id
    and key = p_role_key;

  if not found then
    raise exception 'unknown role %', p_role_key
      using errcode = '22023';
  end if;

  if crm.tier_rank(v_role.tier) > crm.tier_rank(v_caller.role) then
    raise exception 'cannot invite someone to a role above your own'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.agents a
    join auth.users u on u.id = a.user_id
    where a.organization_id = p_organization_id
      and a.deleted_at is null
      and lower(u.email) = v_email
  ) then
    raise exception 'already a member of this organization'
      using errcode = '23505';
  end if;

  -- A second pending invitation for the same email fails on the upstream
  -- unique index invitations_pending_email_key (23505).
  insert into public.invitations (organization_id, email, role, invited_by)
  values (p_organization_id, v_email, v_role.tier, v_caller.id)
  returning id into v_invitation_id;

  insert into crm.invitation_roles (invitation_id, organization_id, role_id)
  values (v_invitation_id, p_organization_id, v_role.id);

  return v_invitation_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_setting(p_organization_id uuid, p_key text, p_value jsonb, p_scope text DEFAULT 'tenant'::text, p_target uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_target record;
  v_error text;
begin
  select * into v_target
  from crm.setting_target(p_organization_id, p_key, p_scope, p_target);

  v_error := crm.validate_setting_value(
    (select d.schema from crm.setting_definitions d where d.key = p_key),
    p_value
  );
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023';
  end if;

  -- Modules are also features (P1-09): a plan can leave one out entirely,
  -- which turning the setting on cannot work around. Turning one off always
  -- works, and resetting (crm.reset_setting) is unaffected.
  if p_key like 'modules.%' and p_value = 'true'::jsonb
    and not crm.has_feature(p_organization_id, substring(p_key from 9)) then
    raise exception 'your plan does not include this module'
      using errcode = '42501';
  end if;

  insert into crm.setting_values (
    organization_id, setting_key, scope, team_id, agent_id, value, updated_by
  ) values (
    p_organization_id, p_key, p_scope, v_target.team_id, v_target.agent_id,
    p_value, (crm.caller_agent(p_organization_id)).id
  )
  on conflict on constraint setting_values_target_key do update
    set value = excluded.value,
        updated_by = excluded.updated_by,
        updated_at = now()
    where crm.setting_values.value is distinct from excluded.value;
end;
$function$
;

grant select on table "crm"."features" to "anon";

grant select on table "crm"."features" to "authenticated";

grant delete on table "crm"."features" to "service_role";

grant insert on table "crm"."features" to "service_role";

grant references on table "crm"."features" to "service_role";

grant select on table "crm"."features" to "service_role";

grant trigger on table "crm"."features" to "service_role";

grant truncate on table "crm"."features" to "service_role";

grant update on table "crm"."features" to "service_role";

grant select on table "crm"."organization_features" to "anon";

grant select on table "crm"."organization_features" to "authenticated";

grant delete on table "crm"."organization_features" to "service_role";

grant insert on table "crm"."organization_features" to "service_role";

grant references on table "crm"."organization_features" to "service_role";

grant select on table "crm"."organization_features" to "service_role";

grant trigger on table "crm"."organization_features" to "service_role";

grant truncate on table "crm"."organization_features" to "service_role";

grant update on table "crm"."organization_features" to "service_role";

grant select on table "crm"."tier_features" to "anon";

grant select on table "crm"."tier_features" to "authenticated";

grant delete on table "crm"."tier_features" to "service_role";

grant insert on table "crm"."tier_features" to "service_role";

grant references on table "crm"."tier_features" to "service_role";

grant select on table "crm"."tier_features" to "service_role";

grant trigger on table "crm"."tier_features" to "service_role";

grant truncate on table "crm"."tier_features" to "service_role";

grant update on table "crm"."tier_features" to "service_role";


  create policy "signed-in users can read the feature catalog"
  on "crm"."features"
  as permissive
  for select
  to authenticated, anon
using (true);



  create policy "members can read their orgs feature overrides"
  on "crm"."organization_features"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "signed-in users can read tier entitlements"
  on "crm"."tier_features"
  as permissive
  for select
  to authenticated, anon
using (true);


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.features FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER audit AFTER INSERT OR DELETE OR UPDATE ON crm.organization_features FOR EACH ROW EXECUTE FUNCTION crm.audit_organization_features();

CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.organization_features FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER crm_track_member_usage AFTER INSERT OR DELETE OR UPDATE OF deleted_at ON public.agents FOR EACH ROW EXECUTE FUNCTION crm.track_member_usage();


