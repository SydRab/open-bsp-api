set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.get_my_invitation_roles()
 RETURNS TABLE(invitation_id uuid, role_key text, role_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select ir.invitation_id, r.key, r.name
  from crm.invitation_roles ir
  join public.invitations i on i.id = ir.invitation_id
  join crm.roles r on r.id = ir.role_id
  where i.status = 'pending'
    and lower(i.email) = lower(auth.jwt()->>'email');
$function$
;



-- Hand-written (db diff does not emit EXECUTE changes; mirrors 10-40):
-- new functions are executable by PUBLIC by default.
revoke execute on function crm.get_my_invitation_roles() from public;
grant execute on function crm.get_my_invitation_roles() to authenticated, service_role;
