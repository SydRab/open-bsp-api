
  create table "crm"."canned_replies" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "name" text not null,
    "content" text not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."canned_replies" enable row level security;

CREATE INDEX canned_replies_organization_id_idx ON crm.canned_replies USING btree (organization_id);

CREATE UNIQUE INDEX canned_replies_organization_id_name_key ON crm.canned_replies USING btree (organization_id, name);

CREATE UNIQUE INDEX canned_replies_pkey ON crm.canned_replies USING btree (id);

alter table "crm"."canned_replies" add constraint "canned_replies_pkey" PRIMARY KEY using index "canned_replies_pkey";

alter table "crm"."canned_replies" add constraint "canned_replies_content_check" CHECK (((length(TRIM(BOTH FROM content)) >= 1) AND (length(TRIM(BOTH FROM content)) <= 4096))) not valid;

alter table "crm"."canned_replies" validate constraint "canned_replies_content_check";

alter table "crm"."canned_replies" add constraint "canned_replies_name_check" CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 80))) not valid;

alter table "crm"."canned_replies" validate constraint "canned_replies_name_check";

alter table "crm"."canned_replies" add constraint "canned_replies_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."canned_replies" validate constraint "canned_replies_organization_id_fkey";

alter table "crm"."canned_replies" add constraint "canned_replies_organization_id_name_key" UNIQUE using index "canned_replies_organization_id_name_key";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.create_canned_reply(p_organization_id uuid, p_name text, p_content text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
begin
  perform crm.require_permission(p_organization_id, 'templates.manage');

  insert into crm.canned_replies (organization_id, name, content)
  values (p_organization_id, trim(p_name), trim(p_content))
  returning id into v_id;

  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.delete_canned_reply(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select r.organization_id from crm.canned_replies r where r.id = p_id),
    'templates.manage'
  );

  delete from crm.canned_replies where id = p_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.update_canned_reply(p_id uuid, p_name text, p_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform crm.require_permission(
    (select r.organization_id from crm.canned_replies r where r.id = p_id),
    'templates.manage'
  );

  update crm.canned_replies
  set name = trim(p_name), content = trim(p_content)
  where id = p_id;
end;
$function$
;

grant select on table "crm"."canned_replies" to "anon";

grant select on table "crm"."canned_replies" to "authenticated";

grant delete on table "crm"."canned_replies" to "service_role";

grant insert on table "crm"."canned_replies" to "service_role";

grant references on table "crm"."canned_replies" to "service_role";

grant select on table "crm"."canned_replies" to "service_role";

grant trigger on table "crm"."canned_replies" to "service_role";

grant truncate on table "crm"."canned_replies" to "service_role";

grant update on table "crm"."canned_replies" to "service_role";


  create policy "members can read their orgs canned replies"
  on "crm"."canned_replies"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.canned_replies FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');


