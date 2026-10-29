alter table "crm"."notifications" drop constraint "notifications_kind_check";


  create table "crm"."tasks" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "lead_id" uuid not null,
    "assigned_to" uuid,
    "title" text not null,
    "due_at" timestamp with time zone not null,
    "completed_at" timestamp with time zone,
    "reminder_sent_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."tasks" enable row level security;

alter table "crm"."member_roles" add column "whatsapp_address" text;

CREATE INDEX tasks_due_idx ON crm.tasks USING btree (organization_id, due_at) WHERE ((completed_at IS NULL) AND (reminder_sent_at IS NULL));

CREATE INDEX tasks_lead_id_idx ON crm.tasks USING btree (lead_id);

CREATE UNIQUE INDEX tasks_pkey ON crm.tasks USING btree (id);

alter table "crm"."tasks" add constraint "tasks_pkey" PRIMARY KEY using index "tasks_pkey";

alter table "crm"."tasks" add constraint "tasks_assigned_to_fkey" FOREIGN KEY (organization_id, assigned_to) REFERENCES public.agents(organization_id, id) not valid;

alter table "crm"."tasks" validate constraint "tasks_assigned_to_fkey";

alter table "crm"."tasks" add constraint "tasks_lead_fkey" FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE CASCADE not valid;

alter table "crm"."tasks" validate constraint "tasks_lead_fkey";

alter table "crm"."tasks" add constraint "tasks_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."tasks" validate constraint "tasks_organization_id_fkey";

alter table "crm"."tasks" add constraint "tasks_title_check" CHECK (((length(TRIM(BOTH FROM title)) >= 1) AND (length(TRIM(BOTH FROM title)) <= 200))) not valid;

alter table "crm"."tasks" validate constraint "tasks_title_check";

alter table "crm"."notifications" add constraint "notifications_kind_check" CHECK ((kind = ANY (ARRAY['lead_sla_breached'::text, 'lead_escalated_to_manager'::text, 'lead_auto_reassigned'::text, 'task_due'::text]))) not valid;

alter table "crm"."notifications" validate constraint "notifications_kind_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm._lead_visible_to_caller(p_lead_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from crm.leads l
    where l.id = p_lead_id
      and (
        crm.resolve_lead_scope(l.organization_id) = 'all'
        or (
          crm.resolve_lead_scope(l.organization_id) = 'team'
          and l.assigned_to in (
            select tm2.agent_id
            from crm.team_members tm1
            join crm.team_members tm2 on tm2.team_id = tm1.team_id
            where tm1.agent_id = (crm.caller_agent(l.organization_id)).id
          )
        )
        or (
          crm.resolve_lead_scope(l.organization_id) = 'own'
          and l.assigned_to = (crm.caller_agent(l.organization_id)).id
        )
      )
  );
$function$
;

CREATE OR REPLACE FUNCTION crm.complete_task(p_id uuid, p_completed boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_task crm.tasks;
begin
  select * into v_task from crm.tasks where id = p_id;
  if not found then
    raise exception 'task not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_task.organization_id, 'deals.edit');

  if not crm._lead_visible_to_caller(v_task.lead_id) then
    raise exception 'task not found' using errcode = 'P0002';
  end if;

  update crm.tasks
  set completed_at = case when p_completed then coalesce(completed_at, now()) else null end
  where id = p_id;

  perform crm.write_audit(
    v_task.organization_id,
    case when p_completed then 'lead.task_completed' else 'lead.task_reopened' end,
    'lead', v_task.lead_id::text,
    jsonb_build_object('task_id', p_id, 'title', v_task.title)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.create_task(p_lead_id uuid, p_title text, p_due_at timestamp with time zone, p_assigned_to uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
  v_id uuid;
begin
  select l.organization_id into v_org from crm.leads l where l.id = p_lead_id;
  if v_org is null then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_org, 'deals.edit');

  if not crm._lead_visible_to_caller(p_lead_id) then
    raise exception 'lead not found' using errcode = 'P0002';
  end if;

  insert into crm.tasks (organization_id, lead_id, title, due_at, assigned_to)
  values (v_org, p_lead_id, trim(p_title), p_due_at, p_assigned_to)
  returning id into v_id;

  perform crm.write_audit(
    v_org, 'lead.task_created', 'lead', p_lead_id::text,
    jsonb_build_object('task_id', v_id, 'title', trim(p_title), 'due_at', p_due_at)
  );

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.delete_task(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_task crm.tasks;
begin
  select * into v_task from crm.tasks where id = p_id;
  if not found then
    raise exception 'task not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_task.organization_id, 'deals.edit');

  if not crm._lead_visible_to_caller(v_task.lead_id) then
    raise exception 'task not found' using errcode = 'P0002';
  end if;

  delete from crm.tasks where id = p_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.seed_task_reminder_template(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into crm.organization_pack_items (
    organization_id, kind, item_key, value, pack_version, sort_order
  )
  values (
    p_organization_id, 'message_template', 'internal_task_reminder',
    jsonb_build_object(
      'name', 'internal_task_reminder',
      'category', 'UTILITY',
      'purpose', 'Remind staff of a due task',
      'attach_disclaimer', false,
      'languages', jsonb_build_object(
        'en', jsonb_build_object(
          'body', 'Reminder: {{1}} is due.',
          'examples', jsonb_build_array('Call back Priya about pricing')
        ),
        'hi', jsonb_build_object(
          'body', 'याद दिलाना: {{1}} बाकी है।',
          'examples', jsonb_build_array('प्रिया को कीमत के बारे में वापस कॉल करें')
        )
      )
    ),
    0, 0
  )
  on conflict (organization_id, kind, item_key) do nothing;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_my_whatsapp_address(p_organization_id uuid, p_address text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_self uuid := (crm.caller_agent(p_organization_id)).id;
begin
  if v_self is null then
    raise exception 'not a member of this organization' using errcode = '42501';
  end if;

  if p_address is not null and p_address !~ '^[0-9]{10,15}$' then
    raise exception 'enter the WhatsApp number as digits only, with country code'
      using errcode = '22023';
  end if;

  update crm.member_roles
  set whatsapp_address = p_address, updated_at = now()
  where agent_id = v_self;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.sweep_task_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_task crm.tasks;
  v_whatsapp_address text;
  v_sender_address text;
  v_template_lang text;
  v_conversation_id uuid;
  v_message_id uuid;
begin
  for v_task in
    select * from crm.tasks
    where due_at <= now() and completed_at is null and reminder_sent_at is null
      and assigned_to is not null
  loop
    v_whatsapp_address := null;
    v_sender_address := null;
    v_template_lang := null;
    v_conversation_id := null;
    v_message_id := null;

    perform crm._create_notification(
      v_task.organization_id, v_task.assigned_to, 'task_due',
      'Task due', v_task.title, v_task.lead_id
    );

    select mr.whatsapp_address into v_whatsapp_address
    from crm.member_roles mr where mr.agent_id = v_task.assigned_to;

    if v_whatsapp_address is not null then
      select ((select r.value from crm.resolve_setting(
        v_task.organization_id, 'notifications.whatsapp_sender_address'
      ) r) #>> '{}')
      into v_sender_address;

      if v_sender_address is null then
        select oa.address into v_sender_address
        from public.organizations_addresses oa
        where oa.organization_id = v_task.organization_id
          and oa.service = 'whatsapp' and oa.status = 'connected'
        order by oa.created_at asc
        limit 1;
      end if;
    end if;

    if v_sender_address is not null then
      select t.language into v_template_lang
      from crm.templates t
      where t.organization_id = v_task.organization_id
        and t.organization_address = v_sender_address
        and t.name = 'internal_task_reminder'
        and t.status = 'APPROVED'
      order by t.language
      limit 1;
    end if;

    if v_template_lang is not null then
      insert into public.conversations (organization_id, service, organization_address, address)
      values (v_task.organization_id, 'whatsapp', v_sender_address, v_whatsapp_address)
      on conflict (organization_id, organization_address, service, address) do nothing;

      select c.id into v_conversation_id from public.conversations c
      where c.organization_id = v_task.organization_id
        and c.organization_address = v_sender_address
        and c.service = 'whatsapp' and c.address = v_whatsapp_address;

      insert into public.messages (
        organization_id, conversation_id, service, organization_address,
        conversation_address, content
      )
      values (
        v_task.organization_id, v_conversation_id, 'whatsapp', v_sender_address,
        v_whatsapp_address,
        jsonb_build_object(
          'version', '1', 'type', 'data', 'kind', 'template',
          'data', jsonb_build_object(
            'name', 'internal_task_reminder',
            'language', jsonb_build_object('code', v_template_lang, 'policy', 'deterministic'),
            'components', jsonb_build_array(
              jsonb_build_object(
                'type', 'body',
                'parameters', jsonb_build_array(
                  jsonb_build_object('type', 'text', 'text', v_task.title)
                )
              )
            )
          )
        )
      )
      returning id into v_message_id;
    end if;

    update crm.tasks set reminder_sent_at = now() where id = v_task.id;

    perform crm.write_audit(
      v_task.organization_id, 'lead.task_reminder_sent', 'lead', v_task.lead_id::text,
      jsonb_build_object(
        'task_id', v_task.id,
        'channel', case when v_message_id is not null then 'whatsapp' else 'in_app' end,
        'message_id', v_message_id,
        'assigned_to', v_task.assigned_to
      )
    );
  end loop;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.update_task(p_id uuid, p_title text, p_due_at timestamp with time zone, p_assigned_to uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_task crm.tasks;
begin
  select * into v_task from crm.tasks where id = p_id;
  if not found then
    raise exception 'task not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_task.organization_id, 'deals.edit');

  if not crm._lead_visible_to_caller(v_task.lead_id) then
    raise exception 'task not found' using errcode = 'P0002';
  end if;

  update crm.tasks
  set title = trim(p_title), due_at = p_due_at, assigned_to = p_assigned_to,
      -- A changed due date means any already-sent reminder no longer
      -- applies -- let the sweep reconsider it.
      reminder_sent_at = case when p_due_at <> v_task.due_at then null else reminder_sent_at end
  where id = p_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.after_insert_on_organizations()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into crm.organization_profiles (organization_id, slug)
  values (new.id, crm.generate_slug(new.name));

  perform crm.create_preset_roles(new.id);
  perform crm.apply_default_pack(new.id);
  -- [crm] P3-02
  perform crm.seed_lead_catalogs(new.id);
  -- [crm] P3-04: after seed_lead_catalogs, so crm.lead_qualities already
  -- has rows for seed_qualification_scoring to resolve quality_key against.
  perform crm.seed_qualification_scoring(new.id);
  -- [crm] P3-07d
  perform crm.seed_task_reminder_template(new.id);

  return null;
end;
$function$
;

grant select on table "crm"."tasks" to "anon";

grant select on table "crm"."tasks" to "authenticated";

grant delete on table "crm"."tasks" to "service_role";

grant insert on table "crm"."tasks" to "service_role";

grant references on table "crm"."tasks" to "service_role";

grant select on table "crm"."tasks" to "service_role";

grant trigger on table "crm"."tasks" to "service_role";

grant truncate on table "crm"."tasks" to "service_role";

grant update on table "crm"."tasks" to "service_role";


  create policy "members can read tasks on leads they can see"
  on "crm"."tasks"
  as permissive
  for select
  to authenticated, anon
using (((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)) AND crm._lead_visible_to_caller(lead_id)));


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.tasks FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');


