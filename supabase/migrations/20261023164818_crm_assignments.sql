
  create table "crm"."conversation_assignments" (
    "conversation_id" uuid not null,
    "organization_id" uuid not null,
    "agent_id" uuid not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."conversation_assignments" enable row level security;

CREATE INDEX conversation_assignments_agent_id_idx ON crm.conversation_assignments USING btree (agent_id);

CREATE INDEX conversation_assignments_organization_id_idx ON crm.conversation_assignments USING btree (organization_id);

CREATE UNIQUE INDEX conversation_assignments_pkey ON crm.conversation_assignments USING btree (conversation_id);

alter table "crm"."conversation_assignments" add constraint "conversation_assignments_pkey" PRIMARY KEY using index "conversation_assignments_pkey";

alter table "crm"."conversation_assignments" add constraint "conversation_assignments_agent_fkey" FOREIGN KEY (organization_id, agent_id) REFERENCES public.agents(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."conversation_assignments" validate constraint "conversation_assignments_agent_fkey";

alter table "crm"."conversation_assignments" add constraint "conversation_assignments_conversation_fkey" FOREIGN KEY (organization_id, conversation_id) REFERENCES public.conversations(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."conversation_assignments" validate constraint "conversation_assignments_conversation_fkey";

alter table "crm"."conversation_assignments" add constraint "conversation_assignments_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."conversation_assignments" validate constraint "conversation_assignments_organization_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.assign_conversation(p_conversation_id uuid, p_agent_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid := (
    select c.organization_id from public.conversations c
    where c.id = p_conversation_id
  );
begin
  perform crm.require_permission(v_org, 'messages.send');

  if not exists (
    select 1 from public.agents a
    where a.id = p_agent_id
      and a.organization_id = v_org
      and a.deleted_at is null
  ) then
    raise exception 'agent not found' using errcode = '22023';
  end if;

  insert into crm.conversation_assignments (organization_id, conversation_id, agent_id)
  values (v_org, p_conversation_id, p_agent_id)
  on conflict (conversation_id) do update set agent_id = excluded.agent_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.unassign_conversation(p_conversation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid := (
    select c.organization_id from public.conversations c
    where c.id = p_conversation_id
  );
begin
  perform crm.require_permission(v_org, 'messages.send');

  delete from crm.conversation_assignments where conversation_id = p_conversation_id;
end;
$function$
;

grant select on table "crm"."conversation_assignments" to "anon";

grant select on table "crm"."conversation_assignments" to "authenticated";

grant delete on table "crm"."conversation_assignments" to "service_role";

grant insert on table "crm"."conversation_assignments" to "service_role";

grant references on table "crm"."conversation_assignments" to "service_role";

grant select on table "crm"."conversation_assignments" to "service_role";

grant trigger on table "crm"."conversation_assignments" to "service_role";

grant truncate on table "crm"."conversation_assignments" to "service_role";

grant update on table "crm"."conversation_assignments" to "service_role";


  create policy "members can read their orgs conversation assignments"
  on "crm"."conversation_assignments"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.conversation_assignments FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');


