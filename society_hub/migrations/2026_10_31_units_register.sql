-- ============================================================================
-- SocietyHub — Flats / Houses REGISTER (run once in Supabase → SQL Editor)
-- ============================================================================
-- Requires 2026_10_30_flats.sql and 2026_10_30_property_types.sql. Safe to re-run.
--
--  • public.units: the admin's master list of flats / houses, with the owner's
--    details (even before the owner installs the app), block and floor.
--  • Residents and parking slots link to a unit by its number (e.g. "B-402").
--  • Renaming a unit also renames it on its residents and parking slots.
--  • Deleting a unit frees its parking slots (residents keep their number and
--    show as "not in register" so nothing is lost by mistake).
--  • import_units(): bulk add / update from a CSV (also used for "Add many").
-- ============================================================================

begin;

-- ── 1. Table ───────────────────────────────────────────────────────────────
create table if not exists public.units (
  id          uuid primary key default gen_random_uuid(),
  society_id  uuid not null references public.societies(id) on delete cascade,
  number      text not null,
  unit_type   text not null default 'flat',
  block       text,
  floor       text,
  owner_name  text,
  owner_phone text,
  owner_email text,
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.units drop constraint if exists units_unit_type_check;
alter table public.units add constraint units_unit_type_check check (unit_type in ('flat', 'house'));
alter table public.units drop constraint if exists units_number_len;
alter table public.units add constraint units_number_len check (char_length(number) between 1 and 30);
create unique index if not exists units_society_number_key on public.units (society_id, number);
create index if not exists units_society_idx on public.units (society_id);

-- ── 2. Tidy values on every insert / update ────────────────────────────────
create or replace function public.tidy_unit() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_type text;
begin
  new.number      := public.normalize_flat(new.number);
  if new.number is null then raise exception 'Flat / house number is required'; end if;
  new.block       := nullif(left(trim(coalesce(new.block, '')), 30), '');
  new.floor       := nullif(left(trim(coalesce(new.floor, '')), 10), '');
  new.owner_name  := nullif(left(trim(coalesce(new.owner_name, '')), 100), '');
  new.owner_phone := nullif(left(regexp_replace(coalesce(new.owner_phone, ''), '[^0-9+]', '', 'g'), 20), '');
  new.owner_email := nullif(left(lower(trim(coalesce(new.owner_email, ''))), 120), '');
  new.notes       := nullif(left(trim(coalesce(new.notes, '')), 500), '');
  new.unit_type   := lower(trim(coalesce(new.unit_type, '')));
  -- Society with only flats / only houses decides the type.
  select property_type into v_type from public.societies where id = new.society_id;
  if v_type = 'apartments' then new.unit_type := 'flat';
  elsif v_type = 'villas' then new.unit_type := 'house';
  elsif new.unit_type not in ('flat', 'house') then new.unit_type := 'flat';
  end if;
  if tg_op = 'UPDATE' then
    new.society_id := old.society_id;   -- a unit never moves to another society
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists tidy_unit on public.units;
create trigger tidy_unit before insert or update on public.units
  for each row execute function public.tidy_unit();

-- ── 3. Rename / delete follow-ups ──────────────────────────────────────────
create or replace function public.units_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.number is distinct from old.number then
      update public.users set apartment_number = new.number
       where society_id = old.society_id and apartment_number = old.number;
      update public.parking_slots set flat_id = new.number
       where society_id = old.society_id and flat_id = old.number;
    end if;
    if new.unit_type is distinct from old.unit_type then
      update public.users set unit_type = new.unit_type
       where society_id = new.society_id and apartment_number = new.number;
    end if;
    return new;
  else -- DELETE: free its parking
    update public.parking_slots
       set flat_id = null, vehicle_no = null, vehicle_type = null, is_occupied = false
     where society_id = old.society_id and flat_id = old.number;
    return old;
  end if;
end $$;
drop trigger if exists units_after_change on public.units;
create trigger units_after_change after update or delete on public.units
  for each row execute function public.units_after_change();

-- A resident linked to a unit of a mixed society takes the unit's type.
create or replace function public.unit_type_from_register() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_type text;
begin
  if new.society_id is not null and new.apartment_number is not null then
    select unit_type into v_type from public.units
     where society_id = new.society_id and number = new.apartment_number;
    if v_type is not null then new.unit_type := v_type; end if;
  end if;
  return new;
end $$;
-- Name sorts after "default_unit_type" and "tidy_flat", so it runs last.
drop trigger if exists zz_unit_type_from_register on public.users;
create trigger zz_unit_type_from_register before insert or update of society_id, apartment_number, unit_type on public.users
  for each row execute function public.unit_type_from_register();

-- ── 4. Security ────────────────────────────────────────────────────────────
alter table public.units enable row level security;
drop policy if exists "units_select" on public.units;
drop policy if exists "units_admin_write" on public.units;
-- Admins and guards see the whole register; a resident sees only their own unit.
create policy "units_select" on public.units for select to authenticated using (
  public.is_society_staff(society_id)
  or public.is_super_admin()
  or (society_id = public.auth_society() and number = public.auth_apartment())
);
create policy "units_admin_write" on public.units for all to authenticated
  using (public.is_society_admin(society_id))
  with check (public.is_society_admin(society_id));
revoke all on public.units from anon;
grant select, insert, update, delete on public.units to authenticated;

-- ── 5. Bulk import (CSV / "Add many") ──────────────────────────────────────
-- p_rows: [{"number":"A-101","type":"flat","block":"A","floor":"1",
--           "owner_name":"..","owner_phone":"..","owner_email":"..",
--           "parking":"P-1; P-2"}, ...]
-- Blank owner fields keep what is already saved. Parking slots that don't
-- exist yet are created; a slot already given to another unit is skipped.
create or replace function public.import_units(p_rows jsonb)
returns table (added int, updated int, skipped int, parking_assigned int, errors text[])
language plpgsql security definer set search_path = public as $$
declare
  v_sid uuid := public.auth_society();
  r jsonb; v_num text; v_existing public.units%rowtype; v_slot text; v_slot_row public.parking_slots%rowtype;
  n_add int := 0; n_upd int := 0; n_skip int := 0; n_park int := 0; v_err text[] := '{}';
  i int := 0;
begin
  if v_sid is null or not public.is_society_admin(v_sid) then
    raise exception 'Only the society admin can import flats / houses';
  end if;
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'Expected a list of rows'; end if;
  if jsonb_array_length(p_rows) > 5000 then raise exception 'Too many rows (max 5000 at a time)'; end if;

  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    v_num := public.normalize_flat(r->>'number');
    if v_num is null or char_length(v_num) > 30 then
      n_skip := n_skip + 1;
      if array_length(v_err, 1) is null or array_length(v_err, 1) < 20 then
        v_err := v_err || format('Row %s: missing or invalid number', i);
      end if;
      continue;
    end if;

    select * into v_existing from public.units where society_id = v_sid and number = v_num;
    if v_existing.id is null then
      insert into public.units (society_id, number, unit_type, block, floor, owner_name, owner_phone, owner_email, notes)
      values (v_sid, v_num, r->>'type', r->>'block', r->>'floor',
              r->>'owner_name', r->>'owner_phone', r->>'owner_email', r->>'notes');
      n_add := n_add + 1;
    else
      update public.units set
        unit_type   = coalesce(nullif(trim(coalesce(r->>'type', '')), ''), unit_type),
        block       = coalesce(nullif(trim(coalesce(r->>'block', '')), ''), block),
        floor       = coalesce(nullif(trim(coalesce(r->>'floor', '')), ''), floor),
        owner_name  = coalesce(nullif(trim(coalesce(r->>'owner_name', '')), ''), owner_name),
        owner_phone = coalesce(nullif(trim(coalesce(r->>'owner_phone', '')), ''), owner_phone),
        owner_email = coalesce(nullif(trim(coalesce(r->>'owner_email', '')), ''), owner_email),
        notes       = coalesce(nullif(trim(coalesce(r->>'notes', '')), ''), notes)
      where id = v_existing.id;
      n_upd := n_upd + 1;
    end if;
    v_existing := null;

    -- Parking: "P-1; P-2" or "P-1, P-2"
    for v_slot in
      select distinct upper(trim(s)) from regexp_split_to_table(coalesce(r->>'parking', ''), '[;,|]') s
      where trim(s) <> ''
    loop
      select * into v_slot_row from public.parking_slots
       where society_id = v_sid and upper(trim(slot_number)) = v_slot limit 1;
      if v_slot_row.id is null then
        insert into public.parking_slots (society_id, slot_number, slot_type, is_occupied, flat_id)
        values (v_sid, v_slot, 'car', true, v_num);
        n_park := n_park + 1;
      elsif v_slot_row.flat_id is null or v_slot_row.flat_id = v_num then
        if v_slot_row.flat_id is null then
          update public.parking_slots set flat_id = v_num, is_occupied = true where id = v_slot_row.id;
          n_park := n_park + 1;
        end if;
      elsif array_length(v_err, 1) is null or array_length(v_err, 1) < 20 then
        v_err := v_err || format('Row %s: slot %s already belongs to %s', i, v_slot, v_slot_row.flat_id);
      end if;
      v_slot_row := null;
    end loop;
  end loop;

  return query select n_add, n_upd, n_skip, n_park, v_err;
end $$;
revoke all on function public.import_units(jsonb) from public, anon;
grant execute on function public.import_units(jsonb) to authenticated;

-- ── 6. Start the register from what already exists ─────────────────────────
-- Every flat number already used by a resident or a parking slot becomes a unit
-- (owner details filled from an approved owner when there is one).
insert into public.units (society_id, number, unit_type, owner_name, owner_phone, owner_email)
select distinct on (x.society_id, x.number) x.society_id, x.number, x.unit_type, x.name, x.phone, x.email
from (
  select u.society_id, u.apartment_number as number, coalesce(u.unit_type, 'flat') as unit_type,
         case when u.occupancy_type = 'owner' and u.status = 'active' then u.name end as name,
         case when u.occupancy_type = 'owner' and u.status = 'active' then u.contact_number end as phone,
         case when u.occupancy_type = 'owner' and u.status = 'active' then u.email end as email,
         case when u.occupancy_type = 'owner' and u.status = 'active' then 0 else 1 end as pri
    from public.users u
   where u.society_id is not null and u.apartment_number is not null and u.status <> 'rejected'
  union all
  select p.society_id, p.flat_id, 'flat', null, null, null, 2
    from public.parking_slots p where p.society_id is not null and p.flat_id is not null
) x
where x.number is not null
order by x.society_id, x.number, x.pri
on conflict (society_id, number) do nothing;

commit;

notify pgrst, 'reload schema';
