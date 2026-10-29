
  create table "crm"."lead_notes" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "lead_id" uuid not null,
    "author_agent_id" uuid not null,
    "body" text not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."lead_notes" enable row level security;

CREATE INDEX lead_notes_lead_id_idx ON crm.lead_notes USING btree (lead_id, created_at DESC);

CREATE UNIQUE INDEX lead_notes_pkey ON crm.lead_notes USING btree (id);

alter table "crm"."lead_notes" add constraint "lead_notes_pkey" PRIMARY KEY using index "lead_notes_pkey";

alter table "crm"."lead_notes" add constraint "lead_notes_author_fkey" FOREIGN KEY (organization_id, author_agent_id) REFERENCES public.agents(organization_id, id) not valid;

alter table "crm"."lead_notes" validate constraint "lead_notes_author_fkey";

alter table "crm"."lead_notes" add constraint "lead_notes_body_check" CHECK (((length(TRIM(BOTH FROM body)) >= 1) AND (length(TRIM(BOTH FROM body)) <= 4000))) not valid;

alter table "crm"."lead_notes" validate constraint "lead_notes_body_check";

alter table "crm"."lead_notes" add constraint "lead_notes_lead_fkey" FOREIGN KEY (lead_id) REFERENCES crm.leads(id) ON DELETE CASCADE not valid;

alter table "crm"."lead_notes" validate constraint "lead_notes_lead_fkey";

alter table "crm"."lead_notes" add constraint "lead_notes_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."lead_notes" validate constraint "lead_notes_organization_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.create_lead_note(p_lead_id uuid, p_body text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org uuid;
  v_self uuid;
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

  v_self := (crm.caller_agent(v_org)).id;

  insert into crm.lead_notes (organization_id, lead_id, author_agent_id, body)
  values (v_org, p_lead_id, v_self, trim(p_body))
  returning id into v_id;

  perform crm.write_audit(
    v_org, 'lead.note_created', 'lead', p_lead_id::text,
    jsonb_build_object('note_id', v_id)
  );

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.delete_lead_note(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_note crm.lead_notes;
begin
  select * into v_note from crm.lead_notes where id = p_id;
  if not found then
    raise exception 'note not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_note.organization_id, 'deals.edit');

  if not crm._lead_visible_to_caller(v_note.lead_id) then
    raise exception 'note not found' using errcode = 'P0002';
  end if;

  delete from crm.lead_notes where id = p_id;

  perform crm.write_audit(
    v_note.organization_id, 'lead.note_deleted', 'lead', v_note.lead_id::text,
    jsonb_build_object('note_id', p_id)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.update_lead_note(p_id uuid, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_note crm.lead_notes;
begin
  select * into v_note from crm.lead_notes where id = p_id;
  if not found then
    raise exception 'note not found' using errcode = 'P0002';
  end if;

  perform crm.require_permission(v_note.organization_id, 'deals.edit');

  if not crm._lead_visible_to_caller(v_note.lead_id) then
    raise exception 'note not found' using errcode = 'P0002';
  end if;

  update crm.lead_notes set body = trim(p_body) where id = p_id;

  perform crm.write_audit(
    v_note.organization_id, 'lead.note_updated', 'lead', v_note.lead_id::text,
    jsonb_build_object('note_id', p_id)
  );
end;
$function$
;

grant select on table "crm"."lead_notes" to "anon";

grant select on table "crm"."lead_notes" to "authenticated";

grant delete on table "crm"."lead_notes" to "service_role";

grant insert on table "crm"."lead_notes" to "service_role";

grant references on table "crm"."lead_notes" to "service_role";

grant select on table "crm"."lead_notes" to "service_role";

grant trigger on table "crm"."lead_notes" to "service_role";

grant truncate on table "crm"."lead_notes" to "service_role";

grant update on table "crm"."lead_notes" to "service_role";


  create policy "members can read notes on leads they can see"
  on "crm"."lead_notes"
  as permissive
  for select
  to authenticated, anon
using (((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)) AND crm._lead_visible_to_caller(lead_id)));


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.lead_notes FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');


