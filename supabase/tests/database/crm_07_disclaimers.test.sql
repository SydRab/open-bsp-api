-- P1-07: business details and disclaimers. Validation and normalization of
-- business details; versioned disclaimers (limits, history, permissions,
-- isolation, audit); render_with_disclaimer (attach rules, which version,
-- language and fallback, no duplicates, length limit).
begin;
\ir _helpers.psql

select plan(42);

select tests.create_user('owner@test.local');
select tests.create_user('rep@test.local');
select tests.create_user('other.owner@test.local');

select tests.create_org('owner@test.local', 'Golf Academy') as org \gset
select tests.create_org('other.owner@test.local', 'Other Academy') as other \gset
select tests.add_member(:'org', 'rep@test.local', 'sales_rep');

select pack_value->>'en' as pack_short_en from crm.organization_pack_items
where organization_id = :'org' and kind = 'compliance' and item_key = 'disclaimer_short' \gset
select pack_value->>'hi' as pack_short_hi from crm.organization_pack_items
where organization_id = :'org' and kind = 'compliance' and item_key = 'disclaimer_short' \gset
select pack_value->>'en' as pack_full_en from crm.organization_pack_items
where organization_id = :'org' and kind = 'compliance' and item_key = 'disclaimer_full' \gset

-- Business details -------------------------------------------------------------------

select tests.as_user('owner@test.local');
update crm.organization_profiles
set legal_name = ' Golf Trading Academy Pvt Ltd ',
    address = '{"line1": "12 MG Road", "city": "Pune", "state": "Maharashtra", "postal_code": "411001", "country": "IN"}',
    support_email = ' Help@Golf.Example ',
    support_phone = '+91 98765 43210',
    website = 'https://golf.example',
    registrations = '[{"type": "gstin", "number": "27aapfu0939f1zv"}, {"type": "sebi_ra", "number": "INH000012345"}]'
where organization_id = :'org';

select tests.as_postgres();
select results_eq(
  format($$ select legal_name, support_email, registrations from crm.organization_profiles where organization_id = %L $$, :'org'),
  $$ values ('Golf Trading Academy Pvt Ltd'::text, 'help@golf.example'::text,
     '[{"type": "gstin", "number": "27AAPFU0939F1ZV"}, {"type": "sebi_ra", "number": "INH000012345"}]'::jsonb) $$,
  'the owner saves business details, trimmed and normalized'
);

select tests.as_user('owner@test.local');
select throws_ok(
  format($$ update crm.organization_profiles set registrations = '[{"type": "gstin", "number": "27AAPFU0939F1Z"}]' where organization_id = %L $$, :'org'),
  '22023', 'invalid GSTIN number', 'a malformed GSTIN is refused'
);
select throws_ok(
  format($$ update crm.organization_profiles set registrations = '[{"type": "sebi_ra", "number": "INA000012345"}]' where organization_id = %L $$, :'org'),
  '22023', 'invalid SEBI RA number', 'a SEBI RA number must start with INH'
);
select throws_ok(
  format($$ update crm.organization_profiles set registrations = '[{"type": "pan", "number": "ABCDE1234F"}]' where organization_id = %L $$, :'org'),
  '22023', 'registrations[0].type is not one of the allowed values', 'unknown registration types are refused'
);
select throws_ok(
  format($$ update crm.organization_profiles set support_email = 'not-an-email' where organization_id = %L $$, :'org'),
  '22023', 'invalid support email', 'a malformed support email is refused'
);
select throws_ok(
  format($$ update crm.organization_profiles set website = 'golf.example' where organization_id = %L $$, :'org'),
  '22023', 'website must start with http:// or https://', 'a website needs its scheme'
);
select throws_ok(
  format($$ update crm.organization_profiles set address = '{"line1": "x", "planet": "Mars"}' where organization_id = %L $$, :'org'),
  '22023', 'address.planet is not allowed', 'unknown address fields are refused'
);
update crm.organization_profiles set support_phone = '  ' where organization_id = :'org';
select is(
  (select support_phone from crm.organization_profiles where organization_id = :'org'),
  null,
  'a blank field is stored as not given'
);

select tests.as_user('rep@test.local');
update crm.organization_profiles set legal_name = 'Hijacked' where organization_id = :'org';
select tests.as_user('other.owner@test.local');
update crm.organization_profiles set legal_name = 'Hijacked' where organization_id = :'org';
select tests.as_postgres();
select is(
  (select legal_name from crm.organization_profiles where organization_id = :'org'),
  'Golf Trading Academy Pvt Ltd',
  'a sales rep and another tenant cannot change business details'
);
select is(
  (select details->'after'->>'legal_name' from crm.audit_log
   where organization_id = :'org' and action = 'organization.profile_updated'
     and details->'after' ? 'legal_name' order by id limit 1),
  'Golf Trading Academy Pvt Ltd',
  'business detail changes are audited'
);

-- Disclaimers: reading and writing ---------------------------------------------------

select tests.as_user('rep@test.local');
select results_eq(
  format($$ select kind, locale, version, source from crm.get_disclaimers(%L) $$, :'org'),
  $$ values ('short'::text, 'en'::text, 0, 'pack'::text), ('short', 'hi', 0, 'pack'),
            ('full', 'en', 0, 'pack'), ('full', 'hi', 0, 'pack') $$,
  'a new organization uses the pack''s four disclaimers'
);
select is(
  (select text from crm.get_disclaimers(:'org') where kind = 'short' and locale = 'en'),
  :'pack_short_en',
  'with the pack''s text'
);
select throws_ok(
  format($$ select crm.set_disclaimer(%L, 'short', 'en', 'For learning only. No advice.') $$, :'org'),
  '42501', 'permission organization.manage required', 'a sales rep cannot change the disclaimer'
);

select tests.as_user('owner@test.local');
select is(
  crm.set_disclaimer(:'org', 'short', 'en', ' For learning only. Not investment advice. '),
  1,
  'the owner saves version 1'
);
select is(
  crm.set_disclaimer(:'org', 'short', 'en', 'For learning only. Not investment advice.'),
  1,
  'saving the same text adds no version'
);
select is(
  crm.set_disclaimer(:'org', 'short', 'en', 'Education only. Not investment advice.'),
  2,
  'a new text is version 2'
);
select results_eq(
  format($$ select version, text from crm.disclaimer_versions where organization_id = %L and kind = 'short' and locale = 'en' order by version $$, :'org'),
  $$ values (1, 'For learning only. Not investment advice.'::text), (2, 'Education only. Not investment advice.') $$,
  'every version is kept'
);
select results_eq(
  format($$ select text, version, source from crm.get_disclaimers(%L) where kind = 'short' and locale = 'en' $$, :'org'),
  $$ values ('Education only. Not investment advice.'::text, 2, 'tenant'::text) $$,
  'the latest version is in force'
);

select throws_ok(
  format($$ select crm.set_disclaimer(%L, 'short', 'en', %L) $$, :'org', repeat('x', 61)),
  '22023', 'the short disclaimer is 61 characters; the maximum is 60', 'the short version must fit a template footer'
);
select throws_ok(
  format($$ select crm.set_disclaimer(%L, 'short', 'en', E'Education only.\nNo advice.') $$, :'org'),
  '22023', 'the short disclaimer must be one line', 'the short version is one line'
);
select throws_ok(
  format($$ select crm.set_disclaimer(%L, 'full', 'en', 'Hi {{1}}, this is not investment advice at all.') $$, :'org'),
  '22023', 'the disclaimer cannot contain placeholders like {{1}}', 'placeholders are refused'
);
select throws_ok(
  format($$ select crm.set_disclaimer(%L, 'full', 'en', %L) $$, :'org', repeat('y', 1001)),
  '22023', 'the full disclaimer is 1001 characters; the maximum is 1000', 'the full version has a limit'
);
select throws_ok(
  format($$ select crm.set_disclaimer(%L, 'short', 'ta', 'Education only. Not advice.') $$, :'org'),
  '22023', 'unknown language ta', 'only English and Hindi'
);
select throws_ok(
  format($$ insert into crm.disclaimer_versions (organization_id, kind, locale, version, text) values (%L, 'short', 'en', 9, 'Sneaky') $$, :'org'),
  '42501', null, 'nobody writes versions directly'
);

select tests.as_user('other.owner@test.local');
select throws_ok(
  format($$ select crm.set_disclaimer(%L, 'short', 'en', 'Education only. Not advice.') $$, :'org'),
  '42501', 'organization not found', 'another tenant cannot change our disclaimer'
);
select is_empty(
  format('select 1 from crm.disclaimer_versions where organization_id = %L', :'org'),
  'or read our versions'
);

select tests.as_postgres();
select results_eq(
  format($$ select details->>'version', details->>'before', details->>'after' from crm.audit_log where organization_id = %L and action = 'disclaimer.updated' order by id $$, :'org'),
  format($$ values ('1'::text, %L::text, 'For learning only. Not investment advice.'::text),
                   ('2', 'For learning only. Not investment advice.', 'Education only. Not investment advice.') $$, :'pack_short_en'),
  'each version is audited with the text it replaced'
);

-- render_with_disclaimer -------------------------------------------------------------

select tests.as_user('rep@test.local');
select results_eq(
  format($$ select text, attached, disclaimer_kind, disclaimer_locale, disclaimer_version from crm.render_with_disclaimer(%L, 'broadcast', 'New batch starts Monday!') $$, :'org'),
  $$ values (E'New batch starts Monday!\n\nEducation only. Not investment advice.'::text, true, 'short'::text, 'en'::text, 2) $$,
  'a broadcast gets the short disclaimer in force, with its version'
);
select results_eq(
  format($$ select text, attached from crm.render_with_disclaimer(%L, 'receipt', 'Received Rs 5,000. Thank you.') $$, :'org'),
  $$ values ('Received Rs 5,000. Thank you.'::text, false) $$,
  'receipts carry no disclaimer by default (attach rules)'
);
select results_eq(
  format($$ select text, attached from crm.render_with_disclaimer(%L, 'broadcast', E'New batch!\n\nEducation only. Not investment advice.') $$, :'org'),
  $$ values (E'New batch!\n\nEducation only. Not investment advice.'::text, true) $$,
  'a text that already carries the disclaimer is not changed'
);
select results_eq(
  format($$ select disclaimer_kind, disclaimer_version, text like %L from crm.render_with_disclaimer(%L, 'public_page', 'About us') $$, '%' || :'pack_full_en', :'org'),
  $$ values ('full'::text, 0, true) $$,
  'public pages always get the full disclaimer'
);
select results_eq(
  format($$ select disclaimer_locale, text like %L from crm.render_with_disclaimer(%L, 'ai_message', 'नमस्ते', 'hi') $$, '%' || :'pack_short_hi', :'org'),
  $$ values ('hi'::text, true) $$,
  'the Hindi disclaimer for Hindi content'
);
select throws_ok(
  format($$ select * from crm.render_with_disclaimer(%L, 'broadcast', %L) $$, :'org', repeat('z', 4080)),
  '22023', 'the message is too long once the disclaimer is added (4120 of 4096 characters)',
  'a message that no longer fits WhatsApp''s 4096 characters is refused'
);
select throws_ok(
  format($$ select * from crm.render_with_disclaimer(%L, 'chit_chat', 'Hi') $$, :'org'),
  '22023', 'unknown content type chit_chat', 'unknown content types are refused'
);
select throws_ok(
  format($$ select * from crm.render_with_disclaimer(%L, 'broadcast', '  ') $$, :'org'),
  '22023', 'nothing to send', 'empty content is refused'
);

select tests.as_user('owner@test.local');
select crm.set_setting(:'org', 'disclaimer.attach_rules',
  '{"broadcast": true, "digest": true, "ai_message": true, "receipt": true, "payment_confirmation": false}');
select results_eq(
  format($$ select attached, disclaimer_kind from crm.render_with_disclaimer(%L, 'receipt', 'Received Rs 5,000.') $$, :'org'),
  $$ values (true, 'full'::text) $$,
  'turning the receipt rule on attaches the full version to receipts'
);
update crm.organization_profiles set locale = 'hi' where organization_id = :'org';
select is(
  (select disclaimer_locale from crm.render_with_disclaimer(:'org', 'broadcast', 'Hello')),
  'hi',
  'without a language, the organization''s language is used'
);

-- Fallback to English, and no disclaimer at all.
select tests.as_postgres();
update crm.organization_pack_items
set pack_value = jsonb_build_object('en', pack_value->>'en')
where organization_id = :'other' and kind = 'compliance' and item_key = 'disclaimer_short';
update crm.organization_pack_items
set pack_value = '{}'
where organization_id = :'other' and kind = 'compliance' and item_key = 'disclaimer_full';

select tests.as_user('other.owner@test.local');
select is(
  (select disclaimer_locale from crm.render_with_disclaimer(:'other', 'broadcast', 'Hello', 'hi')),
  'en',
  'no Hindi text: English is used'
);
select throws_ok(
  format($$ select * from crm.render_with_disclaimer(%L, 'public_page', 'About us') $$, :'other'),
  '22023', 'the organization has no full disclaimer', 'content is never sent without the disclaimer it needs'
);
select throws_ok(
  format($$ select * from crm.render_with_disclaimer(%L, 'broadcast', 'Hello') $$, :'org'),
  '42501', 'organization not found', 'another tenant cannot render with our disclaimer'
);

select tests.as_postgres();
insert into public.api_keys (organization_id, key, role, name) values (:'org', 'disclaimer-key', 'member', 'k');
select tests.as_api_key('disclaimer-key');
select is(
  (select attached from crm.render_with_disclaimer(:'org', 'broadcast', 'Hello', 'en')),
  true,
  'an API key integration renders with the disclaimer too'
);
select throws_ok(
  format($$ select crm.set_disclaimer(%L, 'short', 'en', 'Education only. Not advice.') $$, :'org'),
  '42501', null, 'but cannot change it'
);

select * from finish();
rollback;
