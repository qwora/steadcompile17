-- Retention: shared cases are kept 30 days (the app only shows the latest 50 anyway), and the
-- rate-limit tables only need the last hour. One nightly pg_cron job does all three.
-- Deleting a case also removes its push_log rows (on delete cascade).

create or replace function public.stead_cleanup()
returns void language sql security definer set search_path = public as $$
  delete from public.cases where created_at < now() - interval '30 days';
  delete from public.join_attempts where created_at < now() - interval '1 day';
  delete from public.ai_calls where created_at < now() - interval '1 day';
$$;
revoke execute on function public.stead_cleanup() from public, anon, authenticated;

create extension if not exists pg_cron;
select cron.schedule('stead-cleanup', '17 3 * * *', 'select public.stead_cleanup()'); -- 03:17 UTC daily

-- Covered by the unique (member_id, device_token) index.
drop index if exists public.device_tokens_member;
