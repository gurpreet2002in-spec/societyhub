-- Migration to enable Push Notifications
-- Add fcm_token for push notifications
alter table public.users add column if not exists fcm_token text;

-- Add data column to notifications for deep linking
alter table public.notifications add column if not exists data jsonb default '{}'::jsonb;

-- Create a function to trigger a notification when a visitor is logged
create or replace function notify_on_visitor_entry()
returns trigger language plpgsql security definer as $$
declare
  resident_id uuid;
begin
  -- Find the resident for the flat
  select id into resident_id from public.users
  where apartment_number = new.flat_number
  and society_id = new.society_id
  limit 1;

  if resident_id is not null then
    insert into public.notifications (user_id, title, body, data)
    values (
      resident_id,
      'New Visitor Alert',
      new.name || ' has arrived for ' || new.purpose,
      jsonb_build_object('type', 'visitor', 'id', new.id)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists on_visitor_entry on visitors;
create trigger on_visitor_entry
  after insert on visitors
  for each row execute procedure notify_on_visitor_entry();

-- Create a function to trigger a notification when a poll is created
create or replace function notify_on_new_poll()
returns trigger language plpgsql security definer as $$
begin
  -- Insert notification for all residents in the society
  insert into public.notifications (user_id, title, body, data)
  select id, 'New Society Poll', new.question, jsonb_build_object('type', 'poll', 'id', new.id)
  from public.users
  where society_id = new.society_id
  and role = 'resident';
  return new;
end;
$$;

drop trigger if exists on_new_poll on polls;
create trigger on_new_poll
  after insert on polls
  for each row execute procedure notify_on_new_poll();

-- Create a function to trigger a notification when an invoice is marked as Paid (approval)
create or replace function notify_on_payment_approval()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'Paid' and old.status != 'Paid' then
    insert into public.notifications (user_id, title, body, data)
    values (
      new.user_id,
      'Payment Approved',
      'Your payment for "' || new.title || '" has been approved.',
      jsonb_build_object('type', 'payment', 'id', new.id)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists on_payment_approval on invoices;
create trigger on_payment_approval
  after update on invoices
  for each row execute procedure notify_on_payment_approval();

-- Create a function to trigger a notification when a notice is created
create or replace function notify_on_new_notice()
returns trigger language plpgsql security definer as $$
begin
  insert into public.notifications (user_id, title, body, data)
  select id, 'New Notice: ' || new.title, left(new.body, 100), jsonb_build_object('type', 'notice', 'id', new.id)
  from public.users
  where society_id = new.society_id
  and role = 'resident';
  return new;
end;
$$;

drop trigger if exists on_new_notice on notices;
create trigger on_new_notice
  after insert on notices
  for each row execute procedure notify_on_new_notice();

-- Create a function to trigger a notification when a parking slot is updated (allotted)
create or replace function notify_on_parking_allotment()
returns trigger language plpgsql security definer as $$
declare
  resident_id uuid;
begin
  if (new.flat_id is not null and (old.flat_id is null or old.flat_id != new.flat_id)) then
    -- Find the resident for the flat
    select id into resident_id from public.users
    where apartment_number = new.flat_id
    and society_id = new.society_id
    limit 1;

    if resident_id is not null then
      insert into public.notifications (user_id, title, body, data)
      values (
        resident_id,
        'Parking Slot Allotted',
        'Slot ' || new.slot_number || ' has been allotted to your flat.',
        jsonb_build_object('type', 'amenity', 'id', new.id)
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists on_parking_allotment on parking_slots;
create trigger on_parking_allotment
  after update on parking_slots
  for each row execute procedure notify_on_parking_allotment();