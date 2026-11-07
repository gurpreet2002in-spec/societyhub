-- ============================================================================
-- SocietyHub — flat / house numbers (run once in Supabase → SQL Editor)
-- ============================================================================
-- Requires the earlier scripts (secure_rls, society_codes_approval,
-- complaint_updates, fix_all_columns). Safe to re-run.
--
--  • Flat numbers are tidied automatically everywhere (residents, parking,
--    visitors, vehicle logs): "b 402", "b402", "B_402" → "B-402".
--  • Residents give their flat + Owner/Tenant when registering (or joining
--    with a code). After approval only a society admin can change them —
--    this stops a resident from switching flats to see another flat's visitors.
-- ============================================================================

begin;

-- ── 1. Normaliser ──────────────────────────────────────────────────────────
create or replace function public.normalize_flat(p text) returns text
language sql immutable as $$
  select nullif(
           regexp_replace(
             btrim(regexp_replace(upper(regexp_replace(trim(coalesce(p, '')), '[\s_/\\]+', '-', 'g')), '-+', '-', 'g'), '-'),
             '^([A-Z]+)-?([0-9]+)$', '\1-\2'),
           '')
$$;

-- ── 2. Owner / tenant ──────────────────────────────────────────────────────
alter table public.users add column if not exists occupancy_type text;
update public.users set occupancy_type = lower(trim(occupancy_type)) where occupancy_type is not null;
update public.users set occupancy_type = null where occupancy_type not in ('owner', 'tenant');
alter table public.users drop constraint if exists users_occupancy_type_check;
alter table public.users add constraint users_occupancy_type_check
  check (occupancy_type is null or occupancy_type in ('owner', 'tenant'));

-- ── 3. Tidy existing data, and keep it tidy ────────────────────────────────
update public.users         set apartment_number = public.normalize_flat(apartment_number) where apartment_number is not null;
update public.parking_slots set flat_id          = public.normalize_flat(flat_id)          where flat_id is not null;
update public.visitors      set flat_number      = public.normalize_flat(flat_number)      where flat_number is not null;
do $$ begin
  if to_regclass('public.vehicle_logs') is not null then
    execute 'update public.vehicle_logs set flat_number = public.normalize_flat(flat_number) where flat_number is not null';
  end if;
end $$;

create or replace function public.tidy_flat_users() returns trigger
language plpgsql as $$
begin new.apartment_number := public.normalize_flat(new.apartment_number); return new; end $$;
drop trigger if exists tidy_flat on public.users;
create trigger tidy_flat before insert or update of apartment_number on public.users
  for each row execute function public.tidy_flat_users();

create or replace function public.tidy_flat_parking() returns trigger
language plpgsql as $$
begin new.flat_id := public.normalize_flat(new.flat_id); return new; end $$;
drop trigger if exists tidy_flat on public.parking_slots;
create trigger tidy_flat before insert or update of flat_id on public.parking_slots
  for each row execute function public.tidy_flat_parking();

create or replace function public.tidy_flat_number() returns trigger
language plpgsql as $$
begin new.flat_number := public.normalize_flat(new.flat_number); return new; end $$;
drop trigger if exists tidy_flat on public.visitors;
create trigger tidy_flat before insert or update of flat_number on public.visitors
  for each row execute function public.tidy_flat_number();
do $$ begin
  if to_regclass('public.vehicle_logs') is not null then
    execute 'drop trigger if exists tidy_flat on public.vehicle_logs';
    execute 'create trigger tidy_flat before insert or update of flat_number on public.vehicle_logs
               for each row execute function public.tidy_flat_number()';
  end if;
end $$;

-- ── 4. Guard: approved residents can't change their own flat ───────────────
create or replace function public.guard_user_changes() returns trigger
language plpgsql security definer set search_path = public as $$
declare caller_role text; caller_society uuid; caller_status text;
begin
  if auth.uid() is null then return new; end if;   -- SQL editor / service role
  select role, society_id, status into caller_role, caller_society, caller_status
    from public.users where id = auth.uid();
  if caller_role = 'super_admin' then return new; end if;

  if new.id is distinct from old.id then
    raise exception 'Changing user id is not allowed';
  end if;

  if new.role is distinct from old.role then
    if not (caller_role = 'admin' and caller_status = 'active' and old.society_id = caller_society
            and new.role in ('resident','guard','admin') and old.role <> 'super_admin'
            and old.id <> auth.uid()) then
      raise exception 'Not allowed to change role';
    end if;
  end if;

  if new.society_id is distinct from old.society_id then
    if not (old.id = auth.uid() and new.role = 'resident'
            and (old.society_id is null or old.status = 'rejected')
            and new.status = 'pending') then
      raise exception 'Not allowed to change society';
    end if;
  end if;

  if new.status is distinct from old.status then
    if old.id = auth.uid() then
      if not (new.status = 'pending'
              and (new.society_id is distinct from old.society_id or old.status = 'rejected')) then
        raise exception 'Not allowed to change your own status';
      end if;
    elsif not (caller_role = 'admin' and caller_status = 'active'
               and old.society_id = caller_society and old.role <> 'super_admin') then
      raise exception 'Not allowed to change status';
    end if;
  end if;

  -- Flat / owner-tenant: free to set until approved; afterwards only an admin.
  if (new.apartment_number is distinct from old.apartment_number
      or new.occupancy_type is distinct from old.occupancy_type)
     and old.id = auth.uid() and old.status = 'active' and old.society_id is not null
     and caller_role not in ('admin') then
    raise exception 'Your flat is managed by the society admin. Ask them to change it.';
  end if;
  return new;
end $$;

-- ── 5. Sign-up: take flat + owner/tenant from the register form ────────────
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_society uuid; v_occ text;
begin
  select s.id into v_society from public.societies s
   where s.join_code = upper(trim(coalesce(new.raw_user_meta_data->>'join_code', '')));
  if v_society is null then
    begin
      select s.id into v_society from public.societies s
       where s.id = nullif(new.raw_user_meta_data->>'society_id', '')::uuid;
    exception when others then v_society := null;
    end;
  end if;
  v_occ := lower(trim(coalesce(new.raw_user_meta_data->>'occupancy_type', '')));
  if v_occ not in ('owner', 'tenant') then v_occ := null; end if;

  insert into public.users (id, email, name, role, society_id, status, apartment_number, occupancy_type)
  values (new.id, new.email,
          left(coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)), 100),
          'resident', v_society, 'pending',
          left(new.raw_user_meta_data->>'apartment_number', 30), v_occ)
  on conflict (id) do nothing;
  return new;
end $$;

-- ── 6. Join with a code later — now also takes flat + owner/tenant ─────────
drop function if exists public.join_society_with_code(text);
create or replace function public.join_society_with_code(
  p_code text, p_flat text default null, p_occupancy text default null)
returns table (society_id uuid, society_name text)
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_name text; v_me public.users%rowtype; v_occ text;
begin
  select * into v_me from public.users where id = auth.uid();
  if v_me.id is null then raise exception 'Not logged in'; end if;
  if v_me.role <> 'resident' then raise exception 'Only residents can join with a code'; end if;
  if v_me.society_id is not null and v_me.status <> 'rejected' then
    raise exception 'You already belong to a society';
  end if;

  select s.id, s.name into v_id, v_name from public.societies s
   where s.join_code = upper(trim(p_code)) and coalesce(s.subscription_status, 'active') = 'active';
  if v_id is null then raise exception 'Invalid society code'; end if;

  v_occ := lower(trim(coalesce(p_occupancy, '')));
  if v_occ not in ('owner', 'tenant') then v_occ := v_me.occupancy_type; end if;

  update public.users
     set society_id = v_id, status = 'pending',
         apartment_number = coalesce(nullif(trim(coalesce(p_flat, '')), ''), apartment_number),
         occupancy_type = v_occ
   where id = auth.uid();
  return query select v_id, v_name;
end $$;
revoke all on function public.join_society_with_code(text, text, text) from public, anon;
grant execute on function public.join_society_with_code(text, text, text) to authenticated;

-- ── 7. Visitor / parking alerts go to EVERY active resident of the flat ────
create or replace function public.notify_on_visitor_entry() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, title, body, data)
  select u.id, 'New Visitor Alert',
         new.name || ' has arrived for ' || coalesce(new.purpose, 'a visit'),
         jsonb_build_object('type', 'visitor', 'id', new.id)
  from public.users u
  where u.society_id = new.society_id and u.status = 'active'
    and u.apartment_number is not null and u.apartment_number = new.flat_number;
  return new;
end $$;

create or replace function public.notify_on_parking_allotment() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.flat_id is not null and (old.flat_id is null or old.flat_id <> new.flat_id) then
    insert into public.notifications (user_id, title, body, data)
    select u.id, 'Parking Slot Allotted',
           'Slot ' || new.slot_number || ' has been allotted to your flat ' || new.flat_id || '.',
           jsonb_build_object('type', 'amenity', 'id', new.id)
    from public.users u
    where u.society_id = new.society_id and u.status = 'active' and u.apartment_number = new.flat_id;
  end if;
  return new;
end $$;

commit;

notify pgrst, 'reload schema';
