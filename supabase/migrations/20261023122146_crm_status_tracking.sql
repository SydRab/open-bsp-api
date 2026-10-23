set check_function_bodies = off;

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

CREATE OR REPLACE FUNCTION public.enforce_forward_only_status()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  rank_of jsonb := '{
    "pending": 0,
    "held_for_quality_assessment": 1,
    "accepted": 2,
    "sent": 3,
    "delivered": 4,
    "read": 5
  }'::jsonb;
  highest_rank int := -1;
  new_rank int;
  key text;
begin
  if old.status is null or new.status is null then
    return new;
  end if;

  for key in select jsonb_object_keys(old.status) loop
    if rank_of ? key and (rank_of ->> key)::int > highest_rank then
      highest_rank := (rank_of ->> key)::int;
    end if;
  end loop;

  if new.status ? 'failed' and not (old.status ? 'failed')
    and (old.status ? 'delivered' or old.status ? 'read') then
    new.status := new.status - 'failed';
  end if;

  for key in select jsonb_object_keys(new.status) loop
    new_rank := (rank_of ->> key)::int;

    if new_rank is not null
      and new_rank < highest_rank
      and not (old.status ? key) then
      new.status := new.status - key;
    end if;
  end loop;

  return new;
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

CREATE TRIGGER z_enforce_forward_only_status BEFORE UPDATE ON public.messages FOR EACH ROW WHEN ((new.status IS NOT NULL)) EXECUTE FUNCTION public.enforce_forward_only_status();


