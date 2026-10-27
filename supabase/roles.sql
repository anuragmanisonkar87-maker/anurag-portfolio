-- Role-based access for the portfolio database
-- Run AFTER schema.sql: Supabase Dashboard -> SQL Editor -> New query -> paste -> Run
--
-- Who can do what:
--   Public website (anon)  : add a contact message only. Cannot read anything.
--   Logged-in admin        : read, update, delete contact messages and payments.
--   Any other logged-in user: nothing.
--   Razorpay webhook        : writes payments via the service role (unchanged).

------------------------------------------------------------
-- 1) Roles table: which login has which role
------------------------------------------------------------
create table if not exists public.user_roles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  role       text not null check (role in ('admin')),   -- add more roles here later, e.g. 'viewer'
  created_at timestamptz not null default now()
);

alter table public.user_roles enable row level security;

-- A logged-in user can see only their own role. Nobody can change roles
-- from the website or API; roles are set only from the SQL Editor (step 4).
drop policy if exists "users can read own role" on public.user_roles;
create policy "users can read own role"
  on public.user_roles for select
  to authenticated
  using (user_id = auth.uid());

revoke insert, update, delete on public.user_roles from anon, authenticated;

------------------------------------------------------------
-- 2) Helper: is the current login an admin?
------------------------------------------------------------
create or replace function public.has_role(wanted text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_roles r
    where r.user_id = auth.uid() and r.role = wanted
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select public.has_role('admin'); $$;

revoke execute on function public.has_role(text) from public, anon;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.has_role(text) to authenticated;
grant execute on function public.is_admin() to authenticated;

------------------------------------------------------------
-- 3) Admin access rules
------------------------------------------------------------
-- contact_messages (the existing "visitors can send messages" insert rule stays)
drop policy if exists "admin can read messages"   on public.contact_messages;
drop policy if exists "admin can update messages" on public.contact_messages;
drop policy if exists "admin can delete messages" on public.contact_messages;

create policy "admin can read messages"   on public.contact_messages
  for select to authenticated using ((select public.is_admin()));
create policy "admin can update messages" on public.contact_messages
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admin can delete messages" on public.contact_messages
  for delete to authenticated using ((select public.is_admin()));

-- payments: admin can read and correct records; inserts come only from the webhook
drop policy if exists "admin can read payments"   on public.payments;
drop policy if exists "admin can update payments" on public.payments;
drop policy if exists "admin can delete payments" on public.payments;

create policy "admin can read payments"   on public.payments
  for select to authenticated using ((select public.is_admin()));
create policy "admin can update payments" on public.payments
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admin can delete payments" on public.payments
  for delete to authenticated using ((select public.is_admin()));

------------------------------------------------------------
-- 4) Make yourself admin
-- First create your login: Authentication -> Users -> Add user -> Create new user
--   (email + password, tick "Auto Confirm User").
-- Then change the email below and run ONLY this statement:
------------------------------------------------------------
-- insert into public.user_roles (user_id, role)
-- select id, 'admin' from auth.users where email = 'anuragmani.sonkar87@gmail.com'
-- on conflict (user_id) do update set role = excluded.role;

-- Check it worked:
-- select u.email, r.role from public.user_roles r join auth.users u on u.id = r.user_id;

-- Remove someone's admin access:
-- delete from public.user_roles where user_id = (select id from auth.users where email = 'someone@example.com');
