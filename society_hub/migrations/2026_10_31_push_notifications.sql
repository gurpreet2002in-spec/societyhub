-- ============================================================================
-- SocietyHub — PUSH NOTIFICATIONS with sound (run once in Supabase → SQL Editor)
-- ============================================================================
-- Safe to re-run. Run AFTER deploying the "send-push" Edge Function.
--
--  • Every new row in public.notifications (notice, poll, complaint, visitor,
--    parking, join request …) now also goes to the person's phone as a push
--    notification with the notification tone, via the send-push function.
--  • NEW: a new complaint notifies the society's admins.
--  • NEW: the in-app bell updates live (Realtime).
-- ============================================================================

create extension if not exists pg_net with schema extensions;

begin;

-- ── 1. Remember which notifications were already pushed (no double sends) ──
alter table public.notifications add column if not exists pushed_at timestamptz;
alter table public.notifications add column if not exists data jsonb default '{}'::jsonb;

-- ── 2. After a notification is saved, ask send-push to deliver it ──────────
create or replace function public.push_new_notification() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  -- Only when the person has a phone registered for push.
  if exists (select 1 from public.users where id = new.user_id and fcm_token is not null) then
    begin
      perform net.http_post(
        url     := 'https://dkrxwhjxxhdeordtrwvd.supabase.co/functions/v1/send-push',
        body    := jsonb_build_object('id', new.id),
        headers := '{"Content-Type": "application/json"}'::jsonb,
        timeout_milliseconds := 8000
      );
    exception when others then
      -- Never let a push problem stop the notice / complaint itself from saving.
      raise warning 'push_new_notification: %', sqlerrm;
    end;
  end if;
  return new;
end $$;
drop trigger if exists push_new_notification on public.notifications;
create trigger push_new_notification after insert on public.notifications
  for each row execute function public.push_new_notification();

-- ── 3. New complaint → the society's admins ────────────────────────────────
create or replace function public.notify_on_new_complaint() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_who text;
begin
  select coalesce(name, 'A resident')
         || coalesce(' (' || apartment_number || ')', '')
    into v_who
    from public.users where id = new.user_id;

  insert into public.notifications (user_id, title, body, data)
  select a.id,
         'New complaint: ' || left(coalesce(new.title, ''), 80),
         coalesce(v_who, 'A resident')
           || coalesce(' • ' || new.priority, '')
           || coalesce(' — ' || left(new.description, 100), ''),
         jsonb_build_object('type', 'complaint', 'id', new.id)
    from public.users a
   where a.society_id = new.society_id and a.role = 'admin' and a.status = 'active'
     and a.id is distinct from new.user_id;
  return new;
end $$;
drop trigger if exists notify_on_new_complaint on public.complaints;
create trigger notify_on_new_complaint after insert on public.complaints
  for each row execute function public.notify_on_new_complaint();

-- ── 4. Notices also reach guards (they keep the gate informed) ─────────────
create or replace function public.notify_on_new_notice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, title, body, data)
  select id, 'New Notice: ' || new.title, left(new.body, 100),
         jsonb_build_object('type', 'notice', 'id', new.id)
  from public.users
  where society_id = new.society_id and role in ('resident', 'guard') and status = 'active';
  return new;
end $$;

commit;

-- ── 5. Live bell: stream new notifications to the app ──────────────────────
-- (Each user only receives their own rows — Realtime follows the RLS rules.)
do $$ begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
  ) then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
exception when undefined_object then
  raise notice 'Realtime publication not found — live bell skipped (push still works).';
end $$;

notify pgrst, 'reload schema';
