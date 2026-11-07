-- ============================================================================
-- SocietyHub — SECURITY HARDENING (run once in Supabase → SQL Editor)
-- ============================================================================
-- Replaces the old "Allow all for authenticated" rules, under which ANY
-- logged-in user could read/modify/delete every society's data and even make
-- themselves super_admin.
--
-- After this script:
--   • Every user only sees data from their own society.
--   • Residents only see their own invoices, complaints, daily help, bookings,
--     notifications and vehicles (plus their flat's visitors).
--   • Only society admins can manage users, billing, notices, polls,
--     amenities and parking for THEIR society.
--   • Guards manage visitors / vehicle logs / daily-help attendance for their
--     society only.
--   • Nobody can change their own role or move themselves to another society.
--   • Residents can no longer mark invoices "Paid" — they submit a payment for
--     review and an admin approves it.
--   • super_admin keeps full access (set it only from this SQL editor).
--
-- Safe to re-run. Run it in ONE go (select all → Run).
-- ============================================================================

begin;

-- ── 0. Schema additions used by the hardened app ───────────────────────────
alter table public.visitors add column if not exists created_by uuid references public.users(id) default auth.uid();
alter table public.users    add column if not exists fcm_token text;

-- Allowed values (protects against junk / unexpected roles)
alter table public.users drop constraint if exists users_role_check;
update public.users set role = lower(trim(role)) where role is not null;
update public.users set role = 'resident'
 where role is null or role not in ('resident','guard','admin','super_admin');
alter table public.users add constraint users_role_check
  check (role in ('resident','guard','admin','super_admin'));

alter table public.invoices drop constraint if exists invoices_status_check;
update public.invoices set status = 'Pending' where status is null
  or status not in ('Pending','Under Review','Paid','Overdue');
alter table public.invoices add constraint invoices_status_check
  check (status in ('Pending','Under Review','Paid','Overdue'));
alter table public.invoices add column if not exists payment_note text;
alter table public.invoices add column if not exists submitted_at timestamptz;

-- ── 1. Helper functions (SECURITY DEFINER avoids RLS recursion) ────────────
create or replace function public.auth_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.users where id = auth.uid()
$$;

create or replace function public.auth_society() returns uuid
language sql stable security definer set search_path = public as $$
  select society_id from public.users where id = auth.uid()
$$;

create or replace function public.auth_apartment() returns text
language sql stable security definer set search_path = public as $$
  select apartment_number from public.users where id = auth.uid()
$$;

create or replace function public.is_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'super_admin' from public.users where id = auth.uid()), false)
$$;

create or replace function public.is_society_admin(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'admin' and society_id = sid
                   from public.users where id = auth.uid()), false)
$$;

create or replace function public.is_society_staff(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role in ('admin','guard') and society_id = sid
                   from public.users where id = auth.uid()), false)
$$;

revoke all on function public.auth_role(), public.auth_society(), public.auth_apartment(),
  public.is_super_admin(), public.is_society_admin(uuid), public.is_society_staff(uuid) from anon;

-- ── 2. Drop EVERY existing policy on the app tables (clean slate) ──────────
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname from pg_policies
    where schemaname = 'public' and tablename in (
      'users','societies','complaints','invoices','visitors','daily_help',
      'help_attendance','amenities','bookings','notices','polls','poll_votes',
      'parking_slots','marketplace','notifications','platform_settings',
      'audit_logs','vehicle_logs','resident_vehicles')
  loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

-- Make sure RLS is ON everywhere (and forced, so table owners obey it too)
do $$
declare t text;
begin
  foreach t in array array[
    'users','societies','complaints','invoices','visitors','daily_help',
    'help_attendance','amenities','bookings','notices','polls','poll_votes',
    'parking_slots','marketplace','notifications','platform_settings',
    'audit_logs','vehicle_logs','resident_vehicles']
  loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);
    end if;
  end loop;
end $$;

-- Anonymous (not logged in) visitors get NO table access at all.
revoke all on all tables in schema public from anon;

-- ── 3. Super admin: full access to everything ──────────────────────────────
do $$
declare t text;
begin
  foreach t in array array[
    'users','societies','complaints','invoices','visitors','daily_help',
    'help_attendance','amenities','bookings','notices','polls','poll_votes',
    'parking_slots','marketplace','notifications','platform_settings',
    'audit_logs','vehicle_logs','resident_vehicles']
  loop
    if to_regclass('public.' || t) is not null then
      execute format(
        'create policy "super_admin_all" on public.%I for all to authenticated
           using (public.is_super_admin()) with check (public.is_super_admin())', t);
    end if;
  end loop;
end $$;

-- ── 4. USERS ───────────────────────────────────────────────────────────────
create policy "users_select" on public.users for select to authenticated using (
  id = auth.uid() or public.is_society_staff(society_id)
);
create policy "users_insert_self" on public.users for insert to authenticated with check (
  id = auth.uid() and role = 'resident'
);
create policy "users_update" on public.users for update to authenticated
  using (id = auth.uid() or public.is_society_admin(society_id))
  with check (id = auth.uid() or public.is_society_admin(society_id));
create policy "users_delete_admin" on public.users for delete to authenticated using (
  public.is_society_admin(society_id) and id <> auth.uid() and role <> 'super_admin'
);

-- Block privilege escalation even when an UPDATE is otherwise allowed.
create or replace function public.guard_user_changes() returns trigger
language plpgsql security definer set search_path = public as $$
declare caller_role text; caller_society uuid;
begin
  -- SQL editor / service role (no logged-in user) may do anything.
  if auth.uid() is null then return new; end if;
  select role, society_id into caller_role, caller_society from public.users where id = auth.uid();
  if caller_role = 'super_admin' then return new; end if;

  if new.id is distinct from old.id then
    raise exception 'Changing user id is not allowed';
  end if;

  if new.role is distinct from old.role then
    if not (caller_role = 'admin' and old.society_id = caller_society
            and new.role in ('resident','guard','admin') and old.role <> 'super_admin'
            and old.id <> auth.uid()) then
      raise exception 'Not allowed to change role';
    end if;
  end if;

  if new.society_id is distinct from old.society_id then
    -- A brand-new resident may join a society once (sign-up link). Nothing else.
    if not (old.society_id is null and old.id = auth.uid() and new.role = 'resident') then
      raise exception 'Not allowed to change society';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists guard_user_changes on public.users;
create trigger guard_user_changes before update on public.users
  for each row execute function public.guard_user_changes();

-- New sign-ups are ALWAYS residents, whatever the client sends. The society
-- from the sign-up link is applied here too, so it also works when e-mail
-- confirmation is switched on (it is only accepted if that society exists).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_society uuid;
begin
  begin
    select s.id into v_society from public.societies s
     where s.id = nullif(new.raw_user_meta_data->>'society_id', '')::uuid;
  exception when others then v_society := null;
  end;
  insert into public.users (id, email, name, role, society_id)
  values (new.id, new.email,
          left(coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)), 100),
          'resident', v_society)
  on conflict (id) do nothing;
  return new;
end $$;

-- ── 5. SOCIETIES ───────────────────────────────────────────────────────────
create policy "societies_select_own" on public.societies for select to authenticated using (
  id = public.auth_society()
);
create policy "societies_update_admin" on public.societies for update to authenticated
  using (public.is_society_admin(id)) with check (public.is_society_admin(id));

create or replace function public.guard_society_changes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_super_admin() then return new; end if;
  if new.subscription_plan is distinct from old.subscription_plan
     or new.subscription_status is distinct from old.subscription_status
     or new.slug is distinct from old.slug then
    raise exception 'Only the platform admin can change plan, status or link';
  end if;
  return new;
end $$;
drop trigger if exists guard_society_changes on public.societies;
create trigger guard_society_changes before update on public.societies
  for each row execute function public.guard_society_changes();

-- Public lookup used by the sign-up link (/my_society) — returns ONLY id+name.
create or replace function public.get_society_by_slug(p_slug text)
returns table (id uuid, name text, slug text)
language sql stable security definer set search_path = public as $$
  select s.id, s.name, s.slug from public.societies s
  where s.slug = p_slug and coalesce(s.subscription_status, 'active') = 'active'
  limit 1
$$;
grant execute on function public.get_society_by_slug(text) to anon, authenticated;

-- ── 6. COMPLAINTS ──────────────────────────────────────────────────────────
create policy "complaints_select" on public.complaints for select to authenticated using (
  user_id = auth.uid() or public.is_society_admin(society_id)
);
create policy "complaints_insert" on public.complaints for insert to authenticated with check (
  user_id = auth.uid() and society_id = public.auth_society()
);
create policy "complaints_update" on public.complaints for update to authenticated
  using (user_id = auth.uid() or public.is_society_admin(society_id))
  with check (society_id = public.auth_society());
create policy "complaints_delete" on public.complaints for delete to authenticated using (
  public.is_society_admin(society_id)
);

-- ── 7. INVOICES (residents read-only; payment via submit_invoice_payment) ──
create policy "invoices_select" on public.invoices for select to authenticated using (
  user_id = auth.uid() or public.is_society_admin(society_id)
);
create policy "invoices_admin_write" on public.invoices for all to authenticated
  using (public.is_society_admin(society_id))
  with check (public.is_society_admin(society_id));

create or replace function public.submit_invoice_payment(p_invoice_id uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.invoices
     set status = 'Under Review', submitted_at = now(), payment_note = left(p_note, 500)
   where id = p_invoice_id and user_id = auth.uid() and status in ('Pending','Overdue');
  if not found then raise exception 'Invoice not found or already submitted'; end if;
end $$;
revoke all on function public.submit_invoice_payment(uuid, text) from anon, public;
grant execute on function public.submit_invoice_payment(uuid, text) to authenticated;

-- ── 8. VISITORS ────────────────────────────────────────────────────────────
create policy "visitors_select" on public.visitors for select to authenticated using (
  public.is_society_staff(society_id)
  or (society_id = public.auth_society()
      and (created_by = auth.uid() or flat_number = public.auth_apartment()))
);
create policy "visitors_insert" on public.visitors for insert to authenticated with check (
  society_id = public.auth_society()
);
create policy "visitors_update" on public.visitors for update to authenticated
  using (public.is_society_staff(society_id) or created_by = auth.uid())
  with check (society_id = public.auth_society());
create policy "visitors_delete" on public.visitors for delete to authenticated using (
  public.is_society_staff(society_id)
);

-- ── 9. DAILY HELP + ATTENDANCE ─────────────────────────────────────────────
create policy "daily_help_rw" on public.daily_help for all to authenticated
  using (user_id = auth.uid() or public.is_society_staff(society_id))
  with check ((user_id = auth.uid() and society_id = public.auth_society())
              or public.is_society_staff(society_id));

create policy "help_attendance_rw" on public.help_attendance for all to authenticated
  using (exists (select 1 from public.daily_help h where h.id = help_id
                 and (h.user_id = auth.uid() or public.is_society_staff(h.society_id))))
  with check (exists (select 1 from public.daily_help h where h.id = help_id
                 and (h.user_id = auth.uid() or public.is_society_staff(h.society_id))));

-- ── 10. AMENITIES + BOOKINGS ───────────────────────────────────────────────
create policy "amenities_select" on public.amenities for select to authenticated using (
  society_id = public.auth_society()
);
create policy "amenities_admin_write" on public.amenities for all to authenticated
  using (public.is_society_admin(society_id)) with check (public.is_society_admin(society_id));

create policy "bookings_select" on public.bookings for select to authenticated using (
  user_id = auth.uid()
  or exists (select 1 from public.amenities a where a.id = amenity_id and public.is_society_admin(a.society_id))
);
create policy "bookings_insert" on public.bookings for insert to authenticated with check (
  user_id = auth.uid()
  and exists (select 1 from public.amenities a where a.id = amenity_id and a.society_id = public.auth_society())
);
create policy "bookings_update" on public.bookings for update to authenticated
  using (user_id = auth.uid()
         or exists (select 1 from public.amenities a where a.id = amenity_id and public.is_society_admin(a.society_id)))
  with check (exists (select 1 from public.amenities a where a.id = amenity_id and a.society_id = public.auth_society()));
create policy "bookings_delete" on public.bookings for delete to authenticated using (
  exists (select 1 from public.amenities a where a.id = amenity_id and public.is_society_admin(a.society_id))
);

-- ── 11. NOTICES + POLLS ────────────────────────────────────────────────────
create policy "notices_select" on public.notices for select to authenticated using (
  society_id = public.auth_society()
);
create policy "notices_admin_write" on public.notices for all to authenticated
  using (public.is_society_admin(society_id)) with check (public.is_society_admin(society_id));

create policy "polls_select" on public.polls for select to authenticated using (
  society_id = public.auth_society()
);
create policy "polls_admin_write" on public.polls for all to authenticated
  using (public.is_society_admin(society_id)) with check (public.is_society_admin(society_id));

create policy "poll_votes_select" on public.poll_votes for select to authenticated using (
  user_id = auth.uid()
  or exists (select 1 from public.polls p where p.id = poll_id and public.is_society_admin(p.society_id))
);
create policy "poll_votes_insert" on public.poll_votes for insert to authenticated with check (
  user_id = auth.uid()
  and exists (select 1 from public.polls p where p.id = poll_id and p.society_id = public.auth_society()
              and (p.ends_at is null or p.ends_at > now()))
);
create policy "poll_votes_update" on public.poll_votes for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid()
    and exists (select 1 from public.polls p where p.id = poll_id and (p.ends_at is null or p.ends_at > now())));

-- ── 12. PARKING + MARKETPLACE ──────────────────────────────────────────────
create policy "parking_select" on public.parking_slots for select to authenticated using (
  society_id = public.auth_society()
);
create policy "parking_admin_write" on public.parking_slots for all to authenticated
  using (public.is_society_admin(society_id)) with check (public.is_society_admin(society_id));

create policy "marketplace_select" on public.marketplace for select to authenticated using (
  society_id = public.auth_society()
);
create policy "marketplace_insert" on public.marketplace for insert to authenticated with check (
  user_id = auth.uid() and society_id = public.auth_society()
);
create policy "marketplace_update" on public.marketplace for update to authenticated
  using (user_id = auth.uid() or public.is_society_admin(society_id))
  with check (society_id = public.auth_society());
create policy "marketplace_delete" on public.marketplace for delete to authenticated using (
  user_id = auth.uid() or public.is_society_admin(society_id)
);

-- ── 13. NOTIFICATIONS (created only by DB triggers) ────────────────────────
create policy "notifications_own_select" on public.notifications for select to authenticated using (user_id = auth.uid());
create policy "notifications_own_update" on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "notifications_own_delete" on public.notifications for delete to authenticated using (user_id = auth.uid());

-- platform_settings & audit_logs: super_admin only (policy from section 3).

-- ── 14. GUARD TABLES ───────────────────────────────────────────────────────
do $$ begin
  if to_regclass('public.vehicle_logs') is not null then
    execute 'create policy "vehicle_logs_staff" on public.vehicle_logs for all to authenticated
      using (public.is_society_staff(society_id)) with check (public.is_society_staff(society_id))';
  end if;
  if to_regclass('public.resident_vehicles') is not null then
    execute 'create policy "resident_vehicles_own" on public.resident_vehicles for all to authenticated
      using (user_id = auth.uid())
      with check (user_id = auth.uid() and society_id = public.auth_society())';
    execute 'create policy "resident_vehicles_staff_read" on public.resident_vehicles for select to authenticated
      using (public.is_society_staff(society_id))';
  end if;
end $$;

-- ── 15. Pin search_path on the existing trigger functions ──────────────────
do $$
declare f text;
begin
  foreach f in array array['notify_on_visitor_entry','notify_on_new_poll',
    'notify_on_payment_approval','notify_on_new_notice','notify_on_parking_allotment']
  loop
    if exists (select 1 from pg_proc where proname = f and pronamespace = 'public'::regnamespace) then
      execute format('alter function public.%I() set search_path = public', f);
    end if;
  end loop;
end $$;

commit;

-- ── Quick self-check: every table should show rls_enabled = true ───────────
select c.relname as table_name, c.relrowsecurity as rls_enabled,
       (select count(*) from pg_policies p where p.tablename = c.relname and p.schemaname = 'public') as policies
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by 1;
