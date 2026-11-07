-- ============================================================================
-- SocietyHub — VISITOR APPROVAL from the flat (run once in Supabase → SQL Editor)
-- ============================================================================
-- Requires 2026_10_31_push_notifications.sql. Safe to re-run.
--
--  Flow: guard enters the visitor and taps "Ask resident" →
--        every approved resident of that flat / house gets a ringing,
--        call-style alert with Approve / Decline →
--        the first answer wins and shows on the guard's screen instantly →
--        guard lets the visitor in (or turns them away).
--
--  • Only residents of THAT flat can answer (checked in the database).
--  • Nobody can fake an answer: approval can only be set through
--    respond_to_visitor(), which records who answered and when.
-- ============================================================================

begin;

-- ── 1. Columns ─────────────────────────────────────────────────────────────
alter table public.visitors add column if not exists approval_status text;     -- pending | approved | rejected
alter table public.visitors add column if not exists requested_at    timestamptz;
alter table public.visitors add column if not exists decided_by      uuid references public.users(id);
alter table public.visitors add column if not exists decided_by_name text;
alter table public.visitors add column if not exists decided_at      timestamptz;
alter table public.visitors add column if not exists decision_note   text;
alter table public.visitors add column if not exists guard_id        uuid references public.users(id);
alter table public.visitors add column if not exists vehicle_number  text;
alter table public.visitors add column if not exists checked_in_at   timestamptz;
alter table public.visitors drop constraint if exists visitors_approval_status_check;
alter table public.visitors add constraint visitors_approval_status_check
  check (approval_status is null or approval_status in ('pending', 'approved', 'rejected'));
create index if not exists visitors_pending_idx on public.visitors (society_id, flat_number)
  where approval_status = 'pending';

-- ── 2. Guard asks the flat ─────────────────────────────────────────────────
create or replace function public.request_visitor_approval(
  p_name text, p_mobile text, p_purpose text, p_flat text, p_vehicle text default null)
returns table (visitor_id uuid, residents int)
language plpgsql security definer set search_path = public as $$
declare v_sid uuid := public.auth_society(); v_flat text; v_id uuid; v_n int;
begin
  if v_sid is null or not public.is_society_staff(v_sid) then
    raise exception 'Only the gate guard or society admin can ask for approval';
  end if;
  if nullif(trim(coalesce(p_name, '')), '') is null then raise exception 'Enter the visitor''s name'; end if;
  v_flat := public.normalize_flat(p_flat);
  if v_flat is null then raise exception 'Enter the flat / house number'; end if;

  select count(*) into v_n from public.users
   where society_id = v_sid and status = 'active' and apartment_number = v_flat
     and role in ('resident', 'admin');

  insert into public.visitors (name, mobile, purpose, flat_number, vehicle_number, society_id,
                               status, approval_status, requested_at, guard_id, created_by)
  values (left(trim(p_name), 80), left(trim(coalesce(p_mobile, '')), 20),
          left(trim(coalesce(p_purpose, '')), 80), v_flat,
          nullif(left(upper(trim(coalesce(p_vehicle, ''))), 20), ''), v_sid,
          'Awaiting approval', 'pending', now(), auth.uid(), auth.uid())
  returning id into v_id;

  return query select v_id, v_n;
end $$;
revoke all on function public.request_visitor_approval(text, text, text, text, text) from public, anon;
grant execute on function public.request_visitor_approval(text, text, text, text, text) to authenticated;

-- Guard: ring the flat again (no answer yet).
create or replace function public.reask_visitor_approval(p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.visitors set requested_at = now()
   where id = p_id and approval_status = 'pending' and public.is_society_staff(society_id);
  if not found then raise exception 'This request was already answered or is not yours'; end if;
end $$;
revoke all on function public.reask_visitor_approval(uuid) from public, anon;
grant execute on function public.reask_visitor_approval(uuid) to authenticated;

-- ── 3. Resident answers ────────────────────────────────────────────────────
create or replace function public.respond_to_visitor(p_id uuid, p_approve boolean, p_note text default null)
returns table (approval_status text, decided_by_name text, already_answered boolean)
language plpgsql security definer set search_path = public as $$
declare v public.visitors%rowtype; me public.users%rowtype;
begin
  select * into me from public.users where id = auth.uid();
  select * into v from public.visitors where id = p_id for update;
  if v.id is null then raise exception 'Visitor request not found'; end if;
  if me.id is null or me.status <> 'active' or me.society_id is distinct from v.society_id
     or me.apartment_number is null or me.apartment_number is distinct from v.flat_number then
    raise exception 'This visitor is not for your flat / house';
  end if;
  if v.approval_status is distinct from 'pending' then
    return query select v.approval_status, v.decided_by_name, true;   -- someone else answered first
    return;
  end if;
  if v.status is distinct from 'Awaiting approval' then
    raise exception 'The guard has already handled this visitor (%).', v.status;
  end if;
  if v.requested_at < now() - interval '30 minutes' then
    raise exception 'This request has expired. Ask the guard to send it again.';
  end if;

  perform set_config('app.visitor_decision', 'on', true);
  update public.visitors set
    approval_status = case when p_approve then 'approved' else 'rejected' end,
    status          = case when p_approve then 'Approved' else 'Declined' end,
    decided_by      = me.id,
    decided_by_name = left(coalesce(me.name, 'Resident'), 80),
    decided_at      = now(),
    decision_note   = nullif(left(trim(coalesce(p_note, '')), 200), '')
  where id = p_id;

  return query select case when p_approve then 'approved' else 'rejected' end,
                      left(coalesce(me.name, 'Resident'), 80), false;
end $$;
revoke all on function public.respond_to_visitor(uuid, boolean, text) from public, anon;
grant execute on function public.respond_to_visitor(uuid, boolean, text) to authenticated;

-- ── 4. Answers can't be faked by direct table edits ────────────────────────
create or replace function public.guard_visitor_decision() returns trigger
language plpgsql as $$
begin
  if auth.uid() is null then return new; end if;   -- SQL editor / service role
  if (new.approval_status is distinct from old.approval_status
      or new.decided_by is distinct from old.decided_by
      or new.decided_by_name is distinct from old.decided_by_name
      or new.decided_at is distinct from old.decided_at)
     and coalesce(current_setting('app.visitor_decision', true), '') <> 'on' then
    raise exception 'Only the flat''s residents can approve or decline a visitor';
  end if;
  return new;
end $$;
drop trigger if exists guard_visitor_decision on public.visitors;
create trigger guard_visitor_decision before update on public.visitors
  for each row execute function public.guard_visitor_decision();

create or replace function public.guard_visitor_insert() returns trigger
language plpgsql as $$
begin
  if auth.uid() is null then return new; end if;
  -- New rows may only start as "pending" (via the guard function) or with no approval at all.
  if new.approval_status is not null and new.approval_status <> 'pending' then
    raise exception 'Not allowed';
  end if;
  if new.approval_status = 'pending' and not public.is_society_staff(new.society_id) then
    raise exception 'Not allowed';
  end if;
  new.decided_by := null; new.decided_by_name := null; new.decided_at := null;
  return new;
end $$;
drop trigger if exists guard_visitor_insert on public.visitors;
create trigger guard_visitor_insert before insert on public.visitors
  for each row execute function public.guard_visitor_insert();

-- ── 5. Notifications ───────────────────────────────────────────────────────
-- Ring the flat when the guard asks (and when they ask again);
-- tell the guard as soon as someone answers.
create or replace function public.notify_visitor_approval() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_body text;
begin
  if new.approval_status = 'pending'
     and (tg_op = 'INSERT' or new.requested_at is distinct from old.requested_at) then
    v_body := new.name
      || coalesce(' (' || nullif(new.purpose, '') || ')', '')
      || ' is at the gate for ' || new.flat_number || '. Tap to approve or decline.';
    insert into public.notifications (user_id, title, body, data)
    select u.id, 'Visitor at the gate', v_body,
           jsonb_build_object('type', 'visitor_approval', 'id', new.id,
                              'name', new.name, 'purpose', coalesce(new.purpose, ''),
                              'flat', new.flat_number)
      from public.users u
     where u.society_id = new.society_id and u.status = 'active'
       and u.apartment_number = new.flat_number and u.role in ('resident', 'admin');

  elsif tg_op = 'UPDATE' and old.approval_status = 'pending'
        and new.approval_status in ('approved', 'rejected') and new.guard_id is not null then
    insert into public.notifications (user_id, title, body, data)
    values (new.guard_id,
            case when new.approval_status = 'approved' then 'Entry approved ✓' else 'Entry declined ✗' end,
            new.name || ' for ' || new.flat_number || ' — '
              || case when new.approval_status = 'approved' then 'approved' else 'declined' end
              || ' by ' || coalesce(new.decided_by_name, 'resident')
              || coalesce(': ' || new.decision_note, ''),
            jsonb_build_object('type', 'visitor_decision', 'id', new.id));
  end if;
  return new;
end $$;
drop trigger if exists notify_visitor_approval on public.visitors;
create trigger notify_visitor_approval after insert or update of approval_status, requested_at on public.visitors
  for each row execute function public.notify_visitor_approval();

-- The old "visitor has arrived" alert stays for walk-ins, but not for
-- approval requests (the ringing alert replaces it).
create or replace function public.notify_on_visitor_entry() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.approval_status = 'pending' then return new; end if;
  insert into public.notifications (user_id, title, body, data)
  select u.id, 'New Visitor Alert',
         new.name || ' has arrived for ' || coalesce(new.purpose, 'a visit'),
         jsonb_build_object('type', 'visitor', 'id', new.id)
  from public.users u
  where u.society_id = new.society_id and u.status = 'active'
    and u.apartment_number is not null and u.apartment_number = new.flat_number;
  return new;
end $$;

commit;

-- ── 6. Live status for the guard and the residents (Realtime) ──────────────
do $$ begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'visitors'
  ) then
    execute 'alter publication supabase_realtime add table public.visitors';
  end if;
exception when undefined_object then
  raise notice 'Realtime publication not found — live status skipped.';
end $$;

notify pgrst, 'reload schema';
