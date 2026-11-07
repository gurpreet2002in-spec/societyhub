-- ============================================================================
-- SocietyHub — society JOIN CODES + resident APPROVAL (run once, SQL Editor)
-- ============================================================================
-- Requires 2026_10_30_secure_rls.sql to have been run first.
--
-- After this script:
--   • Every society has a join code (e.g. EKTA-7F3K). New societies get one
--     automatically. Admins see their own code; the super admin sees all.
--   • New residents sign up with a code and start as 'pending'.
--   • A pending (or rejected) user can see ONLY their own profile — no society
--     data — until an admin of that society approves them.
--   • Society admins get a notification for every new pending resident.
--   • Everyone who exists today is marked 'active', so nobody is locked out.
-- Safe to re-run.
-- ============================================================================

begin;

-- ── 1. Join codes ──────────────────────────────────────────────────────────
alter table public.societies add column if not exists join_code text;

create or replace function public.make_join_code(p_name text) returns text
language plpgsql volatile set search_path = public as $$
declare
  prefix text := upper(left(regexp_replace(coalesce(p_name, ''), '[^A-Za-z0-9]', '', 'g'), 4));
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   -- no 0/O/1/I confusion
  code text;
  i int;
begin
  if length(prefix) < 2 then prefix := 'SOC'; end if;
  loop
    code := prefix || '-';
    for i in 1..4 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.societies where join_code = code);
  end loop;
  return code;
end $$;

update public.societies set join_code = public.make_join_code(name) where join_code is null;
update public.societies set join_code = upper(trim(join_code));

create unique index if not exists societies_join_code_key on public.societies (join_code);

create or replace function public.set_join_code() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.join_code is null or trim(new.join_code) = '' then
    new.join_code := public.make_join_code(new.name);
  else
    new.join_code := upper(trim(new.join_code));
  end if;
  return new;
end $$;
drop trigger if exists set_join_code on public.societies;
create trigger set_join_code before insert or update of join_code on public.societies
  for each row execute function public.set_join_code();

-- Public lookup used on the register screen: returns ONLY id + name.
create or replace function public.get_society_by_code(p_code text)
returns table (id uuid, name text)
language sql stable security definer set search_path = public as $$
  select s.id, s.name from public.societies s
  where s.join_code = upper(trim(p_code))
    and coalesce(s.subscription_status, 'active') = 'active'
  limit 1
$$;
revoke all on function public.get_society_by_code(text) from public;
grant execute on function public.get_society_by_code(text) to anon, authenticated;

-- ── 2. User status ─────────────────────────────────────────────────────────
alter table public.users add column if not exists status text;
update public.users set status = 'active' where status is null;      -- existing users keep access
alter table public.users alter column status set default 'pending';
alter table public.users alter column status set not null;
alter table public.users drop constraint if exists users_status_check;
alter table public.users add constraint users_status_check
  check (status in ('pending', 'active', 'rejected'));

-- ── 3. Only ACTIVE users count as members of a society ─────────────────────
-- Every policy from secure_rls.sql goes through these helpers, so pending and
-- rejected users automatically see no society data.
create or replace function public.auth_society() returns uuid
language sql stable security definer set search_path = public as $$
  select society_id from public.users where id = auth.uid() and status = 'active'
$$;

create or replace function public.is_society_admin(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'admin' and society_id = sid and status = 'active'
                   from public.users where id = auth.uid()), false)
$$;

create or replace function public.is_society_staff(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role in ('admin','guard') and society_id = sid and status = 'active'
                   from public.users where id = auth.uid()), false)
$$;

create or replace function public.auth_apartment() returns text
language sql stable security definer set search_path = public as $$
  select apartment_number from public.users where id = auth.uid() and status = 'active'
$$;

-- A user may only create their own row, as a pending resident.
drop policy if exists "users_insert_self" on public.users;
create policy "users_insert_self" on public.users for insert to authenticated with check (
  id = auth.uid() and role = 'resident' and status = 'pending'
);

-- ── 4. Guard: who may change role / society / status ───────────────────────
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
    -- A resident without a society (or rejected) may join one, and becomes pending.
    if not (old.id = auth.uid() and new.role = 'resident'
            and (old.society_id is null or old.status = 'rejected')
            and new.status = 'pending') then
      raise exception 'Not allowed to change society';
    end if;
  end if;

  if new.status is distinct from old.status then
    if old.id = auth.uid() then
      -- Self: only (re-)applying to a society (→ pending) is allowed.
      if not (new.status = 'pending'
              and (new.society_id is distinct from old.society_id or old.status = 'rejected')) then
        raise exception 'Not allowed to change your own status';
      end if;
    elsif not (caller_role = 'admin' and caller_status = 'active'
               and old.society_id = caller_society and old.role <> 'super_admin') then
      raise exception 'Not allowed to change status';
    end if;
  end if;
  return new;
end $$;

-- ── 5. Sign-up: always a PENDING resident; society from a valid code ───────
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_society uuid;
begin
  -- Preferred: a join code. Fallback: society_id from the sign-up link.
  select s.id into v_society from public.societies s
   where s.join_code = upper(trim(coalesce(new.raw_user_meta_data->>'join_code', '')));
  if v_society is null then
    begin
      select s.id into v_society from public.societies s
       where s.id = nullif(new.raw_user_meta_data->>'society_id', '')::uuid;
    exception when others then v_society := null;
    end;
  end if;

  insert into public.users (id, email, name, role, society_id, status)
  values (new.id, new.email,
          left(coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)), 100),
          'resident', v_society, 'pending')
  on conflict (id) do nothing;
  return new;
end $$;

-- ── 6. Join a society later (logged-in user without a society) ─────────────
create or replace function public.join_society_with_code(p_code text)
returns table (society_id uuid, society_name text)
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_name text; v_me public.users%rowtype;
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

  update public.users set society_id = v_id, status = 'pending' where id = auth.uid();
  return query select v_id, v_name;
end $$;
revoke all on function public.join_society_with_code(text) from public, anon;
grant execute on function public.join_society_with_code(text) to authenticated;

-- Name of the caller's society even while pending (for the "waiting" screen).
create or replace function public.my_society_name() returns text
language sql stable security definer set search_path = public as $$
  select s.name from public.users u join public.societies s on s.id = u.society_id
  where u.id = auth.uid()
$$;
revoke all on function public.my_society_name() from public, anon;
grant execute on function public.my_society_name() to authenticated;

-- ── 7. Tell the society's admins about new pending residents ───────────────
create or replace function public.notify_admins_pending_resident() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending' and new.society_id is not null
     and (tg_op = 'INSERT' or old.status is distinct from new.status
          or old.society_id is distinct from new.society_id) then
    insert into public.notifications (user_id, title, body, data)
    select a.id, 'New resident awaiting approval',
           coalesce(new.name, new.email) || ' wants to join. Approve them in Users.',
           jsonb_build_object('type', 'approval', 'id', new.id)
    from public.users a
    where a.society_id = new.society_id and a.role = 'admin' and a.status = 'active';
  end if;
  return new;
end $$;
drop trigger if exists notify_admins_pending_resident on public.users;
create trigger notify_admins_pending_resident after insert or update of status, society_id on public.users
  for each row execute function public.notify_admins_pending_resident();

-- ── 8. Existing notification triggers: only ACTIVE residents ───────────────
create or replace function public.notify_on_new_poll() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, title, body, data)
  select id, 'New Society Poll', new.question, jsonb_build_object('type', 'poll', 'id', new.id)
  from public.users
  where society_id = new.society_id and role = 'resident' and status = 'active';
  return new;
end $$;

create or replace function public.notify_on_new_notice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, title, body, data)
  select id, 'New Notice: ' || new.title, left(new.body, 100),
         jsonb_build_object('type', 'notice', 'id', new.id)
  from public.users
  where society_id = new.society_id and role = 'resident' and status = 'active';
  return new;
end $$;

create or replace function public.notify_on_visitor_entry() returns trigger
language plpgsql security definer set search_path = public as $$
declare resident_id uuid;
begin
  select id into resident_id from public.users
   where apartment_number = new.flat_number and society_id = new.society_id and status = 'active'
   limit 1;
  if resident_id is not null then
    insert into public.notifications (user_id, title, body, data)
    values (resident_id, 'New Visitor Alert',
            new.name || ' has arrived for ' || coalesce(new.purpose, 'a visit'),
            jsonb_build_object('type', 'visitor', 'id', new.id));
  end if;
  return new;
end $$;

create or replace function public.notify_on_parking_allotment() returns trigger
language plpgsql security definer set search_path = public as $$
declare resident_id uuid;
begin
  if (new.flat_id is not null and (old.flat_id is null or old.flat_id != new.flat_id)) then
    select id into resident_id from public.users
     where apartment_number = new.flat_id and society_id = new.society_id and status = 'active'
     limit 1;
    if resident_id is not null then
      insert into public.notifications (user_id, title, body, data)
      values (resident_id, 'Parking Slot Allotted',
              'Slot ' || new.slot_number || ' has been allotted to your flat.',
              jsonb_build_object('type', 'amenity', 'id', new.id));
    end if;
  end if;
  return new;
end $$;

commit;

-- Your societies and their join codes:
select name, join_code from public.societies order by name;
