-- KaamSetu schema for Supabase. Run in SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  company_name text,
  role text not null default 'job_seeker' check (role in ('job_seeker','company','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 2 and 120),
  company_name text not null check (char_length(company_name) between 2 and 120),
  location text not null check (char_length(location) between 2 and 120),
  job_type text not null check (job_type in ('Full-time','Part-time','Contract','Internship','Remote')),
  salary_range text,
  apply_url text,
  qualification text,
  experience text,
  deadline date,
  description text not null check (char_length(description) between 10 and 8000),
  created_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists jobs_public_feed_idx on public.jobs(status, created_at desc);
create index if not exists jobs_creator_idx on public.jobs(created_by, created_at desc);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles(id, full_name, company_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name',''),
    nullif(new.raw_user_meta_data ->> 'company_name',''),
    'job_seeker'
  ) on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin');
$$;

alter table public.profiles enable row level security;
alter table public.jobs enable row level security;

drop policy if exists "Profiles view self or admin" on public.profiles;
create policy "Profiles view self or admin" on public.profiles for select to authenticated
using (id = auth.uid() or public.is_admin());

drop policy if exists "Users update own non-role profile" on public.profiles;
create policy "Users update own non-role profile" on public.profiles for update to authenticated
using (id = auth.uid() and role <> 'admin')
with check (id = auth.uid() and role = (select p.role from public.profiles p where p.id = auth.uid()));

drop policy if exists "Public read approved jobs" on public.jobs;
create policy "Public read approved jobs" on public.jobs for select
using (status = 'approved' or created_by = auth.uid() or public.is_admin());

drop policy if exists "Company or admin submit job" on public.jobs;
create policy "Company or admin submit job" on public.jobs for insert to authenticated
with check (
  created_by = auth.uid()
  and status = 'pending'
  and exists(select 1 from public.profiles p where p.id = auth.uid() and p.role in ('company','admin'))
);

drop policy if exists "Admin update jobs" on public.jobs;
create policy "Admin update jobs" on public.jobs for update to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Admin delete jobs" on public.jobs;
create policy "Admin delete jobs" on public.jobs for delete to authenticated
using (public.is_admin());

-- IMPORTANT: After you register your own account, replace the email below with yours.
-- Run this statement as project owner in Supabase SQL Editor to make yourself admin:
-- update public.profiles p set role = 'admin'
-- from auth.users u where p.id = u.id and u.email = 'YOUR_EMAIL@example.com';

-- To approve an employer account, first verify their company manually, then run:
-- update public.profiles p set role = 'company'
-- from auth.users u where p.id = u.id and u.email = 'EMPLOYER_EMAIL@example.com';
