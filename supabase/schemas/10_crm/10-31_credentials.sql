-- Channel credentials (P2-02). The WhatsApp access token lives in Supabase
-- Vault, not in organizations_addresses.extra directly: extra is jsonb with
-- no column-level RLS, so any tenant member with row access to this table
-- could otherwise read a live Meta token straight through PostgREST
-- (CLAUDE.md requires Vault for channel tokens). Only the vault secret's id
-- is stored, in extra.access_token_secret_id.
--
-- WhatsApp-only for now: Slack and Instagram have the same
-- extra.access_token pattern but are out of scope for this phase (see
-- SYSTEM_BLUEPRINT's known gaps) -- scoped by service = 'whatsapp'
-- throughout so a future pass for those channels can follow the same shape.

create function crm.set_whatsapp_access_token(
  p_organization_id uuid,
  p_address text,
  p_access_token text
) returns void
language plpgsql
security definer
set search_path to ''
as $$
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
$$;

create function crm.get_whatsapp_access_token(
  p_organization_id uuid,
  p_address text
) returns text
language sql
security definer
set search_path to ''
as $$
  select s.decrypted_secret
  from public.organizations_addresses a
  join vault.decrypted_secrets s on s.id = (a.extra->>'access_token_secret_id')::uuid
  where a.organization_id = p_organization_id
    and a.service = 'whatsapp'
    and a.address = p_address;
$$;
