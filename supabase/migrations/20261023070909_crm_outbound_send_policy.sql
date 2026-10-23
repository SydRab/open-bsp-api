
  create table "crm"."contacts_consent" (
    "id" uuid not null default gen_random_uuid(),
    "seq" bigint generated always as identity not null,
    "organization_id" uuid not null,
    "organization_address" text not null,
    "service" public.service not null,
    "address" text not null,
    "status" text not null,
    "source" text not null,
    "keyword_matched" text,
    "note" text,
    "created_at" timestamp with time zone not null default now()
      );


alter table "crm"."contacts_consent" enable row level security;


  create table "crm"."send_rate_buckets" (
    "organization_id" uuid not null,
    "service" public.service not null,
    "organization_address" text not null,
    "tokens" numeric not null,
    "capacity" numeric not null,
    "refill_per_second" numeric not null,
    "updated_at" timestamp with time zone not null default now()
      );


alter table "crm"."send_rate_buckets" enable row level security;

alter table "public"."conversations" add column "last_inbound_at" timestamp with time zone;

CREATE INDEX contacts_consent_lookup_idx ON crm.contacts_consent USING btree (organization_id, organization_address, service, address, seq DESC);

CREATE UNIQUE INDEX contacts_consent_pkey ON crm.contacts_consent USING btree (id);

CREATE UNIQUE INDEX send_rate_buckets_pkey ON crm.send_rate_buckets USING btree (organization_id, service, organization_address);

alter table "crm"."contacts_consent" add constraint "contacts_consent_pkey" PRIMARY KEY using index "contacts_consent_pkey";

alter table "crm"."send_rate_buckets" add constraint "send_rate_buckets_pkey" PRIMARY KEY using index "send_rate_buckets_pkey";

alter table "crm"."contacts_consent" add constraint "contacts_consent_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."contacts_consent" validate constraint "contacts_consent_organization_id_fkey";

alter table "crm"."contacts_consent" add constraint "contacts_consent_source_check" CHECK ((source = ANY (ARRAY['keyword'::text, 'admin'::text, 'signup_default'::text, 'api'::text]))) not valid;

alter table "crm"."contacts_consent" validate constraint "contacts_consent_source_check";

alter table "crm"."contacts_consent" add constraint "contacts_consent_status_check" CHECK ((status = ANY (ARRAY['opted_in'::text, 'opted_out'::text]))) not valid;

alter table "crm"."contacts_consent" validate constraint "contacts_consent_status_check";

alter table "crm"."send_rate_buckets" add constraint "send_rate_buckets_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "crm"."send_rate_buckets" validate constraint "send_rate_buckets_organization_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.count_recent_marketing_sends(p_organization_id uuid, p_organization_address text, p_conversation_address text, p_period_days integer)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select count(*)
  from public.messages m
  join crm.templates t
    on t.organization_id = m.organization_id
   and t.organization_address = m.organization_address
   and t.name = m.content->'data'->>'name'
   and t.language = m.content->'data'->'language'->>'code'
  where m.organization_id = p_organization_id
    and m.organization_address = p_organization_address
    and m.conversation_address = p_conversation_address
    and m.sender_address is null
    and t.category = 'MARKETING'
    and m.status ->> 'failed' is null
    and m.timestamp >= now() - (p_period_days || ' days')::interval;
$function$
;

CREATE OR REPLACE FUNCTION crm.get_consent_status(p_organization_id uuid, p_organization_address text, p_service public.service, p_address text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select status
  from crm.contacts_consent
  where organization_id = p_organization_id
    and organization_address = p_organization_address
    and service = p_service
    and address = p_address
  order by seq desc
  limit 1;
$function$
;

CREATE OR REPLACE FUNCTION crm.record_consent_event(p_organization_id uuid, p_organization_address text, p_service public.service, p_address text, p_status text, p_source text, p_keyword_matched text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into crm.contacts_consent (
    organization_id, organization_address, service, address,
    status, source, keyword_matched, note
  ) values (
    p_organization_id, p_organization_address, p_service, p_address,
    p_status, p_source, p_keyword_matched, p_note
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.try_consume_send_token(p_organization_id uuid, p_service public.service, p_organization_address text, p_capacity numeric, p_refill_per_second numeric, p_cost numeric DEFAULT 1)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tokens numeric;
  v_now timestamp with time zone := now();
begin
  insert into crm.send_rate_buckets (
    organization_id, service, organization_address,
    tokens, capacity, refill_per_second, updated_at
  ) values (
    p_organization_id, p_service, p_organization_address,
    p_capacity, p_capacity, p_refill_per_second, v_now
  )
  on conflict (organization_id, service, organization_address) do nothing;

  select least(
    p_capacity,
    b.tokens + extract(epoch from (v_now - b.updated_at)) * p_refill_per_second
  ) into v_tokens
  from crm.send_rate_buckets b
  where b.organization_id = p_organization_id
    and b.service = p_service
    and b.organization_address = p_organization_address
  for update;

  if v_tokens < p_cost then
    update crm.send_rate_buckets
    set tokens = v_tokens, capacity = p_capacity,
      refill_per_second = p_refill_per_second, updated_at = v_now
    where organization_id = p_organization_id
      and service = p_service
      and organization_address = p_organization_address;
    return false;
  end if;

  update crm.send_rate_buckets
  set tokens = v_tokens - p_cost, capacity = p_capacity,
    refill_per_second = p_refill_per_second, updated_at = v_now
  where organization_id = p_organization_id
    and service = p_service
    and organization_address = p_organization_address;

  return true;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.update_conversation_last_inbound_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.conversations
  set last_inbound_at = new.timestamp
  where id = new.conversation_id
    and (last_inbound_at is null or last_inbound_at < new.timestamp);

  return new;
end;
$function$
;

grant select on table "crm"."contacts_consent" to "anon";

grant select on table "crm"."contacts_consent" to "authenticated";

grant delete on table "crm"."contacts_consent" to "service_role";

grant insert on table "crm"."contacts_consent" to "service_role";

grant references on table "crm"."contacts_consent" to "service_role";

grant select on table "crm"."contacts_consent" to "service_role";

grant trigger on table "crm"."contacts_consent" to "service_role";

grant truncate on table "crm"."contacts_consent" to "service_role";

grant update on table "crm"."contacts_consent" to "service_role";

grant select on table "crm"."send_rate_buckets" to "anon";

grant select on table "crm"."send_rate_buckets" to "authenticated";

grant delete on table "crm"."send_rate_buckets" to "service_role";

grant insert on table "crm"."send_rate_buckets" to "service_role";

grant references on table "crm"."send_rate_buckets" to "service_role";

grant select on table "crm"."send_rate_buckets" to "service_role";

grant trigger on table "crm"."send_rate_buckets" to "service_role";

grant truncate on table "crm"."send_rate_buckets" to "service_role";

grant update on table "crm"."send_rate_buckets" to "service_role";


  create policy "members can read their orgs consent events"
  on "crm"."contacts_consent"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "members can read their orgs send rate buckets"
  on "crm"."send_rate_buckets"
  as permissive
  for select
  to authenticated, anon
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));


CREATE TRIGGER update_conversation_last_inbound_at AFTER INSERT ON public.messages FOR EACH ROW WHEN ((new.sender_address IS NOT NULL)) EXECUTE FUNCTION public.update_conversation_last_inbound_at();


