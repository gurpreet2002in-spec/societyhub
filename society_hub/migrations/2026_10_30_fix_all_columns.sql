-- ============================================================================
-- SocietyHub — FIX ALL missing columns + app data fixes (run once, SQL Editor)
-- ============================================================================
-- Fixes every "Could not find the '…' column of '…' in the schema cache"
-- error (PGRST204) in one go, and adds what the screens need:
--   • every column from the original schema that your database may lack
--   • marketplace: condition, emoji, SALE / RENT, seller name & flat
--   • notices: author name;  daily help: entry/exit time, active, days
--   • amenities: emoji, price per hour, opening hours;  bookings: amount
--   • parking slots: slot type (car / bike / ev);  societies: total flats
--   • complaints: resolved_at (for "average resolution time" in Reports)
--   • poll results (vote counts) for the Community screen
-- Only ADDS things: no data is removed. Safe to re-run.
-- Run AFTER the earlier scripts (secure_rls, society_codes_approval,
-- complaint_updates). Paste everything → Run.
-- ============================================================================

begin;

-- ── A. Columns from the original schema (adds only the missing ones) ───────
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


-- ── B. New columns used by the app ─────────────────────────────────────────
alter table if exists public.marketplace add column if not exists condition text default 'good';
alter table if exists public.marketplace add column if not exists image_emoji text;
alter table if exists public.marketplace add column if not exists listing_type text default 'sale';
alter table if exists public.marketplace add column if not exists seller_name text;
alter table if exists public.marketplace add column if not exists seller_flat text;
update public.marketplace set listing_type = 'sale' where listing_type is null or listing_type not in ('sale', 'rent');
alter table public.marketplace drop constraint if exists marketplace_listing_type_check;
alter table public.marketplace add constraint marketplace_listing_type_check check (listing_type in ('sale', 'rent'));

alter table if exists public.notices add column if not exists posted_by_name text;

alter table if exists public.daily_help add column if not exists entry_time text;
alter table if exists public.daily_help add column if not exists exit_time text;
alter table if exists public.daily_help add column if not exists is_active boolean default true;
alter table if exists public.daily_help add column if not exists working_days text;

alter table if exists public.amenities add column if not exists image_emoji text;
alter table if exists public.amenities add column if not exists price_per_hour numeric(10,2) default 0;
alter table if exists public.amenities add column if not exists open_time text default '06:00';
alter table if exists public.amenities add column if not exists close_time text default '22:00';

alter table if exists public.bookings add column if not exists total_amount numeric(10,2) default 0;

alter table if exists public.parking_slots add column if not exists slot_type text default 'car';

alter table if exists public.societies add column if not exists total_flats integer;

alter table if exists public.complaints add column if not exists resolved_at timestamptz;

-- ── C. Names filled in by the database (residents can't read other profiles)
create or replace function public.fill_marketplace_seller() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select u.name, u.apartment_number into new.seller_name, new.seller_flat
    from public.users u where u.id = new.user_id;
  return new;
end $$;
drop trigger if exists fill_marketplace_seller on public.marketplace;
create trigger fill_marketplace_seller before insert or update on public.marketplace
  for each row execute function public.fill_marketplace_seller();
update public.marketplace m set seller_name = u.name, seller_flat = u.apartment_number
  from public.users u where u.id = m.user_id and m.seller_name is null;

create or replace function public.fill_notice_author() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.created_by is null then new.created_by := auth.uid(); end if;
  select u.name into new.posted_by_name from public.users u where u.id = new.created_by;
  return new;
end $$;
drop trigger if exists fill_notice_author on public.notices;
create trigger fill_notice_author before insert on public.notices
  for each row execute function public.fill_notice_author();
update public.notices n set posted_by_name = u.name
  from public.users u where u.id = n.created_by and n.posted_by_name is null;

-- Record when a complaint gets resolved (for Reports).
create or replace function public.set_complaint_resolved_at() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.status = 'Resolved' and old.status is distinct from 'Resolved' then
    new.resolved_at := now();
  elsif new.status <> 'Resolved' then
    new.resolved_at := null;
  end if;
  return new;
end $$;
drop trigger if exists set_complaint_resolved_at on public.complaints;
create trigger set_complaint_resolved_at before update of status on public.complaints
  for each row execute function public.set_complaint_resolved_at();

-- ── D. Poll results (votes are private, counts are shared) ─────────────────
create or replace function public.get_polls_with_results()
returns table (id uuid, question text, options jsonb, ends_at timestamptz, created_at timestamptz,
               vote_counts integer[], total_votes integer, user_vote integer)
language sql stable security definer set search_path = public as $$
  select p.id, p.question, p.options, p.ends_at, p.created_at,
         array(select (select count(*)::int from public.poll_votes v
                        where v.poll_id = p.id and v.option_index = i - 1)
               from generate_series(1, greatest(jsonb_array_length(coalesce(p.options, '[]'::jsonb)), 0)) as i),
         (select count(*)::int from public.poll_votes v where v.poll_id = p.id),
         (select v.option_index from public.poll_votes v where v.poll_id = p.id and v.user_id = auth.uid())
  from public.polls p
  where p.society_id = public.auth_society() or public.is_super_admin()
  order by p.created_at desc
$$;
revoke all on function public.get_polls_with_results() from public, anon;
grant execute on function public.get_polls_with_results() to authenticated;

commit;

notify pgrst, 'reload schema';
