
  create table "crm"."conversation_tags" (
    "conversation_id" uuid not null,
    "tag_id" uuid not null,
    "organization_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."conversation_tags" enable row level security;


  create table "crm"."tags" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "name" text not null,
    "color" text not null default 'gray'::text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."tags" enable row level security;

CREATE INDEX conversation_tags_organization_id_idx ON crm.conversation_tags USING btree (organization_id);

CREATE UNIQUE INDEX conversation_tags_pkey ON crm.conversation_tags USING btree (conversation_id, tag_id);

CREATE INDEX conversation_tags_tag_id_idx ON crm.conversation_tags USING btree (tag_id);

CREATE UNIQUE INDEX tags_organization_id_id_key ON crm.tags USING btree (organization_id, id);

CREATE UNIQUE INDEX tags_organization_id_name_key ON crm.tags USING btree (organization_id, name);

CREATE UNIQUE INDEX tags_pkey ON crm.tags USING btree (id);

alter table "crm"."conversation_tags" add constraint "conversation_tags_pkey" PRIMARY KEY using index "conversation_tags_pkey";

alter table "crm"."tags" add constraint "tags_pkey" PRIMARY KEY using index "tags_pkey";

alter table "crm"."conversation_tags" add constraint "conversation_tags_conversation_fkey" FOREIGN KEY (organization_id, conversation_id) REFERENCES public.conversations(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."conversation_tags" validate constraint "conversation_tags_conversation_fkey";

alter table "crm"."conversation_tags" add constraint "conversation_tags_tag_fkey" FOREIGN KEY (organization_id, tag_id) REFERENCES crm.tags(organization_id, id) ON DELETE CASCADE not valid;

alter table "crm"."conversation_tags" validate constraint "conversation_tags_tag_fkey";

alter table "crm"."tags" add constraint "tags_color_check" CHECK ((color = ANY (ARRAY['red'::text, 'orange'::text, 'yellow'::text, 'green'::text, 'blue'::text, 'purple'::text, 'gray'::text]))) not valid;

alter table "crm"."tags" validate constraint "tags_color_check";

alter table "crm"."tags" add constraint "tags_name_check" CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 40))) not valid;

alter table "crm"."tags" validate constraint "tags_name_check";

alter table "crm"."tags" add constraint "tags_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."tags" validate constraint "tags_organization_id_fkey";

alter table "crm"."tags" add constraint "tags_organization_id_id_key" UNIQUE using index "tags_organization_id_id_key";

alter table "crm"."tags" add constraint "tags_organization_id_name_key" UNIQUE using index "tags_organization_id_name_key";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.create_tag(p_organization_id uuid, p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'conversations.view');

  insert into crm.tags (organization_id, name)
  values (p_organization_id, trim(p_name))
  returning id into v_id;

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.delete_tag(p_tag_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select t.organization_id from crm.tags t where t.id = p_tag_id),
    'conversations.view'
  );

  delete from crm.tags where id = p_tag_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.rename_tag(p_tag_id uuid, p_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select t.organization_id from crm.tags t where t.id = p_tag_id),
    'conversations.view'
  );

  update crm.tags set name = trim(p_name) where id = p_tag_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_conversation_tag(p_conversation_id uuid, p_tag_id uuid, p_tagged boolean)
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
  perform crm.require_permission(v_org, 'conversations.view');

  if not p_tagged then
    delete from crm.conversation_tags
    where conversation_id = p_conversation_id and tag_id = p_tag_id;
    return;
  end if;

  if not exists (
    select 1 from crm.tags t
    where t.id = p_tag_id and t.organization_id = v_org
  ) then
    raise exception 'tag not found' using errcode = '22023';
  end if;

  insert into crm.conversation_tags (organization_id, conversation_id, tag_id)
  values (v_org, p_conversation_id, p_tag_id)
  on conflict do nothing;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_tag_color(p_tag_id uuid, p_color text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select t.organization_id from crm.tags t where t.id = p_tag_id),
    'conversations.view'
  );

  update crm.tags set color = p_color where id = p_tag_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.apply_message_statuses(p_statuses jsonb)
 RETURNS SETOF text
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  update public.messages m
  set status = u.status_patch
  from (
    select
      (elem ->> 'external_id') as ext_id,
      (elem -> 'status') as status_patch
    from jsonb_array_elements(p_statuses) as elem
  ) u
  where m.external_id = u.ext_id
  returning m.external_id;
$function$
;

grant select on table "crm"."conversation_tags" to "anon";

grant select on table "crm"."conversation_tags" to "authenticated";

grant delete on table "crm"."conversation_tags" to "service_role";

grant insert on table "crm"."conversation_tags" to "service_role";

grant references on table "crm"."conversation_tags" to "service_role";

grant select on table "crm"."conversation_tags" to "service_role";

grant trigger on table "crm"."conversation_tags" to "service_role";

grant truncate on table "crm"."conversation_tags" to "service_role";

grant update on table "crm"."conversation_tags" to "service_role";

grant select on table "crm"."tags" to "anon";

grant select on table "crm"."tags" to "authenticated";

grant delete on table "crm"."tags" to "service_role";

grant insert on table "crm"."tags" to "service_role";

grant references on table "crm"."tags" to "service_role";

grant select on table "crm"."tags" to "service_role";

grant trigger on table "crm"."tags" to "service_role";

grant truncate on table "crm"."tags" to "service_role";

grant update on table "crm"."tags" to "service_role";


  create policy "members can read their orgs conversation tags"
  on "crm"."conversation_tags"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "members can read their orgs tags"
  on "crm"."tags"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.tags FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');


