-- Portfolio database setup for Supabase
-- Run this once in Supabase: Dashboard -> SQL Editor -> New query -> paste -> Run

------------------------------------------------------------
-- 1) Messages from the "Email me" form
------------------------------------------------------------
create table if not exists public.contact_messages (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  name        text not null check (char_length(name) between 1 and 120),
  email       text not null check (char_length(email) between 3 and 200),
  topic       text check (char_length(topic) <= 100),
  message     text not null check (char_length(message) between 10 and 5000),
  page_url    text check (char_length(page_url) <= 500)
);

alter table public.contact_messages enable row level security;

-- Website visitors (anon key) may ONLY add a message.
-- They cannot read, change or delete any messages.
drop policy if exists "visitors can send messages" on public.contact_messages;
create policy "visitors can send messages"
  on public.contact_messages
  for insert
  to anon
  with check (true);

------------------------------------------------------------
-- 2) Payments from Razorpay
-- Written ONLY by the razorpay-webhook Edge Function (service role).
-- No access at all from the website.
------------------------------------------------------------
create table if not exists public.payments (
  id                  bigint generated always as identity primary key,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  razorpay_payment_id text not null unique,
  razorpay_order_id   text,
  event               text not null,          -- e.g. payment.captured, payment.failed
  status              text,                   -- captured, failed, refunded ...
  amount_paise        bigint,                 -- Razorpay sends amounts in paise (₹1 = 100)
  amount_rupees       numeric generated always as (amount_paise / 100.0) stored,
  currency            text,
  method              text,                   -- upi, card, netbanking ...
  customer_email      text,
  customer_phone      text,
  description         text,
  notes               jsonb,
  paid_at             timestamptz,
  raw                 jsonb not null          -- full webhook payload, for records
);

alter table public.payments enable row level security;
-- No policies on purpose: the website (anon key) cannot read or write payments.
-- The Edge Function uses the service role key, which bypasses RLS.

create index if not exists payments_created_at_idx on public.payments (created_at desc);
create index if not exists contact_messages_created_at_idx on public.contact_messages (created_at desc);
