-- ============================================================================
-- SocietyHub — GATE PASSES (code + QR) and SOS (run once in Supabase → SQL Editor)
-- ============================================================================
-- Requires 2026_10_31_visitor_approval.sql. Safe to re-run.
--
--  • A resident's pre-approved visitor pass now always carries the resident's
--    flat / house number and a 6-digit pass code (shown as a QR code too),
--    valid for 24 hours (or the time the resident picks). One use only.
--  • verify_visitor_pass(): the guard types or scans the code → sees who it is
--    for → lets them in. The resident is told when the guest arrives.
--  • raise_sos(): the guard (or anyone in the society) raises an emergency →
--    every admin and guard gets an alert with sound.
-- ============================================================================

begin;

-- ── 1. Pass columns ────────────────────────────────────────────────────────
alter table public.visitors add column if not exists pass_code text;
alter table public.visitors add column if not exists pass_valid_until timestamptz;
create index if not exists visitors_pass_code_idx on public.visitors (society_id, pass_code)
  where pass_code is not null;

-- ── 2. Pre-approved passes: right flat, unique code, expiry ────────────────
create or replace function public.prepare_visitor_pass() returns trigger
language plpgsql security definer set search_path = public as $$
declare me public.users%rowtype; v_code text; i int := 0;
begin
  if coalesce(new.status, '') <> 'Pre-approved' then return new; end if;

  if auth.uid() is not null then
    select * into me from public.users where id = auth.uid();
    new.created_by := auth.uid();
    new.society_id := coalesce(new.society_id, me.society_id);
    -- A resident can only make passes for their own flat / house.
    if me.role = 'resident' or new.flat_number is null then
      new.flat_number := me.apartment_number;
    end if;
  end if;
  if new.flat_number is null then
    raise exception 'Add your flat / house number to your profile before creating a pass';
  end if;

  -- 6-digit code, unique among this society's passes that are still valid.
  loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (
      select 1 from public.visitors
       where society_id = new.society_id and pass_code = v_code
         and status = 'Pre-approved' and coalesce(pass_valid_until, now()) > now());
    i := i + 1;
    if i > 20 then raise exception 'Could not create a pass code, please try again'; end if;
  end loop;
  new.pass_code := v_code;
  new.pass_valid_until := least(coalesce(new.pass_valid_until, now() + interval '24 hours'),
                                now() + interval '7 days');
  new.approval_status := null;
  return new;
end $$;
drop trigger if exists prepare_visitor_pass on public.visitors;
create trigger prepare_visitor_pass before insert on public.visitors
  for each row execute function public.prepare_visitor_pass();

-- Pass details can't be edited afterwards (only the guard's check-in changes it).
create or replace function public.guard_visitor_pass() returns trigger
language plpgsql as $$
begin
  if auth.uid() is null then return new; end if;
  if new.pass_code is distinct from old.pass_code
     or new.pass_valid_until is distinct from old.pass_valid_until then
    raise exception 'A pass code cannot be changed';
  end if;
  if old.pass_code is not null and new.flat_number is distinct from old.flat_number then
    raise exception 'A pass cannot be moved to another flat';
  end if;
  return new;
end $$;
drop trigger if exists guard_visitor_pass on public.visitors;
create trigger guard_visitor_pass before update on public.visitors
  for each row execute function public.guard_visitor_pass();

-- ── 3. Guard checks a pass ─────────────────────────────────────────────────
create or replace function public.verify_visitor_pass(p_code text)
returns table (id uuid, name text, mobile text, purpose text, flat_number text,
               created_by_name text, pass_valid_until timestamptz)
language plpgsql security definer set search_path = public as $$
declare v_sid uuid := public.auth_society(); v public.visitors%rowtype; v_code text;
begin
  if v_sid is null or not public.is_society_staff(v_sid) then
    raise exception 'Only the gate guard or society admin can check passes';
  end if;
  v_code := regexp_replace(coalesce(p_code, ''), '[^0-9]', '', 'g');
  if length(v_code) <> 6 then raise exception 'Enter the 6-digit pass code'; end if;

  select * into v from public.visitors x
   where x.society_id = v_sid and x.pass_code = v_code
   order by (x.status = 'Pre-approved') desc, x.created_at desc
   limit 1;
  if v.id is null then raise exception 'No pass found with code %', v_code; end if;
  if v.status <> 'Pre-approved' then
    raise exception 'This pass was already used (%)', coalesce(to_char(v.checked_in_at at time zone 'Asia/Kolkata', 'DD Mon HH24:MI'), v.status);
  end if;
  if v.pass_valid_until is not null and v.pass_valid_until < now() then
    raise exception 'This pass expired on %', to_char(v.pass_valid_until at time zone 'Asia/Kolkata', 'DD Mon HH24:MI');
  end if;

  return query
    select v.id, v.name, v.mobile, v.purpose, v.flat_number,
           (select u.name from public.users u where u.id = v.created_by), v.pass_valid_until;
end $$;
revoke all on function public.verify_visitor_pass(text) from public, anon;
grant execute on function public.verify_visitor_pass(text) to authenticated;

-- Tell the flat when their pre-approved guest walks in.
create or replace function public.notify_pass_used() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'Pre-approved' and new.status = 'Checked-in' then
    insert into public.notifications (user_id, title, body, data)
    select u.id, 'Your guest has arrived', new.name || ' entered the society with your pass.',
           jsonb_build_object('type', 'visitor', 'id', new.id)
      from public.users u
     where u.society_id = new.society_id and u.status = 'active'
       and u.apartment_number = new.flat_number;
  end if;
  return new;
end $$;
drop trigger if exists notify_pass_used on public.visitors;
create trigger notify_pass_used after update of status on public.visitors
  for each row execute function public.notify_pass_used();

-- ── 4. SOS ─────────────────────────────────────────────────────────────────
create table if not exists public.sos_alerts (
  id uuid primary key default gen_random_uuid(),
  society_id uuid not null references public.societies(id) on delete cascade,
  raised_by uuid references public.users(id),
  raised_by_name text,
  raised_by_role text,
  location text,
  message text,
  created_at timestamptz not null default now()
);
create index if not exists sos_alerts_society_idx on public.sos_alerts (society_id, created_at desc);
alter table public.sos_alerts enable row level security;
drop policy if exists "sos_select" on public.sos_alerts;
create policy "sos_select" on public.sos_alerts for select to authenticated using (
  public.is_society_staff(society_id) or raised_by = auth.uid()
);
revoke all on public.sos_alerts from anon;
revoke insert, update, delete on public.sos_alerts from authenticated;
grant select on public.sos_alerts to authenticated;

create or replace function public.raise_sos(p_message text default null)
returns int   -- how many people were alerted
language plpgsql security definer set search_path = public as $$
declare me public.users%rowtype; v_where text; v_msg text; v_n int; v_id uuid;
begin
  select * into me from public.users where id = auth.uid();
  if me.id is null or me.status <> 'active' or me.society_id is null then
    raise exception 'Only active members of a society can raise an SOS';
  end if;
  if exists (select 1 from public.sos_alerts
              where raised_by = me.id and created_at > now() - interval '1 minute') then
    raise exception 'SOS already sent. Help has been alerted.';
  end if;

  v_where := case when me.role = 'guard' then 'Gate'
                  else coalesce(me.apartment_number, 'Society') end;
  v_msg := nullif(left(trim(coalesce(p_message, '')), 200), '');

  insert into public.sos_alerts (society_id, raised_by, raised_by_name, raised_by_role, location, message)
  values (me.society_id, me.id, me.name, me.role, v_where, v_msg)
  returning id into v_id;

  insert into public.notifications (user_id, title, body, data)
  select u.id,
         '🚨 SOS — ' || v_where,
         coalesce(v_msg, 'Emergency') || ' • raised by ' || coalesce(me.name, 'a member')
           || case when me.contact_number is not null then ' (' || me.contact_number || ')' else '' end,
         jsonb_build_object('type', 'sos', 'id', v_id)
    from public.users u
   where u.society_id = me.society_id and u.status = 'active'
     and u.role in ('admin', 'guard') and u.id <> me.id;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function public.raise_sos(text) from public, anon;
grant execute on function public.raise_sos(text) to authenticated;

commit;

notify pgrst, 'reload schema';
