-- ============================================================================
-- SocietyHub — society TYPE: apartments / independent houses (villas) / both
-- ============================================================================
-- Requires 2026_10_30_flats.sql (and the scripts before it). Safe to re-run.
--
--  • societies.property_type: 'apartments' | 'villas' | 'mixed'
--    (existing societies become 'apartments').
--  • users.unit_type: 'flat' | 'house' — what the resident lives in. In a
--    mixed society the resident picks it; otherwise it follows the society.
--  • Like the flat number, an approved resident can't change it themselves.
-- ============================================================================

begin;

-- ── 1. Columns ─────────────────────────────────────────────────────────────
alter table public.societies add column if not exists property_type text not null default 'apartments';
alter table public.societies drop constraint if exists societies_property_type_check;
alter table public.societies add constraint societies_property_type_check
  check (property_type in ('apartments', 'villas', 'mixed'));

alter table public.users add column if not exists unit_type text;
alter table public.users drop constraint if exists users_unit_type_check;
alter table public.users add constraint users_unit_type_check
  check (unit_type is null or unit_type in ('flat', 'house'));

-- Existing residents with a flat number in an apartments society → 'flat'.
update public.users u set unit_type = case s.property_type when 'villas' then 'house' else 'flat' end
  from public.societies s
 where s.id = u.society_id and u.unit_type is null and u.apartment_number is not null
   and s.property_type <> 'mixed';

-- ── 2. Public lookups now also return the society type ─────────────────────
drop function if exists public.get_society_by_code(text);
create or replace function public.get_society_by_code(p_code text)
returns table (id uuid, name text, property_type text)
language sql stable security definer set search_path = public as $$
  select s.id, s.name, s.property_type from public.societies s
  where s.join_code = upper(trim(p_code))
    and coalesce(s.subscription_status, 'active') = 'active'
  limit 1
$$;
revoke all on function public.get_society_by_code(text) from public;
grant execute on function public.get_society_by_code(text) to anon, authenticated;

drop function if exists public.get_society_by_slug(text);
create or replace function public.get_society_by_slug(p_slug text)
returns table (id uuid, name text, slug text, property_type text)
language sql stable security definer set search_path = public as $$
  select s.id, s.name, s.slug, s.property_type from public.societies s
  where s.slug = p_slug and coalesce(s.subscription_status, 'active') = 'active'
  limit 1
$$;
grant execute on function public.get_society_by_slug(text) to anon, authenticated;

-- Name + type of the caller's society, also while pending.
create or replace function public.my_society_info()
returns table (name text, property_type text)
language sql stable security definer set search_path = public as $$
  select s.name, s.property_type from public.users u join public.societies s on s.id = u.society_id
  where u.id = auth.uid()
$$;
revoke all on function public.my_society_info() from public, anon;
grant execute on function public.my_society_info() to authenticated;

-- ── 3. Unit type follows the society unless it's mixed ─────────────────────
create or replace function public.default_unit_type() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_type text;
begin
  if new.society_id is not null and new.apartment_number is not null then
    select property_type into v_type from public.societies where id = new.society_id;
    if v_type = 'apartments' then new.unit_type := 'flat';
    elsif v_type = 'villas' then new.unit_type := 'house';
    end if;   -- mixed: keep what the resident / admin chose
  end if;
  return new;
end $$;
drop trigger if exists default_unit_type on public.users;
create trigger default_unit_type before insert or update of society_id, apartment_number, unit_type on public.users
  for each row execute function public.default_unit_type();

-- ── 4. Sign-up reads unit type too ─────────────────────────────────────────
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_society uuid; v_occ text; v_unit text;
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
  v_unit := lower(trim(coalesce(new.raw_user_meta_data->>'unit_type', '')));
  if v_unit not in ('flat', 'house') then v_unit := null; end if;

  insert into public.users (id, email, name, role, society_id, status, apartment_number, occupancy_type, unit_type)
  values (new.id, new.email,
          left(coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)), 100),
          'resident', v_society, 'pending',
          left(new.raw_user_meta_data->>'apartment_number', 30), v_occ, v_unit)
  on conflict (id) do nothing;
  return new;
end $$;

-- ── 5. Join with a code: optional unit type ────────────────────────────────
drop function if exists public.join_society_with_code(text, text, text);
create or replace function public.join_society_with_code(
  p_code text, p_flat text default null, p_occupancy text default null, p_unit_type text default null)
returns table (society_id uuid, society_name text)
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_name text; v_me public.users%rowtype; v_occ text; v_unit text;
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
  v_unit := lower(trim(coalesce(p_unit_type, '')));
  if v_unit not in ('flat', 'house') then v_unit := v_me.unit_type; end if;

  update public.users
     set society_id = v_id, status = 'pending',
         apartment_number = coalesce(nullif(trim(coalesce(p_flat, '')), ''), apartment_number),
         occupancy_type = v_occ, unit_type = v_unit
   where id = auth.uid();
  return query select v_id, v_name;
end $$;
revoke all on function public.join_society_with_code(text, text, text, text) from public, anon;
grant execute on function public.join_society_with_code(text, text, text, text) to authenticated;

-- ── 6. Approved residents can't change their unit type either ──────────────
create or replace function public.guard_unit_type() returns trigger
language plpgsql security definer set search_path = public as $$
declare caller_role text;
begin
  if auth.uid() is null or new.unit_type is not distinct from old.unit_type then return new; end if;
  select role into caller_role from public.users where id = auth.uid();
  if caller_role in ('admin', 'super_admin') then return new; end if;
  if old.id = auth.uid() and old.status = 'active' and old.society_id is not null
     and pg_trigger_depth() = 1 then
    raise exception 'Your flat / house is managed by the society admin. Ask them to change it.';
  end if;
  return new;
end $$;
drop trigger if exists guard_unit_type on public.users;
create trigger guard_unit_type before update of unit_type on public.users
  for each row execute function public.guard_unit_type();

-- ── 7. Changing a society's type updates its residents' unit type ──────────
create or replace function public.sync_unit_types() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.property_type is distinct from old.property_type and new.property_type <> 'mixed' then
    update public.users
       set unit_type = case new.property_type when 'villas' then 'house' else 'flat' end
     where society_id = new.id and apartment_number is not null;
  end if;
  return new;
end $$;
drop trigger if exists sync_unit_types on public.societies;
create trigger sync_unit_types after update of property_type on public.societies
  for each row execute function public.sync_unit_types();

commit;

notify pgrst, 'reload schema';
