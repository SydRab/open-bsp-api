
  create table "crm"."templates" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "organization_address" text not null,
    "meta_id" text,
    "name" text not null,
    "category" text not null,
    "language" text not null,
    "status" text not null default 'PENDING'::text,
    "quality_score" text,
    "components" jsonb not null,
    "rejection_reason" text,
    "pack_item_key" text,
    "synced_at" timestamp with time zone not null default now(),
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."templates" enable row level security;

CREATE INDEX templates_meta_id_idx ON crm.templates USING btree (meta_id) WHERE (meta_id IS NOT NULL);

CREATE UNIQUE INDEX templates_org_address_name_language_key ON crm.templates USING btree (organization_id, organization_address, name, language);

CREATE UNIQUE INDEX templates_pkey ON crm.templates USING btree (id);

alter table "crm"."templates" add constraint "templates_pkey" PRIMARY KEY using index "templates_pkey";

alter table "crm"."templates" add constraint "templates_category_check" CHECK ((category = ANY (ARRAY['MARKETING'::text, 'UTILITY'::text]))) not valid;

alter table "crm"."templates" validate constraint "templates_category_check";

alter table "crm"."templates" add constraint "templates_org_address_name_language_key" UNIQUE using index "templates_org_address_name_language_key";

alter table "crm"."templates" add constraint "templates_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."templates" validate constraint "templates_organization_id_fkey";

grant select on table "crm"."templates" to "anon";

grant select on table "crm"."templates" to "authenticated";

grant delete on table "crm"."templates" to "service_role";

grant insert on table "crm"."templates" to "service_role";

grant references on table "crm"."templates" to "service_role";

grant select on table "crm"."templates" to "service_role";

grant trigger on table "crm"."templates" to "service_role";

grant truncate on table "crm"."templates" to "service_role";

grant update on table "crm"."templates" to "service_role";


  create policy "members can read their orgs templates"
  on "crm"."templates"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));


CREATE TRIGGER set_updated_at BEFORE UPDATE ON crm.templates FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');


