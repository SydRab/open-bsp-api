-- Brings organizations created before the crm layer into it (P1-01, P1-02,
-- P1-05): a profile with a slug, the eight preset roles, the default pack,
-- and a crm role for every current human member.
--
-- Existing members keep what they could do before: owner → Owner, admin →
-- Admin, member → Sales Rep (upstream members read and answer every
-- conversation and edit contacts, which is what Sales Rep holds). Members who
-- join later by tier alone get Viewer (crm.default_role_key). New
-- organizations get all of this from crm.after_insert_on_organizations.
--
-- Idempotent: every step skips what already exists.

do $backfill$
declare
  v_org record;
begin
  for v_org in
    select o.id, o.name
    from public.organizations o
    where not exists (
      select 1 from crm.organization_profiles p where p.organization_id = o.id
    )
    order by o.created_at
  loop
    insert into crm.organization_profiles (organization_id, slug)
    values (v_org.id, crm.generate_slug(v_org.name));

    perform crm.create_preset_roles(v_org.id);

    if not exists (
      select 1 from crm.organization_packs where organization_id = v_org.id
    ) then
      perform crm.apply_default_pack(v_org.id);
    end if;
  end loop;
end;
$backfill$;

insert into crm.member_roles (agent_id, organization_id, role_id)
select a.id, a.organization_id, r.id
from public.agents a
join crm.roles r
  on r.organization_id = a.organization_id
 and r.key = case a.role
   when 'owner' then 'owner'
   when 'admin' then 'admin'
   else 'sales_rep'
 end
where a.user_id is not null
on conflict (agent_id) do nothing;
