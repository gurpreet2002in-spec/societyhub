-- ============================================================================
-- SocietyHub — clear old ACTIVITY data for ONE society (Ekta Society)
-- ============================================================================
-- Deletes, for that society only:
--   complaints, invoices/bills, visitors, vehicle logs, daily help (+ attendance),
--   notices, polls (+ votes), amenity bookings, marketplace listings,
--   and the notifications of that society's users.
-- KEEPS: the society itself, all user accounts, amenities, parking slots,
--   residents' saved vehicles, and every other society's data.
--
-- A copy of every deleted row is saved first in the private schema
-- "cleanup_backup" (not reachable from the app). The UNDO block at the bottom
-- puts it back.
--
-- HOW TO RUN (Supabase → SQL Editor):
--   1. Run STEP 1 alone (select it, then Run). Check the society row and counts.
--   2. If the slug isn't 'ekta_society', change it in STEP 2 (one place).
--   3. Run STEP 2 alone. It is all-or-nothing: on any error nothing is deleted.
-- ============================================================================


-- ── STEP 1: PREVIEW (changes nothing) ──────────────────────────────────────
select s.id, s.name, s.slug,
  (select count(*) from complaints  c where c.society_id = s.id) as complaints,
  (select count(*) from invoices    i where i.society_id = s.id) as invoices,
  (select count(*) from visitors    v where v.society_id = s.id) as visitors,
  (select count(*) from vehicle_logs l where l.society_id = s.id) as vehicle_logs,
  (select count(*) from daily_help  h where h.society_id = s.id) as daily_help,
  (select count(*) from notices     n where n.society_id = s.id) as notices,
  (select count(*) from polls       p where p.society_id = s.id) as polls,
  (select count(*) from bookings b join amenities a on a.id = b.amenity_id where a.society_id = s.id) as bookings,
  (select count(*) from marketplace m where m.society_id = s.id) as marketplace,
  (select count(*) from notifications x join users u on u.id = x.user_id where u.society_id = s.id) as notifications
from societies s
order by s.name;


-- ── STEP 2: BACK UP, THEN DELETE ───────────────────────────────────────────
begin;

create temp table cleanup_target on commit drop as
  select id from public.societies where slug = 'ekta_society';   -- ← the only line to edit

do $$
begin
  if (select count(*) from cleanup_target) <> 1 then
    raise exception 'Society not found: check the slug in STEP 2 against the STEP 1 results';
  end if;
end $$;

create schema if not exists cleanup_backup;
revoke all on schema cleanup_backup from public, anon, authenticated;

-- Backups (kept if this is re-run; a re-run adds nothing new because the rows are gone)
create table if not exists cleanup_backup.complaints      as select * from public.complaints      with no data;
create table if not exists cleanup_backup.invoices        as select * from public.invoices        with no data;
create table if not exists cleanup_backup.visitors        as select * from public.visitors        with no data;
create table if not exists cleanup_backup.vehicle_logs    as select * from public.vehicle_logs    with no data;
create table if not exists cleanup_backup.daily_help      as select * from public.daily_help      with no data;
create table if not exists cleanup_backup.help_attendance as select * from public.help_attendance with no data;
create table if not exists cleanup_backup.notices         as select * from public.notices         with no data;
create table if not exists cleanup_backup.polls           as select * from public.polls           with no data;
create table if not exists cleanup_backup.poll_votes      as select * from public.poll_votes      with no data;
create table if not exists cleanup_backup.bookings        as select * from public.bookings        with no data;
create table if not exists cleanup_backup.marketplace     as select * from public.marketplace     with no data;
create table if not exists cleanup_backup.notifications   as select * from public.notifications   with no data;

insert into cleanup_backup.complaints      select * from public.complaints   where society_id in (select id from cleanup_target);
insert into cleanup_backup.invoices        select * from public.invoices     where society_id in (select id from cleanup_target);
insert into cleanup_backup.visitors        select * from public.visitors     where society_id in (select id from cleanup_target);
insert into cleanup_backup.vehicle_logs    select * from public.vehicle_logs where society_id in (select id from cleanup_target);
insert into cleanup_backup.daily_help      select * from public.daily_help   where society_id in (select id from cleanup_target);
insert into cleanup_backup.help_attendance select a.* from public.help_attendance a
  join public.daily_help h on h.id = a.help_id where h.society_id in (select id from cleanup_target);
insert into cleanup_backup.notices         select * from public.notices      where society_id in (select id from cleanup_target);
insert into cleanup_backup.polls           select * from public.polls        where society_id in (select id from cleanup_target);
insert into cleanup_backup.poll_votes      select v.* from public.poll_votes v
  join public.polls p on p.id = v.poll_id where p.society_id in (select id from cleanup_target);
insert into cleanup_backup.bookings        select b.* from public.bookings b
  join public.amenities a on a.id = b.amenity_id where a.society_id in (select id from cleanup_target);
insert into cleanup_backup.marketplace     select * from public.marketplace  where society_id in (select id from cleanup_target);
insert into cleanup_backup.notifications   select x.* from public.notifications x
  join public.users u on u.id = x.user_id where u.society_id in (select id from cleanup_target);

-- Deletes (children first)
delete from public.help_attendance a using public.daily_help h
  where h.id = a.help_id and h.society_id in (select id from cleanup_target);
delete from public.poll_votes v using public.polls p
  where p.id = v.poll_id and p.society_id in (select id from cleanup_target);
delete from public.bookings b using public.amenities a
  where a.id = b.amenity_id and a.society_id in (select id from cleanup_target);
delete from public.notifications x using public.users u
  where u.id = x.user_id and u.society_id in (select id from cleanup_target);
delete from public.complaints   where society_id in (select id from cleanup_target);
delete from public.invoices     where society_id in (select id from cleanup_target);
delete from public.visitors     where society_id in (select id from cleanup_target);
delete from public.vehicle_logs where society_id in (select id from cleanup_target);
delete from public.daily_help   where society_id in (select id from cleanup_target);
delete from public.notices      where society_id in (select id from cleanup_target);
delete from public.polls        where society_id in (select id from cleanup_target);
delete from public.marketplace  where society_id in (select id from cleanup_target);

commit;

-- Re-run STEP 1 afterwards: the Ekta row should show 0 everywhere.


-- ── UNDO (only if you need the data back) ──────────────────────────────────
-- Remove the "--" in front of each line below, select them, Run.
-- begin;
-- insert into public.complaints      select * from cleanup_backup.complaints      on conflict do nothing;
-- insert into public.invoices        select * from cleanup_backup.invoices        on conflict do nothing;
-- insert into public.visitors        select * from cleanup_backup.visitors        on conflict do nothing;
-- insert into public.vehicle_logs    select * from cleanup_backup.vehicle_logs    on conflict do nothing;
-- insert into public.daily_help      select * from cleanup_backup.daily_help      on conflict do nothing;
-- insert into public.help_attendance select * from cleanup_backup.help_attendance on conflict do nothing;
-- insert into public.notices         select * from cleanup_backup.notices         on conflict do nothing;
-- insert into public.polls           select * from cleanup_backup.polls           on conflict do nothing;
-- insert into public.poll_votes      select * from cleanup_backup.poll_votes      on conflict do nothing;
-- insert into public.bookings        select * from cleanup_backup.bookings        on conflict do nothing;
-- insert into public.marketplace     select * from cleanup_backup.marketplace     on conflict do nothing;
-- insert into public.notifications   select * from cleanup_backup.notifications   on conflict do nothing;
-- commit;
--
-- Once you're sure you don't need it:  drop schema cleanup_backup cascade;
