-- District coverage report (admin only).
-- Shows which districts have data, which are empty, and district-source health.
create or replace function public.admin_district_coverage()
returns jsonb language sql security definer set search_path='' as $fn$
  select case when not public.is_admin() then jsonb_build_object('error','not authorized') else jsonb_build_object(
    'totals', jsonb_build_object(
      'districts', (select count(*) from public.districts),
      'districts_with_jobs', (select count(distinct (state,district)) from public.jobs where district is not null and in_india),
      'district_sources', (select count(*) from public.job_sources where district_hint is not null),
      'sources_ok', (select count(*) from public.job_sources where district_hint is not null and last_status like 'ok:%' and last_status <> 'ok: 0 new, 0 skipped of 0'),
      'sources_failed', (select count(*) from public.job_sources where district_hint is not null and last_status like 'error:%'),
      'sources_never_run', (select count(*) from public.job_sources where district_hint is not null and last_status is null)
    ),
    'by_state', (select coalesce(jsonb_agg(x),'[]'::jsonb) from (
        select jsonb_build_object('state', d.state,
          'districts', count(*)::int,
          'with_jobs', count(*) filter (where j.n is not null)::int,
          'jobs', coalesce(sum(j.n),0)::int) as x
        from public.districts d
        left join (select state, district, count(*) n from public.jobs where district is not null and in_india group by 1,2) j
          on j.state = d.state and j.district = d.name
        group by d.state
        order by d.state) t),
    'top_districts', (select coalesce(jsonb_agg(jsonb_build_object('state',state,'district',district,'jobs',n)),'[]'::jsonb) from (
        select state, district, count(*) n from public.jobs where district is not null and in_india group by 1,2 order by 3 desc limit 15) t),
    'empty_districts', (select coalesce(jsonb_agg(jsonb_build_object('state',d.state,'district',d.name)),'[]'::jsonb) from (
        select d.state, d.name from public.districts d
        where not exists (select 1 from public.jobs jb where jb.district = d.name and jb.state = d.state and jb.in_india)
        order by d.state, d.name limit 80) d)
  ) end;
$fn$;

revoke all on function public.admin_district_coverage() from public, anon;
grant execute on function public.admin_district_coverage() to authenticated;
