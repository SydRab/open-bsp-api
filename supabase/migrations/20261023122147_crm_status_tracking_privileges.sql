-- Function privileges for public.apply_message_statuses (P2-08).
-- Hand-written: db diff does not emit EXECUTE changes.

revoke execute on function public.apply_message_statuses(jsonb) from public, anon, authenticated;
grant execute on function public.apply_message_statuses(jsonb) to service_role;
