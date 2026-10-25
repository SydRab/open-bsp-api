
  create table "crm"."assignment_rules" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "team_id" uuid not null,
    "match_language" text,
    "match_source" text,
    "match_campaign_ref" text,
    "sort_order" integer not null default 0,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."assignment_rules" enable row level security;

alter table "crm"."leads" add column "assigned_at" timestamp with time zone;

alter table "crm"."leads" add column "assigned_to" uuid;

alter table "crm"."team_members" add column "weight" integer not null default 1;

CREATE INDEX assignment_rules_organization_id_idx ON crm.assignment_rules USING btree (organization_id);

CREATE UNIQUE INDEX assignment_rules_pkey ON crm.assignment_rules USING btree (id);

CREATE INDEX leads_assigned_to_idx ON crm.leads USING btree (organization_id, assigned_to) WHERE (assigned_to IS NOT NULL);

alter table "crm"."assignment_rules" add constraint "assignment_rules_pkey" PRIMARY KEY using index "assignment_rules_pkey";

alter table "crm"."assignment_rules" add constraint "assignment_rules_match_language_check" CHECK (((match_language IS NULL) OR (match_language = ANY (ARRAY['en'::text, 'hi'::text])))) not valid;

alter table "crm"."assignment_rules" validate constraint "assignment_rules_match_language_check";

alter table "crm"."assignment_rules" add constraint "assignment_rules_match_source_check" CHECK (((match_source IS NULL) OR (match_source = ANY (ARRAY['ctwa_ad'::text, 'ctwa_post'::text, 'organic'::text, 'manual'::text])))) not valid;

alter table "crm"."assignment_rules" validate constraint "assignment_rules_match_source_check";

alter table "crm"."assignment_rules" add constraint "assignment_rules_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."assignment_rules" validate constraint "assignment_rules_organization_id_fkey";

alter table "crm"."assignment_rules" add constraint "assignment_rules_team_fkey" FOREIGN KEY (organization_id, team_id) REFERENCES crm.teams(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."assignment_rules" validate constraint "assignment_rules_team_fkey";

alter table "crm"."leads" add constraint "leads_assigned_to_fkey" FOREIGN KEY (organization_id, assigned_to) REFERENCES public.agents(organization_id, id) not valid;

alter table "crm"."leads" validate constraint "leads_assigned_to_fkey";

alter table "crm"."team_members" add constraint "team_members_weight_check" CHECK ((weight > 0)) not valid;

alter table "crm"."team_members" validate constraint "team_members_weight_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._ensure_assignment(p_organization_id uuid, p_lead_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads;
  v_team uuid;
  v_agent uuid;
begin
  select * into v_lead from crm.leads where id = p_lead_id and status = 'qualified';
  if not found then
    return;
  end if;

  v_team := crm._match_assignment_rule(p_organization_id, p_lead_id);
  if v_team is null then
    return;
  end if;

  v_agent := crm._pick_assignee(p_organization_id, v_team);
  if v_agent is null then
    return;
  end if;

  update crm.leads set assigned_to = v_agent, assigned_at = now() where id = p_lead_id;

  perform crm.write_audit(
    p_organization_id,
    case when v_lead.assigned_to is null then 'lead.assigned' else 'lead.reassigned' end,
    'lead', p_lead_id::text,
    jsonb_build_object('agent_id', v_agent, 'from_agent_id', v_lead.assigned_to, 'team_id', v_team)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm._match_assignment_rule(p_organization_id uuid, p_lead_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select r.team_id
  from crm.leads l
  join crm.contacts c on c.id = l.contact_id
  join crm.assignment_rules r
    on r.organization_id = p_organization_id and r.is_active
  where l.id = p_lead_id
    and (r.match_language is null or r.match_language = coalesce(c.locale, 'en'))
    and (r.match_source is null or r.match_source = l.source)
    and (
      r.match_campaign_ref is null
      or r.match_campaign_ref = c.first_touch_referral->>'source_id'
    )
  order by r.sort_order
  limit 1;
$function$
;

CREATE OR REPLACE FUNCTION crm._pick_assignee(p_organization_id uuid, p_team_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cap int;
  v_hours jsonb;
  v_tz text;
  v_now_local timestamp;
  v_day text;
  v_agent uuid;
begin
  select (value #>> '{}')::int into v_cap
  from crm.setting_values
  where organization_id = p_organization_id
    and setting_key = 'assignment.capacity_cap' and scope = 'tenant';

  -- Unset per team = unrestricted, by design (not crm.resolve_setting's
  -- usual fallback chain -- a team with no working_hours row is simply
  -- always available, rather than inheriting a platform default that
  -- would restrict every team nobody has configured yet).
  select value into v_hours
  from crm.setting_values
  where organization_id = p_organization_id
    and setting_key = 'assignment.working_hours' and scope = 'team' and team_id = p_team_id;

  select coalesce(timezone, 'Asia/Kolkata') into v_tz
  from crm.organization_profiles where organization_id = p_organization_id;
  v_now_local := now() at time zone coalesce(v_tz, 'Asia/Kolkata');
  v_day := lower(to_char(v_now_local, 'dy'));

  if v_hours is not null and not (
    v_hours->'days' @> to_jsonb(v_day)
    and v_now_local::time between (v_hours->>'start')::time and (v_hours->>'end')::time
  ) then
    return null;
  end if;

  select tm.agent_id into v_agent
  from crm.team_members tm
  join public.agents a on a.id = tm.agent_id and a.deleted_at is null
  where tm.organization_id = p_organization_id and tm.team_id = p_team_id
    and (
      v_cap is null
      or (
        select count(*) from crm.leads l
        where l.organization_id = p_organization_id and l.assigned_to = tm.agent_id
          and l.status in ('open', 'qualified')
      ) < v_cap
    )
  order by (
    select count(*)::numeric from crm.leads l
    where l.organization_id = p_organization_id and l.assigned_to = tm.agent_id
      and l.status in ('open', 'qualified')
  ) / tm.weight asc
  limit 1;

  return v_agent;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.assign_lead(p_lead_id uuid, p_agent_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_lead.organization_id, 'deals.edit');

  if not exists (
    select 1 from public.agents a
    where a.id = p_agent_id and a.organization_id = v_lead.organization_id and a.deleted_at is null
  ) then
    raise exception 'agent not found' using errcode = '22023';
  end if;

  update crm.leads set assigned_to = p_agent_id, assigned_at = now() where id = p_lead_id;

  perform crm.write_audit(
    v_lead.organization_id,
    case when v_lead.assigned_to is null then 'lead.assigned' else 'lead.reassigned' end,
    'lead', p_lead_id::text,
    jsonb_build_object('agent_id', p_agent_id, 'from_agent_id', v_lead.assigned_to, 'manual', true)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.delete_assignment_rule(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select organization_id from crm.assignment_rules where id = p_id),
    'organization.manage'
  );

  delete from crm.assignment_rules where id = p_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_assignment_rule(p_organization_id uuid, p_team_id uuid, p_match_language text, p_match_source text, p_match_campaign_ref text, p_sort_order integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'organization.manage');

  if not exists (
    select 1 from crm.teams where id = p_team_id and organization_id = p_organization_id
  ) then
    raise exception 'team not found' using errcode = '22023';
  end if;

  insert into crm.assignment_rules (
    organization_id, team_id, match_language, match_source, match_campaign_ref, sort_order
  ) values (
    p_organization_id, p_team_id, p_match_language, p_match_source, p_match_campaign_ref,
    coalesce(
      p_sort_order,
      (select max(sort_order) + 1 from crm.assignment_rules where organization_id = p_organization_id),
      0
    )
  )
  returning id into v_id;

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.sweep_lead_reassignment()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads;
  v_timeout_hours int;
  v_has_activity boolean;
begin
  for v_lead in
    select * from crm.leads where assigned_to is not null and status = 'qualified'
  loop
    v_timeout_hours := coalesce(
      ((select r.value from crm.resolve_setting(v_lead.organization_id, 'assignment.reassign_timeout_hours') r) #>> '{}')::int,
      24
    );

    if v_lead.assigned_at is null
      or v_lead.assigned_at > now() - make_interval(hours => v_timeout_hours)
    then
      continue;
    end if;

    v_has_activity := exists (
      select 1 from crm.audit_log al
      where al.organization_id = v_lead.organization_id
        and al.target_type = 'lead' and al.target_id = v_lead.id::text
        and al.action like 'lead.%'
        and al.action not in ('lead.assigned', 'lead.reassigned', 'lead.unassigned')
        and al.created_at > v_lead.assigned_at
    ) or exists (
      select 1 from crm.contact_addresses ca
      join public.conversations cv
        on cv.organization_id = ca.organization_id
        and cv.service = ca.service and cv.address = ca.address
      join public.messages m on m.conversation_id = cv.id
      join public.agents a on a.id = m.agent_id
      where ca.organization_id = v_lead.organization_id and ca.contact_id = v_lead.contact_id
        and a.user_id is not null
        and m.created_at > v_lead.assigned_at
    );

    if not v_has_activity then
      perform crm._ensure_assignment(v_lead.organization_id, v_lead.id);
    end if;
  end loop;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.unassign_lead(p_lead_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found then
    raise exception 'lead not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_lead.organization_id, 'deals.edit');

  update crm.leads set assigned_to = null, assigned_at = null where id = p_lead_id;

  perform crm.write_audit(
    v_lead.organization_id, 'lead.unassigned', 'lead', p_lead_id::text,
    jsonb_build_object('from_agent_id', v_lead.assigned_to, 'manual', true)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.update_assignment_rule(p_id uuid, p_team_id uuid, p_match_language text, p_match_source text, p_match_campaign_ref text, p_sort_order integer, p_is_active boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
begin
  select organization_id into v_org from crm.assignment_rules where id = p_id;
  if v_org is null then
    raise exception 'rule not found' using errcode = '22023';
  end if;

  perform crm.require_permission(v_org, 'organization.manage');

  if not exists (select 1 from crm.teams where id = p_team_id and organization_id = v_org) then
    raise exception 'team not found' using errcode = '22023';
  end if;

  update crm.assignment_rules
  set team_id = p_team_id, match_language = p_match_language, match_source = p_match_source,
      match_campaign_ref = p_match_campaign_ref, sort_order = p_sort_order, is_active = p_is_active
  where id = p_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.z_assign_on_qualified()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_auto_assign boolean;
begin
  v_auto_assign := coalesce(
    ((select r.value from crm.resolve_setting(new.organization_id, 'assignment.auto_assign') r) #>> '{}')::boolean,
    false
  );

  if v_auto_assign and new.assigned_to is null then
    perform crm._ensure_assignment(new.organization_id, new.id);
  end if;

  return new;
end;
$function$
;

grant select on table "crm"."assignment_rules" to "anon";

grant select on table "crm"."assignment_rules" to "authenticated";

grant delete on table "crm"."assignment_rules" to "service_role";

grant insert on table "crm"."assignment_rules" to "service_role";

grant references on table "crm"."assignment_rules" to "service_role";

grant select on table "crm"."assignment_rules" to "service_role";

grant trigger on table "crm"."assignment_rules" to "service_role";

grant truncate on table "crm"."assignment_rules" to "service_role";

grant update on table "crm"."assignment_rules" to "service_role";


  create policy "members can read their orgs assignment rules"
  on "crm"."assignment_rules"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.assignment_rules FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER z_assign_on_qualified AFTER UPDATE ON crm.leads FOR EACH ROW WHEN (((new.status = 'qualified'::text) AND (old.status IS DISTINCT FROM 'qualified'::text))) EXECUTE FUNCTION crm.z_assign_on_qualified();


