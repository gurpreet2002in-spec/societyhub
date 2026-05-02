-- ============================================================
-- SocietyHub - Supabase Database Schema
-- Run this entire file in: Supabase → SQL Editor → New Query
-- ============================================================

-- Enable UUID generation
create extension if not exists "pgcrypto";

-- ── SOCIETIES ─────────────────────────────────────────────────────────────────
create table if not exists societies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text,
  city text,
  registration_number text unique,
  subscription_plan text default 'basic',
  subscription_status text default 'active',
  created_at timestamptz default now()
);

-- ── USERS (mirrors Supabase auth.users) ───────────────────────────────────────
create table if not exists users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  email text unique,
  role text default 'resident',   -- 'resident' | 'admin' | 'super_admin'
  society_id uuid references societies(id),
  contact_number text,
  apartment_number text,
  created_at timestamptz default now()
);

-- Auto-insert user row when someone signs up via Supabase Auth
create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.users (id, email, name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

-- ── COMPLAINTS / MAINTENANCE ──────────────────────────────────────────────────
create table if not exists complaints (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  priority text default 'Medium',  -- 'Low' | 'Medium' | 'High' | 'Critical'
  status text default 'Open',       -- 'Open' | 'Investigating' | 'Escalated' | 'Resolved'
  rating integer,
  rating_comment text,
  user_id uuid references users(id),
  society_id uuid references societies(id),
  created_at timestamptz default now()
);

-- ── INVOICES ──────────────────────────────────────────────────────────────────
create table if not exists invoices (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  amount numeric(10,2) not null,
  tax_amount numeric(10,2) default 0,
  status text default 'Pending',   -- 'Pending' | 'Paid' | 'Overdue'
  due_date date,
  paid_at timestamptz,
  user_id uuid references users(id),
  society_id uuid references societies(id),
  created_at timestamptz default now()
);

-- ── VISITORS ──────────────────────────────────────────────────────────────────
create table if not exists visitors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  mobile text,
  purpose text,
  expected_entry text,
  status text default 'Pending',   -- 'Pending' | 'Pre-approved' | 'Checked-in' | 'Checked-out'
  flat_number text,
  society_id uuid references societies(id),
  created_at timestamptz default now()
);

-- ── DAILY HELP ────────────────────────────────────────────────────────────────
create table if not exists daily_help (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type text,                        -- 'maid' | 'driver' | 'cook' | 'other'
  mobile text,
  user_id uuid references users(id),
  society_id uuid references societies(id),
  created_at timestamptz default now()
);

create table if not exists help_attendance (
  id uuid primary key default gen_random_uuid(),
  help_id uuid references daily_help(id) on delete cascade,
  date date not null,
  status text default 'present',   -- 'present' | 'absent'
  unique (help_id, date)
);

-- ── AMENITIES ─────────────────────────────────────────────────────────────────
create table if not exists amenities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  capacity integer default 1,
  society_id uuid references societies(id),
  created_at timestamptz default now()
);

create table if not exists bookings (
  id uuid primary key default gen_random_uuid(),
  amenity_id uuid references amenities(id) on delete cascade,
  user_id uuid references users(id),
  booking_date date,
  start_time time,
  end_time time,
  notes text,
  status text default 'Confirmed',  -- 'Confirmed' | 'Cancelled'
  created_at timestamptz default now()
);

-- ── NOTICES ───────────────────────────────────────────────────────────────────
create table if not exists notices (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text,
  category text default 'General',
  is_pinned boolean default false,
  created_by uuid references users(id),
  society_id uuid references societies(id),
  created_at timestamptz default now()
);

-- ── POLLS ─────────────────────────────────────────────────────────────────────
create table if not exists polls (
  id uuid primary key default gen_random_uuid(),
  question text not null,
  options jsonb not null default '[]',   -- [{"label":"Yes"},{"label":"No"}]
  ends_at timestamptz,
  society_id uuid references societies(id),
  created_by uuid references users(id),
  created_at timestamptz default now()
);

create table if not exists poll_votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid references polls(id) on delete cascade,
  user_id uuid references users(id),
  option_index integer not null,
  unique (poll_id, user_id)
);

-- ── PARKING ───────────────────────────────────────────────────────────────────
create table if not exists parking_slots (
  id uuid primary key default gen_random_uuid(),
  slot_number text not null,
  is_occupied boolean default false,
  flat_id text,
  vehicle_no text,
  vehicle_type text,                -- 'car' | 'bike' | 'other'
  society_id uuid references societies(id),
  created_at timestamptz default now()
);

-- ── MARKETPLACE ───────────────────────────────────────────────────────────────
create table if not exists marketplace (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  price numeric(10,2),
  category text default 'other',
  status text default 'Available',  -- 'Available' | 'Sold'
  user_id uuid references users(id),
  society_id uuid references societies(id),
  created_at timestamptz default now()
);

-- ── NOTIFICATIONS ─────────────────────────────────────────────────────────────
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  title text,
  body text,
  is_read boolean default false,
  user_id uuid references users(id),
  created_at timestamptz default now()
);

-- ── PLATFORM SETTINGS (super admin) ──────────────────────────────────────────
create table if not exists platform_settings (
  key text primary key,
  value text,
  updated_at timestamptz default now()
);

-- ── AUDIT LOGS ────────────────────────────────────────────────────────────────
create table if not exists audit_logs (
  id uuid primary key default gen_random_uuid(),
  action text,
  entity text,
  entity_id uuid,
  performed_by uuid references users(id),
  created_at timestamptz default now()
);

-- ============================================================
-- ROW LEVEL SECURITY (basic — tighten per your requirements)
-- ============================================================

-- Enable RLS on every table
alter table users enable row level security;
alter table societies enable row level security;
alter table complaints enable row level security;
alter table invoices enable row level security;
alter table visitors enable row level security;
alter table daily_help enable row level security;
alter table help_attendance enable row level security;
alter table amenities enable row level security;
alter table bookings enable row level security;
alter table notices enable row level security;
alter table polls enable row level security;
alter table poll_votes enable row level security;
alter table parking_slots enable row level security;
alter table marketplace enable row level security;
alter table notifications enable row level security;
alter table platform_settings enable row level security;
alter table audit_logs enable row level security;

-- Drop policies first so re-running the script is always safe
drop policy if exists "Allow all for authenticated" on users;
drop policy if exists "Allow all for authenticated" on societies;
drop policy if exists "Allow all for authenticated" on complaints;
drop policy if exists "Allow all for authenticated" on invoices;
drop policy if exists "Allow all for authenticated" on visitors;
drop policy if exists "Allow all for authenticated" on daily_help;
drop policy if exists "Allow all for authenticated" on help_attendance;
drop policy if exists "Allow all for authenticated" on amenities;
drop policy if exists "Allow all for authenticated" on bookings;
drop policy if exists "Allow all for authenticated" on notices;
drop policy if exists "Allow all for authenticated" on polls;
drop policy if exists "Allow all for authenticated" on poll_votes;
drop policy if exists "Allow all for authenticated" on parking_slots;
drop policy if exists "Allow all for authenticated" on marketplace;
drop policy if exists "Allow all for authenticated" on notifications;
drop policy if exists "Allow all for authenticated" on platform_settings;
drop policy if exists "Allow all for authenticated" on audit_logs;

create policy "Allow all for authenticated" on users
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on societies
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on complaints
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on invoices
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on visitors
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on daily_help
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on help_attendance
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on amenities
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on bookings
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on notices
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on polls
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on poll_votes
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on parking_slots
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on marketplace
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on notifications
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on platform_settings
  for all using (auth.role() = 'authenticated');

create policy "Allow all for authenticated" on audit_logs
  for all using (auth.role() = 'authenticated');

-- ============================================================
-- SEED: Create a super admin user record (run AFTER first signup)
-- Replace <YOUR_AUTH_USER_ID> with the UUID from auth.users
-- ============================================================
-- update users set role = 'super_admin' where email = 'your@email.com';
