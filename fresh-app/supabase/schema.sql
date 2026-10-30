-- PHOMAB fresh app database setup. Run this entire script in the Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.listings (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 title text not null, area text not null,
 property_type text not null check(property_type in ('house','room','flat','cottage','other')),
 rent numeric(12,2) not null check(rent>0), description text, photo_url text, phone text,
 share_phone boolean not null default false, whatsapp_enabled boolean not null default false,
 status text not null default 'available' check(status in ('available','rented','hidden')),
 created_at timestamptz not null default now()
);
create table if not exists public.jobs (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 title text not null, company text, location text not null, employment_type text,
 description text, contact_phone text, share_phone boolean not null default false,
 status text not null default 'published' check(status in ('published','closed')),
 created_at timestamptz not null default now()
);
create table if not exists public.service_providers (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 name text not null, service_category text not null, location text not null,
 description text, contact_phone text, share_phone boolean not null default false,
 whatsapp_enabled boolean not null default false,
 status text not null default 'published' check(status in ('published','hidden')),
 created_at timestamptz not null default now()
);

alter table public.jobs add column if not exists share_phone boolean not null default false;
alter table public.service_providers add column if not exists share_phone boolean not null default false;

alter table public.listings enable row level security;
alter table public.jobs enable row level security;
alter table public.service_providers enable row level security;

drop policy if exists "Public can view available rentals" on public.listings;
create policy "Public can view available rentals" on public.listings for select to authenticated using(status='available' or owner_id=auth.uid());
drop policy if exists "Owners can add rentals" on public.listings;
create policy "Owners can add rentals" on public.listings for insert to authenticated with check(owner_id=auth.uid());
drop policy if exists "Owners can edit rentals" on public.listings;
create policy "Owners can edit rentals" on public.listings for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
drop policy if exists "Owners can delete rentals" on public.listings;
create policy "Owners can delete rentals" on public.listings for delete to authenticated using(owner_id=auth.uid());

drop policy if exists "Public can view published jobs" on public.jobs;
create policy "Public can view published jobs" on public.jobs for select to authenticated using(status='published' or owner_id=auth.uid());
drop policy if exists "Signed-in users can post jobs" on public.jobs;
create policy "Signed-in users can post jobs" on public.jobs for insert to authenticated with check(owner_id=auth.uid());
drop policy if exists "Owners can manage jobs" on public.jobs;
create policy "Owners can manage jobs" on public.jobs for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
drop policy if exists "Owners can delete jobs" on public.jobs;
create policy "Owners can delete jobs" on public.jobs for delete to authenticated using(owner_id=auth.uid());

drop policy if exists "Public can view published providers" on public.service_providers;
create policy "Public can view published providers" on public.service_providers for select to authenticated using(status='published' or owner_id=auth.uid());
drop policy if exists "Signed-in users can add providers" on public.service_providers;
create policy "Signed-in users can add providers" on public.service_providers for insert to authenticated with check(owner_id=auth.uid());
drop policy if exists "Owners can manage providers" on public.service_providers;
create policy "Owners can manage providers" on public.service_providers for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
drop policy if exists "Owners can delete providers" on public.service_providers;
create policy "Owners can delete providers" on public.service_providers for delete to authenticated using(owner_id=auth.uid());

-- Public views expose contact details only where the owner explicitly consented.
create or replace view public.public_listings as
 select id,title,area,property_type,rent,description,photo_url,
 case when share_phone then phone else null end as phone,
 (share_phone and whatsapp_enabled) as whatsapp_enabled
 from public.listings where status='available';
create or replace view public.public_jobs as
 select id,title,company,location,employment_type,description,
 case when share_phone then contact_phone else null end as contact_phone
 from public.jobs where status='published';
create or replace view public.public_service_providers as
 select id,name,service_category,location,description,
 case when share_phone then contact_phone else null end as contact_phone,
 (share_phone and whatsapp_enabled) as whatsapp_enabled
 from public.service_providers where status='published';

-- Anonymous visitors can read only the safe public views, not private base-table columns.
revoke all on public.listings, public.jobs, public.service_providers from anon;
grant select on public.public_listings, public.public_jobs, public.public_service_providers to anon, authenticated;
grant insert, update, delete on public.listings, public.jobs, public.service_providers to authenticated;

-- Public rental photos. Each signed-in user may upload only into their own folder.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('rental-photos','rental-photos',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "Anyone can view rental photos" on storage.objects;
create policy "Anyone can view rental photos" on storage.objects for select using(bucket_id='rental-photos');
drop policy if exists "Users upload own rental photos" on storage.objects;
create policy "Users upload own rental photos" on storage.objects for insert to authenticated with check(bucket_id='rental-photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Users update own rental photos" on storage.objects;
create policy "Users update own rental photos" on storage.objects for update to authenticated using(bucket_id='rental-photos' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='rental-photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Users delete own rental photos" on storage.objects;
create policy "Users delete own rental photos" on storage.objects for delete to authenticated using(bucket_id='rental-photos' and (storage.foldername(name))[1]=auth.uid()::text);

grant select on public.listings, public.jobs, public.service_providers to authenticated;
