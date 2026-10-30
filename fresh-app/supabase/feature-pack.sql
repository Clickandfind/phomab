-- PHOMAB fresh-app feature foundation (security-reviewed).
-- Run AFTER fresh-app/supabase/schema.sql.
-- This script affects only the PHOMAB project database; it does not touch the original website.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 display_name text,
 phone text,
 preferred_language text not null default 'en' check (preferred_language in ('en','sn','nd')),
 account_type text not null default 'individual' check (account_type in ('individual','landlord','employer','service_provider','driver')),
 verified_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists "Profiles visible to signed in users" on public.profiles;
drop policy if exists "Users view own profile" on public.profiles;
create policy "Users view own profile" on public.profiles for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists "Users create own profile" on public.profiles;
create policy "Users create own profile" on public.profiles for insert to authenticated with check (user_id=(select auth.uid()));
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));

-- Users may edit their own contact/display preferences, never their role or verification state.
create or replace function public.phomab_protect_profile_privileges()
returns trigger language plpgsql set search_path = '' as $$
begin
 if new.account_type is distinct from old.account_type
    or new.verified_at is distinct from old.verified_at
    or new.user_id is distinct from old.user_id then
   raise exception 'Account role and verification are managed by PHOMAB administrators';
 end if;
 new.updated_at := now();
 return new;
end;
$$;
drop trigger if exists phomab_profile_privileges_guard on public.profiles;
create trigger phomab_profile_privileges_guard before update on public.profiles
for each row execute function public.phomab_protect_profile_privileges();

create table if not exists public.asks (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 category text not null check (category in ('rental','job','service','ride')),
 request_text text not null check (char_length(request_text) between 1 and 1200),
 language text not null default 'en' check (language in ('en','sn','nd')),
 budget_min numeric(12,2), budget_max numeric(12,2),
 location_text text,
 status text not null default 'open' check (status in ('open','matched','agreed','cancelled','closed')),
 created_at timestamptz not null default now(),
 check (budget_min is null or budget_min >= 0),
 check (budget_max is null or budget_max >= 0),
 check (budget_min is null or budget_max is null or budget_max >= budget_min)
);
alter table public.asks enable row level security;
drop policy if exists "Ask owners and authenticated users can view open asks" on public.asks;
drop policy if exists "Users view own asks" on public.asks;
create policy "Users view own asks" on public.asks for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists "Users create own asks" on public.asks;
create policy "Users create own asks" on public.asks for insert to authenticated with check (user_id=(select auth.uid()));
drop policy if exists "Ask owners update own asks" on public.asks;
create policy "Ask owners update own asks" on public.asks for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
drop policy if exists "Ask owners delete own asks" on public.asks;
create policy "Ask owners delete own asks" on public.asks for delete to authenticated using (user_id=(select auth.uid()));

create table if not exists public.ride_requests (
 id uuid primary key default gen_random_uuid(),
 passenger_id uuid not null references auth.users(id) on delete cascade,
 pickup_text text not null, destination_text text not null,
 pickup_lat double precision, pickup_lng double precision,
 destination_lat double precision, destination_lng double precision,
 proposed_fare numeric(12,2) not null check (proposed_fare>0),
 currency text not null default 'USD',
 passenger_count integer not null default 1 check (passenger_count between 1 and 8),
 vehicle_type text not null default 'any' check (vehicle_type in ('any','private_car','registered_taxi')),
 status text not null default 'open' check (status in ('open','matched','agreed','in_progress','completed','cancelled')),
 created_at timestamptz not null default now()
);
alter table public.ride_requests enable row level security;
drop policy if exists "Passengers and drivers view open rides" on public.ride_requests;
drop policy if exists "Passengers and registered drivers view rides" on public.ride_requests;
create policy "Passengers and verified drivers view rides" on public.ride_requests for select to authenticated using (
 passenger_id=(select auth.uid()) or (
  status='open' and exists(select 1 from public.profiles p
   where p.user_id=(select auth.uid()) and p.account_type='driver' and p.verified_at is not null)
 )
);
drop policy if exists "Passengers create rides" on public.ride_requests;
create policy "Passengers create rides" on public.ride_requests for insert to authenticated with check (passenger_id=(select auth.uid()));
drop policy if exists "Passengers update own rides" on public.ride_requests;
create policy "Passengers update own rides" on public.ride_requests for update to authenticated using (passenger_id=(select auth.uid())) with check (passenger_id=(select auth.uid()));

create table if not exists public.matches (
 id uuid primary key default gen_random_uuid(),
 ask_id uuid not null references public.asks(id) on delete cascade,
 listing_id uuid references public.listings(id) on delete cascade,
 job_id uuid references public.jobs(id) on delete cascade,
 service_provider_id uuid references public.service_providers(id) on delete cascade,
 ride_request_id uuid references public.ride_requests(id) on delete cascade,
 match_score numeric(5,2), match_reason text,
 created_at timestamptz not null default now(),
 check (num_nonnulls(listing_id,job_id,service_provider_id,ride_request_id)=1)
);
alter table public.matches enable row level security;
drop policy if exists "Ask participants can view matches" on public.matches;
create policy "Ask owners view matches" on public.matches for select to authenticated
 using (exists(select 1 from public.asks a where a.id=ask_id and a.user_id=(select auth.uid())));
drop policy if exists "Ask owners manage matches" on public.matches;
create policy "Ask owners save matches" on public.matches for insert to authenticated
 with check (exists(select 1 from public.asks a where a.id=ask_id and a.user_id=(select auth.uid())));
create unique index if not exists phomab_matches_unique_target
 on public.matches(ask_id,coalesce(listing_id,'00000000-0000-0000-0000-000000000000'::uuid),
 coalesce(job_id,'00000000-0000-0000-0000-000000000000'::uuid),
 coalesce(service_provider_id,'00000000-0000-0000-0000-000000000000'::uuid),
 coalesce(ride_request_id,'00000000-0000-0000-0000-000000000000'::uuid));

create table if not exists public.service_bids (
 id uuid primary key default gen_random_uuid(),
 service_provider_id uuid not null references public.service_providers(id) on delete cascade,
 customer_id uuid not null references auth.users(id) on delete cascade,
 ask_id uuid references public.asks(id) on delete set null,
 offer_amount numeric(12,2) not null check (offer_amount>=0),
 currency text not null default 'USD', message text,
 status text not null default 'pending' check (status in ('pending','accepted','rejected','withdrawn')),
 created_at timestamptz not null default now()
);
alter table public.service_bids enable row level security;
drop policy if exists "Bid parties can view bids" on public.service_bids;
create policy "Bid parties can view bids" on public.service_bids for select to authenticated using (
 customer_id=(select auth.uid()) or exists(select 1 from public.service_providers s where s.id=service_provider_id and s.owner_id=(select auth.uid()))
);
drop policy if exists "Customers create bids" on public.service_bids;
create policy "Customers create bids" on public.service_bids for insert to authenticated with check (
 customer_id=(select auth.uid()) and exists(select 1 from public.service_providers s
  where s.id=service_provider_id and s.status='published' and s.owner_id<>(select auth.uid()))
);
drop policy if exists "Bid parties update bids" on public.service_bids;
drop policy if exists "Service owners decide customer bids" on public.service_bids;
create policy "Service owners decide customer bids" on public.service_bids for update to authenticated
 using (exists(select 1 from public.service_providers s where s.id=service_provider_id and s.owner_id=(select auth.uid())))
 with check (exists(select 1 from public.service_providers s where s.id=service_provider_id and s.owner_id=(select auth.uid())));

create table if not exists public.ride_offers (
 id uuid primary key default gen_random_uuid(),
 ride_request_id uuid not null references public.ride_requests(id) on delete cascade,
 driver_id uuid not null references auth.users(id) on delete cascade,
 offered_fare numeric(12,2) not null check (offered_fare>0),
 message text,
 status text not null default 'pending' check (status in ('pending','accepted','rejected','withdrawn')),
 created_at timestamptz not null default now(),
 unique(ride_request_id,driver_id)
);
alter table public.ride_offers enable row level security;
drop policy if exists "Ride parties view offers" on public.ride_offers;
create policy "Ride parties view offers" on public.ride_offers for select to authenticated using (
 driver_id=(select auth.uid()) or exists(select 1 from public.ride_requests r where r.id=ride_request_id and r.passenger_id=(select auth.uid()))
);
drop policy if exists "Drivers create own offers" on public.ride_offers;
drop policy if exists "Registered drivers create offers for open rides" on public.ride_offers;
create policy "Verified drivers offer on open rides" on public.ride_offers for insert to authenticated with check (
 driver_id=(select auth.uid())
 and exists(select 1 from public.profiles p where p.user_id=(select auth.uid()) and p.account_type='driver' and p.verified_at is not null)
 and exists(select 1 from public.ride_requests r where r.id=ride_request_id and r.status='open' and r.passenger_id<>(select auth.uid()))
);
drop policy if exists "Ride parties update offers" on public.ride_offers;
drop policy if exists "Passengers decide driver offers" on public.ride_offers;
create policy "Passengers decide driver offers" on public.ride_offers for update to authenticated
 using (exists(select 1 from public.ride_requests r where r.id=ride_request_id and r.passenger_id=(select auth.uid())))
 with check (exists(select 1 from public.ride_requests r where r.id=ride_request_id and r.passenger_id=(select auth.uid())));

-- Prevent either side from changing the identity, target or price of an existing offer.
create or replace function public.phomab_guard_offer_changes()
returns trigger language plpgsql set search_path = '' as $$
begin
 if tg_table_name='service_bids' then
  if new.id is distinct from old.id or new.service_provider_id is distinct from old.service_provider_id
   or new.customer_id is distinct from old.customer_id or new.ask_id is distinct from old.ask_id
   or new.offer_amount is distinct from old.offer_amount or new.currency is distinct from old.currency
   or new.message is distinct from old.message or new.created_at is distinct from old.created_at then
   raise exception 'Offer details cannot be changed after submission';
  end if;
 else
  if new.id is distinct from old.id or new.ride_request_id is distinct from old.ride_request_id
   or new.driver_id is distinct from old.driver_id or new.offered_fare is distinct from old.offered_fare
   or new.message is distinct from old.message or new.created_at is distinct from old.created_at then
   raise exception 'Ride offer details cannot be changed after submission';
  end if;
 end if;
 return new;
end;
$$;
drop trigger if exists phomab_service_bid_guard on public.service_bids;
create trigger phomab_service_bid_guard before update on public.service_bids for each row execute function public.phomab_guard_offer_changes();
drop trigger if exists phomab_ride_offer_guard on public.ride_offers;
create trigger phomab_ride_offer_guard before update on public.ride_offers for each row execute function public.phomab_guard_offer_changes();

-- Conversations can only be created after a related service or ride offer is accepted.
create table if not exists public.conversations (
 id uuid primary key default gen_random_uuid(),
 ask_id uuid references public.asks(id) on delete set null,
 listing_id uuid references public.listings(id) on delete set null,
 job_id uuid references public.jobs(id) on delete set null,
 service_provider_id uuid references public.service_providers(id) on delete set null,
 ride_request_id uuid references public.ride_requests(id) on delete set null,
 participant_one uuid not null references auth.users(id) on delete cascade,
 participant_two uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 check(participant_one<>participant_two),
 check(num_nonnulls(ask_id,listing_id,job_id,service_provider_id,ride_request_id)<=1)
);
create unique index if not exists conversations_pair_context_idx
 on public.conversations(least(participant_one,participant_two),greatest(participant_one,participant_two),
 coalesce(ask_id,'00000000-0000-0000-0000-000000000000'::uuid),
 coalesce(ride_request_id,'00000000-0000-0000-0000-000000000000'::uuid),
 coalesce(service_provider_id,'00000000-0000-0000-0000-000000000000'::uuid));
alter table public.conversations enable row level security;
drop policy if exists "Participants view conversations" on public.conversations;
create policy "Participants view conversations" on public.conversations for select to authenticated
 using ((select auth.uid()) in (participant_one,participant_two));
drop policy if exists "Participants create conversations" on public.conversations;
create policy "Create conversation after accepted offer" on public.conversations for insert to authenticated with check (
 (select auth.uid()) in (participant_one,participant_two) and participant_one<>participant_two
 and (
  (service_provider_id is not null and exists(select 1 from public.service_bids b join public.service_providers s on s.id=b.service_provider_id
   where b.service_provider_id=conversations.service_provider_id and b.status='accepted'
    and ((b.customer_id=participant_one and s.owner_id=participant_two) or (b.customer_id=participant_two and s.owner_id=participant_one))))
  or
  (ride_request_id is not null and exists(select 1 from public.ride_offers o join public.ride_requests r on r.id=o.ride_request_id
   where o.ride_request_id=conversations.ride_request_id and o.status='accepted'
    and ((o.driver_id=participant_one and r.passenger_id=participant_two) or (o.driver_id=participant_two and r.passenger_id=participant_one))))
 )
);

create table if not exists public.messages (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade,
 body text not null check(char_length(body) between 1 and 2000),
 created_at timestamptz not null default now(),
 read_at timestamptz
);
alter table public.messages enable row level security;
drop policy if exists "Conversation participants read messages" on public.messages;
create policy "Conversation participants read messages" on public.messages for select to authenticated
 using (exists(select 1 from public.conversations c where c.id=conversation_id and (select auth.uid()) in (c.participant_one,c.participant_two)));
drop policy if exists "Participants send own messages" on public.messages;
create policy "Participants send own messages" on public.messages for insert to authenticated
 with check (sender_id=(select auth.uid()) and exists(select 1 from public.conversations c where c.id=conversation_id and (select auth.uid()) in (c.participant_one,c.participant_two)));

create table if not exists public.call_sessions (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 caller_id uuid not null references auth.users(id) on delete cascade,
 callee_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'ringing' check (status in ('ringing','accepted','declined','ended','missed')),
 offer jsonb, answer jsonb, ice_candidates jsonb not null default '[]'::jsonb,
 created_at timestamptz not null default now(), ended_at timestamptz,
 check(caller_id<>callee_id)
);
alter table public.call_sessions enable row level security;
drop policy if exists "Call participants access sessions" on public.call_sessions;
drop policy if exists "Participants read call sessions" on public.call_sessions;
drop policy if exists "Caller starts call sessions" on public.call_sessions;
drop policy if exists "Participants update call sessions" on public.call_sessions;
create policy "Participants read call sessions" on public.call_sessions for select to authenticated
 using ((select auth.uid()) in (caller_id,callee_id) and exists(select 1 from public.conversations c where c.id=conversation_id and (select auth.uid()) in (c.participant_one,c.participant_two)));
create policy "Caller starts call sessions" on public.call_sessions for insert to authenticated
 with check (caller_id=(select auth.uid()) and exists(select 1 from public.conversations c where c.id=conversation_id and (select auth.uid()) in (c.participant_one,c.participant_two) and callee_id in (c.participant_one,c.participant_two)));
create policy "Participants update call sessions" on public.call_sessions for update to authenticated
 using ((select auth.uid()) in (caller_id,callee_id) and exists(select 1 from public.conversations c where c.id=conversation_id and (select auth.uid()) in (c.participant_one,c.participant_two)))
 with check ((select auth.uid()) in (caller_id,callee_id));

create table if not exists public.verification_requests (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 submitted_at timestamptz not null default now(),
 reviewed_at timestamptz, reviewer_note text
);
alter table public.verification_requests enable row level security;
drop policy if exists "Users view own verification requests" on public.verification_requests;
create policy "Users view own verification requests" on public.verification_requests for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists "Users submit own verification request" on public.verification_requests;
create policy "Users submit own verification request" on public.verification_requests for insert to authenticated with check(user_id=(select auth.uid()));

grant select,insert,update,delete on public.profiles,public.asks,public.matches,public.service_bids,public.ride_requests,public.ride_offers,public.conversations,public.messages,public.call_sessions,public.verification_requests to authenticated;
