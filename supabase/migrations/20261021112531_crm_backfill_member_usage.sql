-- Backfills the 'members' usage gauge (P1-09) for organizations that already
-- had members before this migration — otherwise their count would read 0
-- until the next hire or departure nudged it, letting them exceed their
-- tier's seat cap unnoticed. Idempotent (resyncs to the true count if rerun).

insert into billing.usage (organization_id, product_id, interval, period, quantity)
select a.organization_id, 'members', 'lifetime', '1970-01-01', count(*)
from public.agents a
where a.user_id is not null and a.deleted_at is null
group by a.organization_id
on conflict (organization_id, product_id, interval, period) do update
  set quantity = excluded.quantity;
