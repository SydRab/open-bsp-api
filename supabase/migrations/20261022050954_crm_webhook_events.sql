
  create table "crm"."webhook_events" (
    "id" uuid not null default gen_random_uuid(),
    "service" public.service not null,
    "dedupe_key" text not null,
    "raw_body" text not null,
    "signature_valid" boolean not null,
    "received_at" timestamp with time zone not null default now(),
    "processed_at" timestamp with time zone,
    "processing_error" text,
    "attempts" integer not null default 0,
    "last_attempt_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."webhook_events" enable row level security;

CREATE INDEX webhook_events_pending_idx ON crm.webhook_events USING btree (service, received_at) WHERE (signature_valid AND (processed_at IS NULL));

CREATE UNIQUE INDEX webhook_events_pkey ON crm.webhook_events USING btree (id);

CREATE UNIQUE INDEX webhook_events_service_dedupe_key_key ON crm.webhook_events USING btree (service, dedupe_key);

alter table "crm"."webhook_events" add constraint "webhook_events_pkey" PRIMARY KEY using index "webhook_events_pkey";

alter table "crm"."webhook_events" add constraint "webhook_events_service_dedupe_key_key" UNIQUE using index "webhook_events_service_dedupe_key_key";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.purge_webhook_events()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  delete from crm.webhook_events where received_at < now() - interval '14 days';
$function$
;

grant select on table "crm"."webhook_events" to "anon";

grant select on table "crm"."webhook_events" to "authenticated";

grant delete on table "crm"."webhook_events" to "service_role";

grant insert on table "crm"."webhook_events" to "service_role";

grant references on table "crm"."webhook_events" to "service_role";

grant select on table "crm"."webhook_events" to "service_role";

grant trigger on table "crm"."webhook_events" to "service_role";

grant truncate on table "crm"."webhook_events" to "service_role";

grant update on table "crm"."webhook_events" to "service_role";


