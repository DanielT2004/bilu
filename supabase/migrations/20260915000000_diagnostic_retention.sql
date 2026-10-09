-- Keep first-party MetricKit payloads only for the period disclosed in the
-- privacy policy. Supabase Cron uses pg_cron and runs this cleanup in UTC.

create extension if not exists pg_cron with schema pg_catalog;

select cron.unschedule(jobid)
from cron.job
where jobname = 'purge-bilu-diagnostics';

select cron.schedule(
  'purge-bilu-diagnostics',
  '17 3 * * *',
  $$
    delete from public.app_diagnostics
    where received_at < now() - interval '30 days';

    delete from public.app_diagnostic_daily_limits
    where bucket_date < current_date - 31;
  $$
);
