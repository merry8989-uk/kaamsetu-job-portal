-- ============================================================================
-- KaamSetu — complete database schema
-- Generated from the live Supabase project, so a fresh setup matches production.
--
-- Run order:
--   1. supabase-schema.sql      (this file: tables, functions, triggers, policies)
--   2. supabase/seed-reference.sql  (india_places, districts, app_config)
--   3. Seed job_sources with the sources you are allowed to use.
--   4. Deploy the edge function in functions/ingest-feeds.
-- ============================================================================

create extension if not exists pgcrypto;
create extension if not exists pg_cron;
create extension if not exists pg_net;

create table if not exists public.app_config (
  key text not null,
  value text not null
);

create table if not exists public.districts (
  id uuid not null default gen_random_uuid(),
  state text not null,
  name text not null,
  slug text not null,
  nic_url text,
  court_url text
);

create table if not exists public.india_places (
  name text not null,
  state text not null
);

create table if not exists public.job_sources (
  id uuid not null default gen_random_uuid(),
  name text not null,
  url text not null,
  kind text not null default 'rss'::text,
  category text,
  active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  last_run_at timestamp with time zone,
  last_status text,
  state_hint text,
  kind_hint text,
  district_hint text
);

create table if not exists public.jobs (
  id uuid not null default gen_random_uuid(),
  title text not null,
  company_name text not null,
  location text not null,
  job_type text not null,
  salary_range text,
  apply_url text,
  qualification text,
  experience text,
  deadline date,
  description text not null,
  created_by uuid,
  status text not null default 'pending'::text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  device_id text,
  archived_at timestamp with time zone,
  source_name text,
  source_url text,
  sector text,
  state text,
  in_india boolean,
  district text,
  kind text not null default 'job'::text,
  dedup_key text default lower(((((btrim(COALESCE(title, ''::text)) || '|'::text) || btrim(COALESCE(company_name, ''::text))) || '|'::text) || btrim(COALESCE(location, ''::text))))
);

create table if not exists public.logs (
  id bigint not null,
  created_at timestamp with time zone not null default now(),
  severity text not null default 'INFO'::text,
  category text not null,
  message text not null,
  app_id text default 'kaamsetu'::text,
  environment text default 'prod'::text,
  request_id text,
  device_id text,
  path text,
  metadata jsonb
);

create table if not exists public.profiles (
  id uuid not null,
  full_name text not null default ''::text,
  company_name text,
  role text not null default 'job_seeker'::text,
  created_at timestamp with time zone not null default now()
);

alter table public.app_config add constraint app_config_pkey PRIMARY KEY (key);
alter table public.districts add constraint districts_pkey PRIMARY KEY (id);
alter table public.districts add constraint districts_state_name_key UNIQUE (state, name);
alter table public.india_places add constraint india_places_pkey PRIMARY KEY (name);
alter table public.job_sources add constraint job_sources_kind_check CHECK ((kind = ANY (ARRAY['rss'::text, 'json'::text, 'gov'::text])));
alter table public.job_sources add constraint job_sources_pkey PRIMARY KEY (id);
alter table public.jobs add constraint jobs_company_name_check CHECK (((char_length(company_name) >= 2) AND (char_length(company_name) <= 120)));
alter table public.jobs add constraint jobs_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.jobs add constraint jobs_description_check CHECK (((char_length(description) >= 10) AND (char_length(description) <= 8000)));
alter table public.jobs add constraint jobs_job_type_check CHECK ((job_type = ANY (ARRAY['Full-time'::text, 'Part-time'::text, 'Contract'::text, 'Internship'::text, 'Remote'::text])));
alter table public.jobs add constraint jobs_kind_chk CHECK ((kind = ANY (ARRAY['job'::text, 'tender'::text, 'scheme'::text])));
alter table public.jobs add constraint jobs_location_check CHECK (((char_length(location) >= 2) AND (char_length(location) <= 120)));
alter table public.jobs add constraint jobs_pkey PRIMARY KEY (id);
alter table public.jobs add constraint jobs_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
alter table public.jobs add constraint jobs_title_check CHECK (((char_length(title) >= 2) AND (char_length(title) <= 120)));
alter table public.logs add constraint logs_pkey PRIMARY KEY (id);
alter table public.logs add constraint logs_severity_check CHECK ((severity = ANY (ARRAY['TRACE'::text, 'DEBUG'::text, 'INFO'::text, 'WARN'::text, 'ERROR'::text, 'FATAL'::text])));
alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);
alter table public.profiles add constraint profiles_role_check CHECK ((role = ANY (ARRAY['job_seeker'::text, 'company'::text, 'admin'::text])));

CREATE INDEX jobs_sector_idx ON public.jobs USING btree (sector, created_at DESC);
CREATE INDEX jobs_kind_idx ON public.jobs USING btree (kind, created_at DESC);
CREATE INDEX districts_state_idx ON public.districts USING btree (state, name);
CREATE INDEX jobs_india_idx ON public.jobs USING btree (in_india, created_at DESC);
CREATE UNIQUE INDEX job_sources_url_key ON public.job_sources USING btree (url);
CREATE INDEX logs_created_idx ON public.logs USING btree (created_at DESC);
CREATE INDEX jobs_archive_idx ON public.jobs USING btree (archived_at, deadline DESC);
CREATE INDEX logs_sev_idx ON public.logs USING btree (severity, created_at DESC);
CREATE INDEX jobs_creator_idx ON public.jobs USING btree (created_by, created_at DESC);
CREATE INDEX jobs_state_idx ON public.jobs USING btree (state, created_at DESC);
CREATE INDEX jobs_district_idx ON public.jobs USING btree (state, district, created_at DESC);
CREATE INDEX jobs_public_feed_idx ON public.jobs USING btree (status, created_at DESC);
CREATE UNIQUE INDEX jobs_source_url_key ON public.jobs USING btree (source_url);
CREATE UNIQUE INDEX jobs_dedup_key_uniq ON public.jobs USING btree (dedup_key) WHERE (source_url IS NOT NULL);
CREATE INDEX jobs_device_idx ON public.jobs USING btree (device_id, created_at DESC);
CREATE INDEX logs_cat_idx ON public.logs USING btree (category, created_at DESC);
CREATE INDEX jobs_deadline_idx ON public.jobs USING btree (deadline) WHERE (deadline IS NOT NULL);

CREATE OR REPLACE FUNCTION public.admin_set_role(p_id uuid, p_role text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  if p_role not in ('job_seeker','company','admin') then raise exception 'invalid role'; end if;
  update public.profiles set role = p_role where id = p_id;
end;
$function$


CREATE OR REPLACE FUNCTION public.archive_expired_jobs()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with moved as (
    update public.jobs set archived_at = now()
     where archived_at is null
       and (
         (deadline is not null and deadline < current_date)
         or (deadline is null and created_at < now() - interval '60 days')
       )
    returning 1
  ) select count(*)::int from moved;
$function$


CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin');
$function$


CREATE OR REPLACE FUNCTION public.classify_job_sector(p_title text, p_source text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when t ~ 'railway|rrb|locomotive|locopilot' then 'Railway'
    when t ~ 'bank|ibps|\ysbi\y|\yrbi\y|nabard|sebi|probationary officer|\yclerk\y' then 'Banking'
    when t ~ 'upsc|\yssc\y|bpsc|\ypsc\y|civil service|\yias\y|\yips\y|combined graduate' then 'Civil Services'
    when t ~ 'army|navy|air force|defence|defense|drdo|coast guard|territorial army' then 'Defence'
    when t ~ 'police|constable|sub.?inspector|home guard' then 'Police'
    when t ~ 'teacher|teaching|professor|faculty|lecturer|\ytutor\y|educator' then 'Teaching'
    when t ~ 'nurse|nursing|doctor|medical|health|pharmac|hospital|paramedic' then 'Healthcare'
    when t ~ '\yintern|trainee|apprentice' then 'Internship'
    when t ~ 'software|developer|programmer|devops|data scien|machine learning|full.?stack|front.?end|back.?end|cloud|qa engineer|\ysde\y|android|\yios\y' then 'IT & Software'
    when t ~ 'engineer|engineering|technician|mechanical|electrical|maintenance' then 'Engineering'
    when t ~ 'government|govt|sarkari|recruitment|notification|vacanc|advertis|advt|\yexam' then 'Government'
    else 'Private'
  end
  from (select lower(coalesce(p_title,'') || ' ' || coalesce(p_source,'')) as t) s;
$function$


CREATE OR REPLACE FUNCTION public.jobs_set_sector()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.sector is null then
    new.sector := public.classify_job_sector(new.title, new.source_name);
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.is_india_job(p_loc text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select case
    when p_loc is null or btrim(p_loc) = '' then false
    when public.india_state(p_loc) is not null then true
    when lower(p_loc) ~ 'india|anywhere|worldwide|global|work from home|wfh' then true
    else false
  end;
$function$


CREATE OR REPLACE FUNCTION public.jobs_set_geo()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.state := public.india_state(new.location);
  new.district := public.india_district(new.location, new.state);
  new.in_india := public.is_india_job(new.location);
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.india_state(p_loc text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select p.state from public.india_places p
  where p_loc is not null
    and (' ' || regexp_replace(lower(p_loc),'[^a-z0-9]+',' ','g') || ' ')
        like ('% ' || regexp_replace(p.name,'[^a-z0-9]+',' ','g') || ' %')
  order by length(p.name) desc limit 1;
$function$


CREATE OR REPLACE FUNCTION public.india_district(p_loc text, p_state text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(
    (select d.name from public.districts d
      where p_loc is not null
        and (' ' || regexp_replace(lower(p_loc),'[^a-z0-9]+',' ','g') || ' ')
            like ('% ' || regexp_replace(lower(d.name),'[^a-z0-9]+',' ','g') || ' %')
        and d.state = p_state
      order by length(d.name) desc limit 1),
    (select d.name from public.districts d
      where p_loc is not null
        and (' ' || regexp_replace(lower(p_loc),'[^a-z0-9]+',' ','g') || ' ')
            like ('% ' || regexp_replace(lower(d.name),'[^a-z0-9]+',' ','g') || ' %')
      order by length(d.name) desc limit 1)
  );
$function$


CREATE OR REPLACE FUNCTION public.redact(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select coalesce(jsonb_object_agg(k, case when k ~* 'pass|token|secret|authoriz|apikey|api_key|cookie|session' then '"[redacted]"'::jsonb else v end), '{}'::jsonb)
  from jsonb_each(coalesce(p,'{}'::jsonb)) as e(k,v);
$function$


CREATE OR REPLACE FUNCTION public.admin_list_users()
 RETURNS TABLE(id uuid, email text, full_name text, role text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p.id, u.email, p.full_name, p.role, p.created_at
  from public.profiles p join auth.users u on u.id = p.id
  where public.is_admin()
  order by p.created_at desc;
$function$


CREATE OR REPLACE FUNCTION public.audit_profiles()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.role is distinct from old.role then
    insert into public.logs(severity,category,message,app_id,environment,metadata)
    values ('INFO','audit','role_changed','kaamsetu','prod', public.redact(jsonb_build_object('profile_id',new.id,'actor',auth.uid(),'from',old.role,'to',new.role)));
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.purge_old_logs()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with d as (
    delete from public.logs
    where created_at < now() - ((select value from public.app_config where key='log_retention_days') || ' days')::interval
    returning 1
  ) select count(*)::int from d;
$function$


CREATE OR REPLACE FUNCTION public.admin_analytics(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when not public.is_admin() then jsonb_build_object('error','not authorized') else jsonb_build_object(
    'window_days', p_days,
    'total_logs', (select count(*) from public.logs where created_at > now() - (p_days||' days')::interval),
    'active_devices', (select count(distinct device_id) from public.logs where created_at > now() - (p_days||' days')::interval and coalesce(device_id,'') <> ''),
    'errors_24h', (select count(*) from public.logs where severity in ('ERROR','FATAL') and created_at > now() - interval '24 hours'),
    'by_severity', (select coalesce(jsonb_object_agg(severity,c),'{}'::jsonb) from (select severity, count(*) c from public.logs where created_at > now() - (p_days||' days')::interval group by severity) t),
    'by_category', (select coalesce(jsonb_object_agg(category,c),'{}'::jsonb) from (select category, count(*) c from public.logs where created_at > now() - (p_days||' days')::interval group by category) t),
    'top_paths', (select coalesce(jsonb_agg(jsonb_build_object('path',path,'n',c)),'[]'::jsonb) from (select coalesce(path,'(none)') path, count(*) c from public.logs where created_at > now() - (p_days||' days')::interval group by 1 order by 2 desc limit 8) t),
    'top_searches', (select coalesce(jsonb_agg(jsonb_build_object('q',q,'n',c)),'[]'::jsonb) from (select metadata->>'q' q, count(*) c from public.logs where message='search' and metadata->>'q' is not null and created_at > now() - (p_days||' days')::interval group by 1 order by 2 desc limit 10) t),
    'events', (select coalesce(jsonb_object_agg(message,c),'{}'::jsonb) from (select message, count(*) c from public.logs where category in ('activity','security','ui','audit') and created_at > now() - (p_days||' days')::interval group by 1) t)
  ) end;
$function$


CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into public.profiles(id, full_name, company_name, role)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name',''),
          nullif(new.raw_user_meta_data ->> 'company_name',''), 'job_seeker')
  on conflict (id) do nothing;
  insert into public.logs(severity,category,message,app_id,environment,metadata)
  values ('INFO','security','user_registered','kaamsetu','prod',
          public.redact(jsonb_build_object('user_id', new.id, 'email', left(new.email,1) || '***@' || split_part(new.email,'@',2))));
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.audit_jobs()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    insert into public.logs(severity,category,message,app_id,environment,metadata)
    values ('INFO','audit','job_deleted','kaamsetu','prod', public.redact(jsonb_build_object('job_id',old.id,'actor',auth.uid(),'status',old.status)));
    return old;
  elsif tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.logs(severity,category,message,app_id,environment,metadata)
    values ('INFO','audit','job_submitted','kaamsetu','prod', public.redact(jsonb_build_object('job_id',new.id,'by_user',new.created_by,'by_device',new.device_id is not null)));
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    insert into public.logs(severity,category,message,app_id,environment,metadata)
    values ('INFO','audit','job_status_changed','kaamsetu','prod', public.redact(jsonb_build_object('job_id',new.id,'actor',auth.uid(),'from',old.status,'to',new.status)));
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.admin_district_coverage()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.log_event(p_severity text, p_category text, p_message text, p_metadata jsonb DEFAULT '{}'::jsonb, p_device_id text DEFAULT NULL::text, p_path text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_sev text := p_severity;
  v_cat text := p_category;
  v_dev text := coalesce(nullif(p_device_id,''), '');
  v_recent int;
begin
  if v_sev not in ('TRACE','DEBUG','INFO','WARN','ERROR','FATAL') then v_sev := 'INFO'; end if;
  if v_cat not in ('app','error','api','performance','activity','security','ui','diagnostics') then v_cat := 'app'; end if;
  if p_message is null or length(btrim(p_message)) = 0 then return; end if;

  select count(*) into v_recent from public.logs
   where device_id = nullif(v_dev,'') and created_at > now() - interval '1 minute';
  if coalesce(v_recent,0) > 120 then return; end if;

  insert into public.logs(severity,category,message,app_id,environment,request_id,device_id,path,metadata)
  values (v_sev, v_cat, left(btrim(p_message),1000), 'kaamsetu','prod',
          gen_random_uuid()::text, nullif(v_dev,''), left(nullif(p_path,''),200),
          public.redact(coalesce(p_metadata,'{}'::jsonb)));
end;
$function$


CREATE OR REPLACE FUNCTION public.jobs_set_deadline()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.deadline is null then
    new.deadline := public.parse_deadline(coalesce(new.title,'') || ' ' || coalesce(new.description,''));
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.parse_deadline(p_text text)
 RETURNS date
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare
  t text;
  m text[];
  mon text[] := array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
  dd int; mm int; yy int;
begin
  if p_text is null or length(btrim(p_text)) = 0 then return null; end if;
  t := lower(p_text);
  begin
    -- keyword + dd/mm/yyyy
    m := regexp_match(t, '(last date|closing date|due date|last day|deadline|on or before|upto|up to)[^0-9]{0,25}(?<![0-9])(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})');
    if m is not null then
      dd := m[2]::int; mm := m[3]::int; yy := m[4]::int;
      if length(m[4]) = 2 then yy := 2000 + yy; end if;
      if dd between 1 and 31 and mm between 1 and 12 and yy between 2000 and 2100 then return make_date(yy, mm, dd); end if;
    end if;

    -- keyword + dd Mon yyyy
    m := regexp_match(t, '(last date|closing date|due date|deadline|on or before|upto|up to)[^a-z]{0,25}(?<![0-9])(\d{1,2})(st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s+(\d{4})');
    if m is not null then
      dd := m[2]::int; mm := array_position(mon, m[4]); yy := m[5]::int;
      if mm is not null and dd between 1 and 31 and yy between 2000 and 2100 then return make_date(yy, mm, dd); end if;
    end if;

    -- last dd/mm/yyyy in the text
    m := regexp_match(t, '.*(?<![0-9])(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})');
    if m is not null then
      dd := m[1]::int; mm := m[2]::int; yy := m[3]::int;
      if dd between 1 and 31 and mm between 1 and 12 and yy between 2000 and 2100 then return make_date(yy, mm, dd); end if;
    end if;

    -- last dd Mon yyyy in the text
    m := regexp_match(t, '.*(?<![0-9])(\d{1,2})(st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s+(\d{4})');
    if m is not null then
      dd := m[1]::int; mm := array_position(mon, m[3]); yy := m[4]::int;
      if mm is not null and dd between 1 and 31 and yy between 2000 and 2100 then return make_date(yy, mm, dd); end if;
    end if;

    return null;
  exception when others then
    return null;
  end;
end;
$function$


CREATE OR REPLACE FUNCTION public.jobs_rate_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n int;
begin
  if new.created_by is null and new.device_id is not null then
    select count(*) into n from public.jobs
     where device_id = new.device_id and created_by is null
       and created_at > now() - interval '1 hour';
    if n >= 5 then
      raise exception 'Rate limit: ek device se 1 ghante mein sirf 5 vacancy post ki ja sakti hain.';
    end if;
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.admin_source_health()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when not public.is_admin() then jsonb_build_object('error','not authorized') else jsonb_build_object(
    'ok', (select count(*) from public.job_sources where last_status like 'ok:%' and last_status <> 'ok: 0 new, 0 skipped of 0'),
    'empty', (select count(*) from public.job_sources where last_status = 'ok: 0 new, 0 skipped of 0'),
    'failed', (select count(*) from public.job_sources where last_status like 'error:%'),
    'never', (select count(*) from public.job_sources where last_status is null),
    'failing', (select coalesce(jsonb_agg(jsonb_build_object('name',name,'status',left(last_status,90))),'[]'::jsonb) from (
        select name, last_status from public.job_sources where last_status like 'error:%' order by name limit 80) t)
  ) end;
$function$


CREATE TRIGGER jobs_set_sector_trg BEFORE INSERT OR UPDATE ON public.jobs FOR EACH ROW EXECUTE FUNCTION jobs_set_sector();
CREATE TRIGGER jobs_set_geo_trg BEFORE INSERT OR UPDATE OF location ON public.jobs FOR EACH ROW EXECUTE FUNCTION jobs_set_geo();
CREATE TRIGGER profiles_audit_trg AFTER UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION audit_profiles();
CREATE TRIGGER jobs_rate_limit_trg BEFORE INSERT ON public.jobs FOR EACH ROW EXECUTE FUNCTION jobs_rate_limit();
CREATE TRIGGER jobs_set_deadline_trg BEFORE INSERT ON public.jobs FOR EACH ROW EXECUTE FUNCTION jobs_set_deadline();
CREATE TRIGGER jobs_audit_trg AFTER INSERT OR DELETE OR UPDATE ON public.jobs FOR EACH ROW EXECUTE FUNCTION audit_jobs();

alter table public.profiles enable row level security;
alter table public.jobs enable row level security;
alter table public.app_config enable row level security;
alter table public.job_sources enable row level security;
alter table public.logs enable row level security;

create policy "Admin update profiles" on public.profiles for update to authenticated using (is_admin()) with check (is_admin());
create policy "Users update own non-role profile" on public.profiles for update to authenticated using (((id = auth.uid()) AND (role <> 'admin'::text))) with check (((id = auth.uid()) AND (role = ( SELECT p.role
   FROM profiles p
  WHERE (p.id = auth.uid())))));
create policy "Profiles view self or admin" on public.profiles for select to authenticated using (((id = auth.uid()) OR is_admin()));
create policy "Anon delete own device jobs" on public.jobs for delete to anon using (((status = 'pending'::text) AND (device_id = COALESCE(((current_setting('request.headers'::text, true))::json ->> 'x-device-id'::text), ''::text))));
create policy "Anon read own device jobs" on public.jobs for select to anon using ((device_id = COALESCE(((current_setting('request.headers'::text, true))::json ->> 'x-device-id'::text), ''::text)));
create policy "Anonymous submit job" on public.jobs for insert to anon with check (((status = 'pending'::text) AND (created_by IS NULL) AND (device_id = COALESCE(((current_setting('request.headers'::text, true))::json ->> 'x-device-id'::text), ''::text))));
create policy "Admin delete jobs" on public.jobs for delete to authenticated using (is_admin());
create policy "Admin update jobs" on public.jobs for update to authenticated using (is_admin()) with check (is_admin());
create policy "Company or admin submit job" on public.jobs for insert to authenticated with check (((created_by = auth.uid()) AND (status = 'pending'::text) AND (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['company'::text, 'admin'::text])))))));
create policy "Public read approved jobs" on public.jobs for select to public using (((status = 'approved'::text) OR (created_by = auth.uid()) OR is_admin()));
create policy "Public read active sources" on public.job_sources for select to public using (active);
create policy "Admins manage sources" on public.job_sources for all to authenticated using (is_admin()) with check (is_admin());
create policy "Admins delete logs" on public.logs for delete to authenticated using (is_admin());
create policy "Admins read logs" on public.logs for select to authenticated using (is_admin());


-- ============================================================================
-- Privileges
-- Supabase grants anon/authenticated access to public tables by default; RLS is
-- the gate. The one deliberate exception is logs: clients must go through the
-- validated log_event() RPC instead of inserting directly.
-- ============================================================================
revoke insert on public.logs from anon, authenticated;
grant select, delete on public.logs to authenticated;

revoke all on function public.log_event(text,text,text,jsonb,text,text) from public;
grant execute on function public.log_event(text,text,text,jsonb,text,text) to anon, authenticated;
revoke all on function public.admin_analytics(int) from public, anon;
grant execute on function public.admin_analytics(int) to authenticated;
revoke all on function public.admin_district_coverage() from public, anon;
grant execute on function public.admin_district_coverage() to authenticated;
revoke all on function public.admin_source_health() from public, anon;
grant execute on function public.admin_source_health() to authenticated;
revoke all on function public.admin_list_users() from public, anon;
grant execute on function public.admin_list_users() to authenticated;
revoke all on function public.admin_set_role(uuid, text) from public, anon;
grant execute on function public.admin_set_role(uuid, text) to authenticated;

-- ============================================================================
-- Scheduled jobs (pg_cron)
-- ============================================================================
select cron.schedule('archive-expired-jobs-daily', '15 1 * * *', 'select public.archive_expired_jobs();');
select cron.schedule('purge-old-logs', '30 2 * * *', 'select public.purge_old_logs();');

-- Hourly feed ingestion. Replace <PROJECT_REF> with your project ref; the secret
-- is read from app_config so it never appears in the schedule text.
select cron.schedule('ingest-feeds-daily', '0 * * * *', $job$
  select net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/ingest-feeds',
    headers := jsonb_build_object('Content-Type','application/json',
                                  'x-ingest-key',(select value from public.app_config where key='ingest_key')),
    body := '{"limit":120}'::jsonb,
    timeout_milliseconds := 120000
  );
$job$);

-- ============================================================================
-- Notes
--  * Jobs, tenders and schemes are separated by jobs.kind ('job'|'tender'|'scheme').
--  * The portal is India-only: the public feed filters in_india = true.
--  * geo (state/district/in_india), sector, deadline and dedup_key are all set by
--    BEFORE-INSERT triggers, so every write path stays consistent.
--  * Commercial job portals must never be scraped or re-published; only add
--    sources you are allowed to use (feeds, official notice pages).
-- ============================================================================
