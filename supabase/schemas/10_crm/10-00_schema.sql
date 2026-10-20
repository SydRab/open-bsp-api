-- Our CRM layer lives in its own schema, beside upstream OpenBSP's `public`
-- and `billing` (ADR 0002 §8). The tenant is still public.organizations and
-- every tenant-owned table here carries `organization_id`.
--
-- Exposed to PostgREST (config.toml [api] schemas) so the UI can read it with
-- `supabase.schema("crm")`. Every write that carries an authorization rule
-- goes through a SECURITY DEFINER function in 10-10; tables grant API roles
-- SELECT, plus UPDATE on a few columns where a plain policy is enough.
create schema if not exists crm;

grant usage on schema crm to anon, authenticated, service_role;
