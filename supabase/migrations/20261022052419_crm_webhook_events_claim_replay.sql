set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.claim_webhook_event(p_id uuid)
 RETURNS TABLE(raw_body text, attempts integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  update crm.webhook_events
  set attempts = webhook_events.attempts + 1, last_attempt_at = now()
  where id = p_id and processed_at is null
  returning webhook_events.raw_body, webhook_events.attempts;
$function$
;

CREATE OR REPLACE FUNCTION crm.replay_webhook_event(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  update crm.webhook_events
  set processed_at = null, attempts = 0, processing_error = null, last_attempt_at = null
  where id = p_id;
$function$
;


