-- PHOMAB fresh app schema. Run in Supabase SQL Editor.
create table if not exists public.listings (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 title text not null, area text not null, property_type text not null check(property_type in ('house','room','flat','cottage','other')),
 rent numeric(12,2) not null check(rent>0), description text, photo_url text, phone text,
 share_phone boolean not null default false, whatsapp_enabled boolean not null default false,
 status text not null default 'available' check(status in ('available','rented','hidden')), created_at timestamptz not null default now()
);
create table if not exists public.jobs (
 id uuid primary key default gen_random_uuid(), owner_id uuid references auth.users(id) on delete set null,
 title text not null, company text, location text not null, employment_type text, description text, contact_phone text,
 status text not null default 'published' check(status in ('published','closed')), created_at timestamptz not null default now()
);
create table if not exists public.service_providers (
 id uuid primary key default gen_random_uuid(), owner_id uuid references auth.users(id) on delete set null,
 name text not null, service_category text not null, location text not null, description text, contact_phone text,
 whatsapp_enabled boolean not null default false, status text not null default 'published' check(status in ('published','hidden')), created_at timestamptz not null default now()
);
alter table public.listings enable row level security; alter table public.jobs enable row level security; alter table public.service_providers enable row level security;
drop policy if exists "Public can view available rentals" on public.listings;
create policy "Public can view available rentals" on public.listings for select using(status='available');
drop policy if exists "Owners can add rentals" on public.listings;
create policy "Owners can add rentals" on public.listings for insert to authenticated with check(owner_id=auth.uid());
drop policy if exists "Owners can edit rentals" on public.listings;
create policy "Owners can edit rentals" on public.listings for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
drop policy if exists "Owners can delete rentals" on public.listings;
create policy "Owners can delete rentals" on public.listings for delete to authenticated using(owner_id=auth.uid());
drop policy if exists "Public can view published jobs" on public.jobs;
create policy "Public can view published jobs" on public.jobs for select using(status='published');
drop policy if exists "Signed-in users can post jobs" on public.jobs;
create policy "Signed-in users can post jobs" on public.jobs for insert to authenticated with check(owner_id=auth.uid());
drop policy if exists "Owners can manage jobs" on public.jobs;
create policy "Owners can manage jobs" on public.jobs for all to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
drop policy if exists "Public can view published providers" on public.service_providers;
create policy "Public can view published providers" on public.service_providers for select using(status='published');
drop policy if exists "Signed-in users can add providers" on public.service_providers;
create policy "Signed-in users can add providers" on public.service_providers for insert to authenticated with check(owner_id=auth.uid());
drop policy if exists "Owners can manage providers" on public.service_providers;
create policy "Owners can manage providers" on public.service_providers for all to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
