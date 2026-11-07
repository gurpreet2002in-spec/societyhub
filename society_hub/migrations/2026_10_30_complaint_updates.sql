-- ============================================================================
-- SocietyHub — complaint UPDATE THREAD (comments + status history)
-- ============================================================================
-- Requires 2026_10_30_secure_rls.sql and 2026_10_30_society_codes_approval.sql.
-- Run in Supabase → SQL Editor (paste everything, Run). Safe to re-run.
--
-- • complaint_comments: one timeline per complaint. The resident who raised it
--   and the society's admins can read it and post comments.
-- • Status changes (Open → In Progress → Resolved, Escalated) are made by
--   admins through update_complaint_status(), which also writes a timeline
--   entry, so the history can't be edited afterwards.
-- • Each new entry notifies the other side (resident ↔ admins).
-- • Existing complaints get tidy status/priority values (e.g. 'high' → 'High').
-- ============================================================================

begin;

-- ── 1. Tidy existing values ────────────────────────────────────────────────
update public.complaints set status = case lower(trim(coalesce(status, '')))
    when 'resolved' then 'Resolved'
    when 'escalated' then 'Escalated'
    when 'in_progress' then 'In Progress'
    when 'in progress' then 'In Progress'
    when 'investigating' then 'In Progress'
    when 'scheduled' then 'In Progress'
    else 'Open' end;
update public.complaints set priority = case lower(trim(coalesce(priority, '')))
    when 'low' then 'Low' when 'high' then 'High' when 'critical' then 'Critical'
    else 'Medium' end;

-- ── 2. Timeline table ──────────────────────────────────────────────────────
create table if not exists public.complaint_comments (
  id            uuid primary key default gen_random_uuid(),
  complaint_id  uuid not null references public.complaints(id) on delete cascade,
  user_id       uuid references public.users(id) on delete set null default auth.uid(),
  author_name   text,
  author_role   text,
  body          text check (body is null or char_length(body) <= 2000),
  status_change text,
  created_at    timestamptz not null default now()
);
create index if not exists complaint_comments_complaint_idx
  on public.complaint_comments (complaint_id, created_at);

alter table public.complaint_comments enable row level security;

-- Who may see a complaint's thread: the resident who raised it, and admins of its society.
create or replace function public.can_see_complaint(p_complaint uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.complaints c
    where c.id = p_complaint
      and (c.user_id = auth.uid() or public.is_society_admin(c.society_id) or public.is_super_admin())
  )
$$;
revoke all on function public.can_see_complaint(uuid) from public, anon;
grant execute on function public.can_see_complaint(uuid) to authenticated;

drop policy if exists "complaint_comments_select" on public.complaint_comments;
drop policy if exists "complaint_comments_insert" on public.complaint_comments;
drop policy if exists "super_admin_all" on public.complaint_comments;

create policy "complaint_comments_select" on public.complaint_comments
  for select to authenticated using (public.can_see_complaint(complaint_id));

-- Plain comments only; status entries come from update_complaint_status().
create policy "complaint_comments_insert" on public.complaint_comments
  for insert to authenticated with check (
    user_id = auth.uid()
    and status_change is null
    and body is not null and length(trim(body)) > 0
    and public.can_see_complaint(complaint_id)
  );

create policy "super_admin_all" on public.complaint_comments
  for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
-- No update/delete policies: the timeline is a permanent record.

-- Author name/role are filled in by the database (the app can't fake them).
create or replace function public.fill_comment_author() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then new.user_id := auth.uid(); end if;
  select u.name, u.role into new.author_name, new.author_role
    from public.users u where u.id = new.user_id;
  new.created_at := now();
  return new;
end $$;
drop trigger if exists fill_comment_author on public.complaint_comments;
create trigger fill_comment_author before insert on public.complaint_comments
  for each row execute function public.fill_comment_author();

-- ── 3. Admin status change (with optional note) ────────────────────────────
create or replace function public.update_complaint_status(
  p_complaint_id uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_society uuid; v_old text;
begin
  if p_status not in ('Open', 'In Progress', 'Escalated', 'Resolved') then
    raise exception 'Unknown status: %', p_status;
  end if;
  select society_id, status into v_society, v_old from public.complaints where id = p_complaint_id;
  if v_society is null then raise exception 'Complaint not found'; end if;
  if not (public.is_society_admin(v_society) or public.is_super_admin()) then
    raise exception 'Only the society admin can change the status';
  end if;
  if v_old is distinct from p_status then
    update public.complaints set status = p_status where id = p_complaint_id;
  end if;
  insert into public.complaint_comments (complaint_id, user_id, body, status_change)
  values (p_complaint_id, auth.uid(), nullif(trim(coalesce(p_note, '')), ''),
          case when v_old is distinct from p_status then p_status end);
end $$;
revoke all on function public.update_complaint_status(uuid, text, text) from public, anon;
grant execute on function public.update_complaint_status(uuid, text, text) to authenticated;

-- ── 4. Notify the other side ───────────────────────────────────────────────
create or replace function public.notify_on_complaint_comment() returns trigger
language plpgsql security definer set search_path = public as $$
declare c record; v_title text; v_body text;
begin
  select id, title, user_id, society_id into c from public.complaints where id = new.complaint_id;
  if c.id is null then return new; end if;

  if new.status_change is not null then
    v_title := 'Complaint ' || lower(new.status_change);
    v_body  := '"' || c.title || '" is now ' || new.status_change
               || coalesce(': ' || left(new.body, 80), '');
  else
    v_title := 'New update on your complaint';
    v_body  := coalesce(new.author_name, 'Someone') || ' on "' || c.title || '": ' || left(new.body, 80);
  end if;

  if new.user_id is distinct from c.user_id then
    -- Admin wrote → tell the resident who raised it.
    insert into public.notifications (user_id, title, body, data)
    values (c.user_id, v_title, v_body, jsonb_build_object('type', 'complaint', 'id', c.id));
  else
    -- Resident wrote → tell the society's admins.
    insert into public.notifications (user_id, title, body, data)
    select a.id, 'Resident replied on a complaint', v_body,
           jsonb_build_object('type', 'complaint', 'id', c.id)
    from public.users a
    where a.society_id = c.society_id and a.role = 'admin' and a.status = 'active';
  end if;
  return new;
end $$;
drop trigger if exists notify_on_complaint_comment on public.complaint_comments;
create trigger notify_on_complaint_comment after insert on public.complaint_comments
  for each row execute function public.notify_on_complaint_comment();

grant select, insert on public.complaint_comments to authenticated;

commit;

notify pgrst, 'reload schema';
