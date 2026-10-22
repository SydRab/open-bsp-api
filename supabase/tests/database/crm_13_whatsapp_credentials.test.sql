-- P2-02: crm.set_whatsapp_access_token / crm.get_whatsapp_access_token.
-- The WhatsApp token lives in Supabase Vault -- organizations_addresses.extra
-- keeps only the secret id -- so this is the one place that should ever see
-- the plaintext token.
begin;
\ir _helpers.psql

select plan(16);

select tests.create_user('owner@test.local') as owner_user \gset
select tests.create_user('other.owner@test.local') as other_user \gset
select tests.create_org('owner@test.local', 'Jupiter Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset

select tests.as_postgres();
insert into public.organizations_addresses (organization_id, service, address, status)
values (:'org', 'whatsapp', 'phone-1', 'connected');

-- Who can call these functions directly ----------------------------------------------

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ select crm.set_whatsapp_access_token(%L, 'phone-1', 'leaked-token') $$, :'org'),
  '42501', null, 'a tenant owner cannot set the token directly (no EXECUTE grant, not even their own)'
);
select throws_ok(
  format($$ select crm.get_whatsapp_access_token(%L, 'phone-1') $$, :'org'),
  '42501', null, 'nor read it'
);

select tests.as_api_key('some-key');
select throws_ok(
  format($$ select crm.get_whatsapp_access_token(%L, 'phone-1') $$, :'org'),
  '42501', null, 'an API key cannot read it either'
);

-- Setting and reading it, as service_role ---------------------------------------------

select tests.as_service();
select is(
  (select extra->>'access_token_secret_id' from public.organizations_addresses
    where organization_id = :'org' and address = 'phone-1'),
  null,
  'no secret id yet, before the first set'
);

select crm.set_whatsapp_access_token(:'org', 'phone-1', 'token-v1');
select ok(
  (select extra->>'access_token_secret_id' from public.organizations_addresses
    where organization_id = :'org' and address = 'phone-1') is not null,
  'a vault secret id is recorded after the first set'
);
select is(
  (select extra->'access_token' from public.organizations_addresses
    where organization_id = :'org' and address = 'phone-1'),
  null,
  'the plaintext token is never written to extra'
);
select is(
  crm.get_whatsapp_access_token(:'org', 'phone-1'),
  'token-v1',
  'get_whatsapp_access_token decrypts it back out'
);

select (extra->>'access_token_secret_id')::uuid as secret_id
from public.organizations_addresses where organization_id = :'org' and address = 'phone-1' \gset

-- Reconnecting (setting it again) reuses the same vault secret -----------------------

select crm.set_whatsapp_access_token(:'org', 'phone-1', 'token-v2');
select is(
  (select (extra->>'access_token_secret_id')::uuid from public.organizations_addresses
    where organization_id = :'org' and address = 'phone-1'),
  :'secret_id',
  'reconnecting updates the same vault secret rather than creating a new one'
);
select is(
  crm.get_whatsapp_access_token(:'org', 'phone-1'),
  'token-v2',
  'and the decrypted value reflects the update'
);
select is(
  (select count(*)::int from vault.secrets where id = :'secret_id'),
  1,
  'still exactly one vault row for this address, not an orphaned second one'
);

-- Edge cases ----------------------------------------------------------------------------

select is(
  crm.get_whatsapp_access_token(:'org', 'no-such-phone'),
  null,
  'reading a token for an address that was never connected returns null, not an error'
);
select throws_ok(
  format($$ select crm.set_whatsapp_access_token(%L, 'no-such-phone', 'x') $$, :'org'),
  'P0002', null, 'setting a token for an address that does not exist is refused'
);
select is(
  crm.get_whatsapp_access_token(:'other', 'phone-1'),
  null,
  'another organization cannot read this token by guessing the address (scoped by organization_id too)'
);

-- Grant surface ---------------------------------------------------------------------------

select is_empty(
  $$ select 1 from information_schema.routine_privileges
     where routine_schema = 'crm' and routine_name = 'set_whatsapp_access_token' and grantee = 'authenticated' $$,
  'set_whatsapp_access_token is not granted to authenticated'
);
select is_empty(
  $$ select 1 from information_schema.routine_privileges
     where routine_schema = 'crm' and routine_name = 'get_whatsapp_access_token' and grantee in ('authenticated', 'anon') $$,
  'nor get_whatsapp_access_token, to authenticated or anon'
);
select is(
  (select bool_and(privilege_type = 'EXECUTE') from information_schema.routine_privileges
    where routine_schema = 'crm' and routine_name = 'get_whatsapp_access_token' and grantee = 'service_role'),
  true,
  'only service_role can execute it'
);

select * from finish();
rollback;
