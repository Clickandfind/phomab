-- PHOMAB feature foundation: ASK / MATCH / AGREE, rides, offers, chat, language and verification.
-- Run AFTER schema.sql in the Supabase SQL Editor.
create extension if not exists pgcrypto;

-- User profile and language preferences.
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
create policy "Users view own profile" on public.profiles for select to authenticated using (user_id=auth.uid());
drop policy if exists "Users create own profile" on public.profiles;
create policy "Users create own profile" on public.profiles for insert to authenticated with check (user_id=auth.uid());
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());

-- ASK: a structured request in the user's own words, optionally by voice transcription.
create table if not exists public.asks (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 category text not null check (category in ('rental','job','service','ride')),
 request_text text not null,
 language text not null default 'en' check (language in ('en','sn','nd')),
 budget_min numeric(12,2),
 budget_max numeric(12,2),
 location_text text,
 status text not null default 'open' check (status in ('open','matched','agreed','cancelled','closed')),
 created_at timestamptz not null default now()
);
alter table public.asks enable row level security;
drop policy if exists "Ask owners and authenticated users can view open asks" on public.asks;
create policy "Ask owners and authenticated users can view open asks" on public.asks for select to authenticated using (user_id=auth.uid() or status='open');
drop policy if exists "Users create own asks" on public.asks;
create policy "Users create own asks" on public.asks for insert to authenticated with check (user_id=auth.uid());
drop policy if exists "Ask owners update own asks" on public.asks;
create policy "Ask owners update own asks" on public.asks for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
drop policy if exists "Ask owners delete own asks" on public.asks;
create policy "Ask owners delete own asks" on public.asks for delete to authenticated using (user_id=auth.uid());

-- MATCH: saved matches connect an ask to an offer/listing and can be scored by the app.
create table if not exists public.matches (
 id uuid primary key default gen_random_uuid(),
 ask_id uuid not null references public.asks(id) on delete cascade,
 listing_id uuid references public.listings(id) on delete cascade,
 job_id uuid references public.jobs(id) on delete cascade,
 service_provider_id uuid references public.service_providers(id) on delete cascade,
 ride_request_id uuid,
 match_score numeric(5,2),
 match_reason text,
 created_at timestamptz not null default now(),
 check (num_nonnulls(listing_id,job_id,service_provider_id,ride_request_id)=1)
);
alter table public.matches enable row level security;
drop policy if exists "Ask participants can view matches" on public.matches;
create policy "Ask participants can view matches" on public.matches for select to authenticated
 using (exists(select 1 from public.asks a where a.id=ask_id and a.user_id=auth.uid()));
drop policy if exists "Ask owners manage matches" on public.matches;
create policy "Ask owners manage matches" on public.matches for all to authenticated
 using (exists(select 1 from public.asks a where a.id=ask_id and a.user_id=auth.uid()))
 with check (exists(select 1 from public.asks a where a.id=ask_id and a.user_id=auth.uid()));

-- Service-provider bids and customer offers.
create table if not exists public.service_bids (
 id uuid primary key default gen_random_uuid(),
 service_provider_id uuid not null references public.service_providers(id) on delete cascade,
 customer_id uuid not null references auth.users(id) on delete cascade,
 ask_id uuid references public.asks(id) on delete set null,
 offer_amount numeric(12,2) not null check (offer_amount>=0),
 currency text not null default 'USD',
 message text,
 status text not null default 'pending' check (status in ('pending','accepted','rejected','withdrawn')),
 created_at timestamptz not null default now()
);
alter table public.service_bids enable row level security;
drop policy if exists "Bid parties can view bids" on public.service_bids;
create policy "Bid parties can view bids" on public.service_bids for select to authenticated
 using (customer_id=auth.uid() or exists(select 1 from public.service_providers s where s.id=service_provider_id and s.owner_id=auth.uid()));
drop policy if exists "Customers create bids" on public.service_bids;
create policy "Customers create bids" on public.service_bids for insert to authenticated with check (customer_id=auth.uid());
drop policy if exists "Bid parties update bids" on public.service_bids;
drop policy if exists "Service owners decide customer bids" on public.service_bids;
create policy "Service owners decide customer bids" on public.service_bids for update to authenticated
 using (exists(select 1 from public.service_providers s where s.id=service_provider_id and s.owner_id=auth.uid()))
 with check (exists(select 1 from public.service_providers s where s.id=service_provider_id and s.owner_id=auth.uid()));

-- Rides: passengers propose fares; drivers respond with counter-offers.
create table if not exists public.ride_requests (
 id uuid primary key default gen_random_uuid(),
 passenger_id uuid not null references auth.users(id) on delete cascade,
 pickup_text text not null,
 destination_text text not null,
 pickup_lat double precision,
 pickup_lng double precision,
 destination_lat double precision,
 destination_lng double precision,
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
create policy "Passengers and registered drivers view rides" on public.ride_requests for select to authenticated using (
 passenger_id=auth.uid() or (status='open' and exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.account_type='driver'))
);
drop policy if exists "Passengers create rides" on public.ride_requests;
create policy "Passengers create rides" on public.ride_requests for insert to authenticated with check (passenger_id=auth.uid());
drop policy if exists "Passengers update own rides" on public.ride_requests;
create policy "Passengers update own rides" on public.ride_requests for update to authenticated using (passenger_id=auth.uid()) with check (passenger_id=auth.uid());

do $ begin
 if not exists(select 1 from pg_constraint where conname='matches_ride_request_fk' and conrelid='public.matches'::regclass) then
  alter table public.matches add constraint matches_ride_request_fk foreign key (ride_request_id) references public.ride_requests(id) on delete cascade;
 end if;
end $;

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
create policy "Ride parties view offers" on public.ride_offers for select to authenticated
 using (driver_id=auth.uid() or exists(select 1 from public.ride_requests r where r.id=ride_request_id and r.passenger_id=auth.uid()));
drop policy if exists "Drivers create own offers" on public.ride_offers;
create policy "Registered drivers create offers for open rides" on public.ride_offers for insert to authenticated with check (
 driver_id=auth.uid()
 and exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.account_type='driver')
 and exists(select 1 from public.ride_requests r where r.id=ride_request_id and r.status='open' and r.passenger_id<>auth.uid())
);
drop policy if exists "Ride parties update offers" on public.ride_offers;
drop policy if exists "Passengers decide driver offers" on public.ride_offers;
create policy "Passengers decide driver offers" on public.ride_offers for update to authenticated
 using (exists(select 1 from public.ride_requests r where r.id=ride_request_id and r.passenger_id=auth.uid()))
 with check (exists(select 1 from public.ride_requests r where r.id=ride_request_id and r.passenger_id=auth.uid()));

-- AGREE: private conversations and messages between matched/engaged users.
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
 check(participant_one<>participant_two)
);
create unique index if not exists conversations_pair_context_idx
 on public.conversations(least(participant_one,participant_two),greatest(participant_one,participant_two),coalesce(ask_id,'00000000-0000-0000-0000-000000000000'::uuid));
alter table public.conversations enable row level security;
drop policy if exists "Participants view conversations" on public.conversations;
create policy "Participants view conversations" on public.conversations for select to authenticated
 using (auth.uid() in (participant_one,participant_two));
drop policy if exists "Participants create conversations" on public.conversations;
create policy "Participants create conversations" on public.conversations for insert to authenticated
 with check (auth.uid() in (participant_one,participant_two) and participant_one<>participant_two and (ask_id is null or exists(select 1 from public.asks a where a.id=ask_id and a.user_id=auth.uid())));
create table if not exists public.messages (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade,
 body text not null,
 created_at timestamptz not null default now(),
 read_at timestamptz
);
alter table public.messages enable row level security;
drop policy if exists "Conversation participants read messages" on public.messages;
create policy "Conversation participants read messages" on public.messages for select to authenticated
 using (exists(select 1 from public.conversations c where c.id=conversation_id and auth.uid() in (c.participant_one,c.participant_two)));
drop policy if exists "Participants send own messages" on public.messages;
create policy "Participants send own messages" on public.messages for insert to authenticated
 with check (sender_id=auth.uid() and exists(select 1 from public.conversations c where c.id=conversation_id and auth.uid() in (c.participant_one,c.participant_two)));

-- Video-call signalling sessions. Actual media is peer-to-peer/WebRTC and needs a signalling client.
create table if not exists public.call_sessions (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 caller_id uuid not null references auth.users(id) on delete cascade,
 callee_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'ringing' check (status in ('ringing','accepted','declined','ended','missed')),
 offer jsonb,
 answer jsonb,
 ice_candidates jsonb not null default '[]'::jsonb,
 created_at timestamptz not null default now(),
 ended_at timestamptz,
 check(caller_id<>callee_id)
);
alter table public.call_sessions enable row level security;
drop policy if exists "Call participants access sessions" on public.call_sessions;
drop policy if exists "Participants read call sessions" on public.call_sessions;
drop policy if exists "Caller starts call sessions" on public.call_sessions;
drop policy if exists "Participants update call sessions" on public.call_sessions;
create policy "Participants read call sessions" on public.call_sessions for select to authenticated
 using (auth.uid() in (caller_id,callee_id) and exists(select 1 from public.conversations c where c.id=conversation_id and auth.uid() in (c.participant_one,c.participant_two)));
create policy "Caller starts call sessions" on public.call_sessions for insert to authenticated
 with check (caller_id=auth.uid() and exists(select 1 from public.conversations c where c.id=conversation_id and auth.uid() in (c.participant_one,c.participant_two) and callee_id in (c.participant_one,c.participant_two)));
create policy "Participants update call sessions" on public.call_sessions for update to authenticated
 using (auth.uid() in (caller_id,callee_id)) with check (auth.uid() in (caller_id,callee_id));

-- Verification is an application review workflow; no identity documents are stored by this migration.
create table if not exists public.verification_requests (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 submitted_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewer_note text
);
alter table public.verification_requests enable row level security;
drop policy if exists "Users view own verification requests" on public.verification_requests;
create policy "Users view own verification requests" on public.verification_requests for select to authenticated using(user_id=auth.uid());
drop policy if exists "Users submit own verification request" on public.verification_requests;
create policy "Users submit own verification request" on public.verification_requests for insert to authenticated with check(user_id=auth.uid());

grant select,insert,update,delete on public.profiles,public.asks,public.matches,public.service_bids,public.ride_requests,public.ride_offers,public.conversations,public.messages,public.call_sessions,public.verification_requests to authenticated;
