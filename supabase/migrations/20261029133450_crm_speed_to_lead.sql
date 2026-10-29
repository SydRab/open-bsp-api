
  create table "crm"."notifications" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "agent_id" uuid not null,
    "kind" text not null,
    "title" text not null,
    "body" text,
    "lead_id" uuid,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."notifications" enable row level security;

alter table "crm"."leads" add column "first_responded_at" timestamp with time zone;

alter table "crm"."leads" add column "first_response_due_at" timestamp with time zone;

CREATE INDEX notifications_agent_unread_idx ON crm.notifications USING btree (organization_id, agent_id, created_at DESC) WHERE (read_at IS NULL);

CREATE UNIQUE INDEX notifications_pkey ON crm.notifications USING btree (id);

alter table "crm"."notifications" add constraint "notifications_pkey" PRIMARY KEY using index "notifications_pkey";

alter table "crm"."notifications" add constraint "notifications_agent_fkey" FOREIGN KEY (organization_id, agent_id) REFERENCES public.agents(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."notifications" validate constraint "notifications_agent_fkey";

alter table "crm"."notifications" add constraint "notifications_kind_check" CHECK ((kind = ANY (ARRAY['lead_sla_breached'::text, 'lead_escalated_to_manager'::text, 'lead_auto_reassigned'::text]))) not valid;

alter table "crm"."notifications" validate constraint "notifications_kind_check";

alter table "crm"."notifications" add constraint "notifications_lead_fkey" FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE CASCADE not valid;

alter table "crm"."notifications" validate constraint "notifications_lead_fkey";

alter table "crm"."notifications" add constraint "notifications_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."notifications" validate constraint "notifications_organization_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._create_notification(p_organization_id uuid, p_agent_id uuid, p_kind text, p_title text, p_body text, p_lead_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into crm.notifications (organization_id, agent_id, kind, title, body, lead_id)
  values (p_organization_id, p_agent_id, p_kind, p_title, p_body, p_lead_id);
end;
$function$
;

CREATE OR REPLACE FUNCTION crm._lead_escalation_managers(p_organization_id uuid, p_agent_id uuid)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select distinct a.id
  from public.agents a
  join crm.member_roles mr on mr.agent_id = a.id and mr.organization_id = p_organization_id
  join crm.roles r on r.id = mr.role_id
  where a.organization_id = p_organization_id
    and a.deleted_at is null
    and a.id <> p_agent_id
    and (
      coalesce(mr.lead_scope, r.lead_scope) = 'all'
      or (
        coalesce(mr.lead_scope, r.lead_scope) = 'team'
        and exists (
          select 1 from crm.team_members tm1
          join crm.team_members tm2 on tm2.team_id = tm1.team_id
          where tm1.agent_id = p_agent_id and tm2.agent_id = a.id
        )
      )
    );
$function$
;

CREATE OR REPLACE FUNCTION crm.mark_all_notifications_read(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_self uuid := (crm.caller_agent(p_organization_id)).id;
begin
  update crm.notifications
  set read_at = now()
  where organization_id = p_organization_id and agent_id = v_self and read_at is null;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.mark_notification_read(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_organization_id uuid;
  v_self uuid;
begin
  select organization_id into v_organization_id from crm.notifications where id = p_id;
  if v_organization_id is null then
    raise exception 'notification not found' using errcode = 'P0002';
  end if;

  v_self := (crm.caller_agent(v_organization_id)).id;

  update crm.notifications
  set read_at = coalesce(read_at, now())
  where id = p_id and agent_id = v_self;

  if not found then
    raise exception 'notification not found' using errcode = 'P0002';
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.sweep_speed_to_lead_escalation()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads;
  v_manager_minutes int;
  v_reassign_minutes int;
  v_manager_due timestamp with time zone;
  v_reassign_due timestamp with time zone;
  v_manager_id uuid;
begin
  for v_lead in
    select * from crm.leads
    where assigned_to is not null
      and first_responded_at is null
      and status in ('open', 'qualified')
      and first_response_due_at is not null
      and first_response_due_at <= now()
  loop
    if not exists (
      select 1 from crm.audit_log
      where organization_id = v_lead.organization_id and target_type = 'lead'
        and target_id = v_lead.id::text and action = 'lead.sla_breached'
    ) then
      perform crm._create_notification(
        v_lead.organization_id, v_lead.assigned_to, 'lead_sla_breached',
        'Lead needs a response', 'A lead assigned to you has passed the first-response SLA.',
        v_lead.id
      );
      perform crm.write_audit(
        v_lead.organization_id, 'lead.sla_breached', 'lead', v_lead.id::text, '{}'::jsonb
      );
    end if;

    v_manager_minutes := coalesce(
      ((select r.value from crm.resolve_setting(v_lead.organization_id, 'speed_to_lead.manager_escalation_minutes') r) #>> '{}')::int,
      15
    );
    v_manager_due := v_lead.first_response_due_at + make_interval(mins => v_manager_minutes);

    if now() >= v_manager_due and not exists (
      select 1 from crm.audit_log
      where organization_id = v_lead.organization_id and target_type = 'lead'
        and target_id = v_lead.id::text and action = 'lead.escalated_to_manager'
    ) then
      for v_manager_id in
        select m from crm._lead_escalation_managers(v_lead.organization_id, v_lead.assigned_to) m
      loop
        perform crm._create_notification(
          v_lead.organization_id, v_manager_id, 'lead_escalated_to_manager',
          'Lead response overdue', 'A lead has gone unanswered past the escalation window.',
          v_lead.id
        );
      end loop;
      perform crm.write_audit(
        v_lead.organization_id, 'lead.escalated_to_manager', 'lead', v_lead.id::text, '{}'::jsonb
      );
    end if;

    v_reassign_minutes := coalesce(
      ((select r.value from crm.resolve_setting(v_lead.organization_id, 'speed_to_lead.reassign_escalation_minutes') r) #>> '{}')::int,
      30
    );
    v_reassign_due := v_manager_due + make_interval(mins => v_reassign_minutes);

    -- Only a qualified lead has an assignment rule/team to re-route
    -- through (crm._ensure_assignment's own guard) -- a manually
    -- assigned, still-open lead stays with the same unresponsive rep
    -- past this point rather than being silently dropped; the manager
    -- notification above already fired for it.
    if now() >= v_reassign_due then
      perform crm._create_notification(
        v_lead.organization_id, v_lead.assigned_to, 'lead_auto_reassigned',
        'Lead reassigned', 'A lead assigned to you was reassigned after going unanswered too long.',
        v_lead.id
      );
      perform crm.write_audit(
        v_lead.organization_id, 'lead.auto_reassigned_sla', 'lead', v_lead.id::text,
        jsonb_build_object('from_agent_id', v_lead.assigned_to)
      );

      update crm.leads
      set assigned_to = null, assigned_at = null, first_response_due_at = null
      where id = v_lead.id;

      perform crm._ensure_assignment(v_lead.organization_id, v_lead.id);
    end if;
  end loop;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.z_record_first_response()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_human boolean;
  v_contact_id uuid;
  v_lead crm.leads;
begin
  select (user_id is not null) into v_human from public.agents where id = new.agent_id;
  if not coalesce(v_human, false) then
    return new;
  end if;

  select ca.contact_id into v_contact_id
  from crm.contact_addresses ca
  where ca.organization_id = new.organization_id
    and ca.service = new.service
    and ca.address = new.conversation_address;
  if v_contact_id is null then
    return new;
  end if;

  select * into v_lead from crm.leads
  where organization_id = new.organization_id and contact_id = v_contact_id
    and assigned_to is not null and first_responded_at is null;
  if not found then
    return new;
  end if;

  update crm.leads set first_responded_at = now() where id = v_lead.id;

  perform crm.write_audit(
    new.organization_id, 'lead.first_responded', 'lead', v_lead.id::text,
    jsonb_build_object(
      'minutes_to_respond', round(extract(epoch from (now() - v_lead.assigned_at)) / 60, 1)
    )
  );

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.z_set_response_deadline()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_minutes int;
begin
  v_minutes := coalesce(
    ((select r.value from crm.resolve_setting(new.organization_id, 'speed_to_lead.first_response_sla_minutes') r) #>> '{}')::int,
    15
  );
  new.first_response_due_at := now() + make_interval(mins => v_minutes);
  return new;
end;
$function$
;

grant select on table "crm"."notifications" to "anon";

grant select on table "crm"."notifications" to "authenticated";

grant delete on table "crm"."notifications" to "service_role";

grant insert on table "crm"."notifications" to "service_role";

grant references on table "crm"."notifications" to "service_role";

grant select on table "crm"."notifications" to "service_role";

grant trigger on table "crm"."notifications" to "service_role";

grant truncate on table "crm"."notifications" to "service_role";

grant update on table "crm"."notifications" to "service_role";


  create policy "members can read their own notifications"
  on "crm"."notifications"
  as permissive
  for select
  to authenticated
using (((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)) AND (EXISTS ( SELECT 1
   FROM public.agents a
  WHERE ((a.id = notifications.agent_id) AND (a.user_id = auth.uid()) AND (a.deleted_at IS NULL))))));


CREATE TRIGGER z_set_response_deadline BEFORE UPDATE ON crm.leads FOR EACH ROW WHEN (((new.assigned_to IS DISTINCT FROM old.assigned_to) AND (new.assigned_to IS NOT NULL) AND (new.first_responded_at IS NULL))) EXECUTE FUNCTION crm.z_set_response_deadline();

CREATE TRIGGER z_record_first_response AFTER INSERT ON public.messages FOR EACH ROW WHEN (((new.sender_address IS NULL) AND (new.agent_id IS NOT NULL))) EXECUTE FUNCTION crm.z_record_first_response();


