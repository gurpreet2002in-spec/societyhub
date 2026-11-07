-- ============================================================================
-- SocietyHub — add any columns the app expects but your database is missing
-- ============================================================================
-- Fixes errors like: Could not find the 'description' column of 'complaints'
-- in the schema cache (PGRST204).
-- Only ADDS missing columns (no data is changed or removed). Safe to re-run.
-- Run in Supabase -> SQL Editor (paste everything, Run).
-- ============================================================================

begin;

-- societies
alter table if exists public.societies add column if not exists name text;
alter table if exists public.societies add column if not exists slug text;
alter table if exists public.societies add column if not exists address text;
alter table if exists public.societies add column if not exists city text;
alter table if exists public.societies add column if not exists registration_number text;
alter table if exists public.societies add column if not exists subscription_plan text default 'basic';
alter table if exists public.societies add column if not exists subscription_status text default 'active';
alter table if exists public.societies add column if not exists created_at timestamptz default now();

-- users
alter table if exists public.users add column if not exists name text;
alter table if exists public.users add column if not exists email text;
alter table if exists public.users add column if not exists role text default 'resident';
alter table if exists public.users add column if not exists society_id uuid references societies(id);
alter table if exists public.users add column if not exists contact_number text;
alter table if exists public.users add column if not exists apartment_number text;
alter table if exists public.users add column if not exists created_at timestamptz default now();

-- complaints
alter table if exists public.complaints add column if not exists title text;
alter table if exists public.complaints add column if not exists description text;
alter table if exists public.complaints add column if not exists priority text default 'Medium';
alter table if exists public.complaints add column if not exists status text default 'Open';
alter table if exists public.complaints add column if not exists rating integer;
alter table if exists public.complaints add column if not exists rating_comment text;
alter table if exists public.complaints add column if not exists user_id uuid references users(id);
alter table if exists public.complaints add column if not exists society_id uuid references societies(id);
alter table if exists public.complaints add column if not exists created_at timestamptz default now();

-- invoices
alter table if exists public.invoices add column if not exists title text;
alter table if exists public.invoices add column if not exists amount numeric(10,2);
alter table if exists public.invoices add column if not exists tax_amount numeric(10,2) default 0;
alter table if exists public.invoices add column if not exists status text default 'Pending';
alter table if exists public.invoices add column if not exists due_date date;
alter table if exists public.invoices add column if not exists paid_at timestamptz;
alter table if exists public.invoices add column if not exists user_id uuid references users(id);
alter table if exists public.invoices add column if not exists society_id uuid references societies(id);
alter table if exists public.invoices add column if not exists created_at timestamptz default now();

-- visitors
alter table if exists public.visitors add column if not exists name text;
alter table if exists public.visitors add column if not exists mobile text;
alter table if exists public.visitors add column if not exists purpose text;
alter table if exists public.visitors add column if not exists expected_entry text;
alter table if exists public.visitors add column if not exists status text default 'Pending';
alter table if exists public.visitors add column if not exists flat_number text;
alter table if exists public.visitors add column if not exists society_id uuid references societies(id);
alter table if exists public.visitors add column if not exists created_at timestamptz default now();

-- daily_help
alter table if exists public.daily_help add column if not exists name text;
alter table if exists public.daily_help add column if not exists type text;
alter table if exists public.daily_help add column if not exists mobile text;
alter table if exists public.daily_help add column if not exists user_id uuid references users(id);
alter table if exists public.daily_help add column if not exists society_id uuid references societies(id);
alter table if exists public.daily_help add column if not exists created_at timestamptz default now();

-- help_attendance
alter table if exists public.help_attendance add column if not exists help_id uuid references daily_help(id) on delete cascade;
alter table if exists public.help_attendance add column if not exists date date;
alter table if exists public.help_attendance add column if not exists status text default 'present';

-- amenities
alter table if exists public.amenities add column if not exists name text;
alter table if exists public.amenities add column if not exists description text;
alter table if exists public.amenities add column if not exists capacity integer default 1;
alter table if exists public.amenities add column if not exists society_id uuid references societies(id);
alter table if exists public.amenities add column if not exists created_at timestamptz default now();

-- bookings
alter table if exists public.bookings add column if not exists amenity_id uuid references amenities(id) on delete cascade;
alter table if exists public.bookings add column if not exists user_id uuid references users(id);
alter table if exists public.bookings add column if not exists booking_date date;
alter table if exists public.bookings add column if not exists start_time time;
alter table if exists public.bookings add column if not exists end_time time;
alter table if exists public.bookings add column if not exists notes text;
alter table if exists public.bookings add column if not exists status text default 'Confirmed';
alter table if exists public.bookings add column if not exists created_at timestamptz default now();

-- notices
alter table if exists public.notices add column if not exists title text;
alter table if exists public.notices add column if not exists body text;
alter table if exists public.notices add column if not exists category text default 'General';
alter table if exists public.notices add column if not exists is_pinned boolean default false;
alter table if exists public.notices add column if not exists created_by uuid references users(id);
alter table if exists public.notices add column if not exists society_id uuid references societies(id);
alter table if exists public.notices add column if not exists created_at timestamptz default now();

-- polls
alter table if exists public.polls add column if not exists question text;
alter table if exists public.polls add column if not exists options jsonb default '[]';
alter table if exists public.polls add column if not exists ends_at timestamptz;
alter table if exists public.polls add column if not exists society_id uuid references societies(id);
alter table if exists public.polls add column if not exists created_by uuid references users(id);
alter table if exists public.polls add column if not exists created_at timestamptz default now();

-- poll_votes
alter table if exists public.poll_votes add column if not exists poll_id uuid references polls(id) on delete cascade;
alter table if exists public.poll_votes add column if not exists user_id uuid references users(id);
alter table if exists public.poll_votes add column if not exists option_index integer;

-- parking_slots
alter table if exists public.parking_slots add column if not exists slot_number text;
alter table if exists public.parking_slots add column if not exists is_occupied boolean default false;
alter table if exists public.parking_slots add column if not exists flat_id text;
alter table if exists public.parking_slots add column if not exists vehicle_no text;
alter table if exists public.parking_slots add column if not exists vehicle_type text;
alter table if exists public.parking_slots add column if not exists society_id uuid references societies(id);
alter table if exists public.parking_slots add column if not exists created_at timestamptz default now();

-- marketplace
alter table if exists public.marketplace add column if not exists title text;
alter table if exists public.marketplace add column if not exists description text;
alter table if exists public.marketplace add column if not exists price numeric(10,2);
alter table if exists public.marketplace add column if not exists category text default 'other';
alter table if exists public.marketplace add column if not exists status text default 'Available';
alter table if exists public.marketplace add column if not exists user_id uuid references users(id);
alter table if exists public.marketplace add column if not exists society_id uuid references societies(id);
alter table if exists public.marketplace add column if not exists created_at timestamptz default now();

-- notifications
alter table if exists public.notifications add column if not exists title text;
alter table if exists public.notifications add column if not exists body text;
alter table if exists public.notifications add column if not exists is_read boolean default false;
alter table if exists public.notifications add column if not exists user_id uuid references users(id);
alter table if exists public.notifications add column if not exists created_at timestamptz default now();

-- platform_settings
alter table if exists public.platform_settings add column if not exists value text;
alter table if exists public.platform_settings add column if not exists updated_at timestamptz default now();

-- audit_logs
alter table if exists public.audit_logs add column if not exists action text;
alter table if exists public.audit_logs add column if not exists entity text;
alter table if exists public.audit_logs add column if not exists entity_id uuid;
alter table if exists public.audit_logs add column if not exists performed_by uuid references users(id);
alter table if exists public.audit_logs add column if not exists created_at timestamptz default now();

-- vehicle_logs
alter table if exists public.vehicle_logs add column if not exists vehicle_number TEXT;
alter table if exists public.vehicle_logs add column if not exists vehicle_type TEXT;
alter table if exists public.vehicle_logs add column if not exists entry_time TIMESTAMPTZ DEFAULT now();
alter table if exists public.vehicle_logs add column if not exists exit_time TIMESTAMPTZ;
alter table if exists public.vehicle_logs add column if not exists flat_number TEXT;
alter table if exists public.vehicle_logs add column if not exists driver_name TEXT;
alter table if exists public.vehicle_logs add column if not exists purpose TEXT;
alter table if exists public.vehicle_logs add column if not exists guard_id UUID REFERENCES users(id);
alter table if exists public.vehicle_logs add column if not exists society_id UUID REFERENCES societies(id);
alter table if exists public.vehicle_logs add column if not exists status TEXT DEFAULT 'Inside';

-- resident_vehicles
alter table if exists public.resident_vehicles add column if not exists vehicle_number TEXT;
alter table if exists public.resident_vehicles add column if not exists vehicle_type TEXT;
alter table if exists public.resident_vehicles add column if not exists brand_model TEXT;
alter table if exists public.resident_vehicles add column if not exists color TEXT;
alter table if exists public.resident_vehicles add column if not exists user_id UUID REFERENCES users(id) ON DELETE CASCADE;
alter table if exists public.resident_vehicles add column if not exists society_id UUID REFERENCES societies(id) ON DELETE CASCADE;
alter table if exists public.resident_vehicles add column if not exists created_at TIMESTAMPTZ DEFAULT now();

alter table if exists public.visitors add column if not exists vehicle_number TEXT;
alter table if exists public.visitors add column if not exists checked_in_at TIMESTAMPTZ;
alter table if exists public.visitors add column if not exists checked_out_at TIMESTAMPTZ;
alter table if exists public.visitors add column if not exists guard_id UUID REFERENCES users(id);
alter table if exists public.parking_slots add column if not exists resident_vehicle_id UUID REFERENCES resident_vehicles(id);
alter table if exists public.vehicle_logs add column if not exists is_resident_vehicle BOOLEAN DEFAULT false;
alter table if exists public.vehicle_logs add column if not exists resident_vehicle_id UUID REFERENCES resident_vehicles(id);
alter table if exists public.users add column if not exists fcm_token text;
alter table if exists public.notifications add column if not exists data jsonb default '{}'::jsonb;

commit;

-- Tell the API to pick up the new columns immediately
notify pgrst, 'reload schema';
