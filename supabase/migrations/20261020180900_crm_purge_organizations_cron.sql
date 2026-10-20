-- Hard delete (P1-01): once a day, purge organizations whose deletion request
-- is older than the grace period (30 days, crm.deletion_grace_period()).
-- Only organizations an owner explicitly asked to delete are touched, and an
-- owner can cancel at any time before purge_after.
--
-- REVIEW BEFORE MERGE: this job deletes tenant data irreversibly once it is
-- deployed. Drop this file if hard deletion should stay manual for now.
select cron.schedule(
  'crm-purge-deleted-organizations',
  '30 21 * * *', -- 21:30 UTC = 03:00 IST
  $$ select crm.purge_organizations(); $$
);
