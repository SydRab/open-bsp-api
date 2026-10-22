set check_function_bodies = off;

CREATE OR REPLACE FUNCTION crm.get_whatsapp_access_token(p_organization_id uuid, p_address text)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select s.decrypted_secret
  from public.organizations_addresses a
  join vault.decrypted_secrets s on s.id = (a.extra->>'access_token_secret_id')::uuid
  where a.organization_id = p_organization_id
    and a.service = 'whatsapp'
    and a.address = p_address;
$function$
;

CREATE OR REPLACE FUNCTION crm.set_whatsapp_access_token(p_organization_id uuid, p_address text, p_access_token text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_secret_id uuid;
begin
  select (extra->>'access_token_secret_id')::uuid into v_secret_id
  from public.organizations_addresses
  where organization_id = p_organization_id
    and service = 'whatsapp'
    and address = p_address;

  if not found then
    raise exception 'no whatsapp address % for organization %', p_address, p_organization_id
      using errcode = 'P0002';
  end if;

  if v_secret_id is not null then
    perform vault.update_secret(v_secret_id, p_access_token);
  else
    v_secret_id := vault.create_secret(
      p_access_token,
      'whatsapp-access-token:' || p_organization_id::text || ':' || p_address
    );

    update public.organizations_addresses
    set extra = jsonb_build_object('access_token_secret_id', v_secret_id)
    where organization_id = p_organization_id
      and service = 'whatsapp'
      and address = p_address;
  end if;
end;
$function$
;


