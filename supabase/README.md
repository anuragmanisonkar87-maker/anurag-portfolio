# Supabase setup (Email me messages + Razorpay payments)

```
Email me form  ──► Web3Forms ──► Gmail
      └─────────► Supabase table: contact_messages   (anon key, insert-only)

Razorpay ──(signed webhook)──► Edge Function razorpay-webhook ──► Supabase table: payments
```

Payments are written only by Razorpay through the Edge Function, never by the browser,
so nobody can fake a "paid" record.

## 1. Create the tables (5 min)
1. Create a project at https://supabase.com (region: Mumbai `ap-south-1`).
2. Open **SQL Editor → New query**, paste everything from [`schema.sql`](schema.sql), click **Run**.

## 2. Connect the Email me form (2 min)
1. Go to **Project Settings → API**. Copy the **Project URL** and the **anon public** key.
2. In `index.html`, replace `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY` with them.
   - The anon key is meant to be public. The table rules only let it *add* messages.
   - **Never** put the `service_role` key in `index.html`.
3. Send a test message from the site → check **Table Editor → contact_messages**.

## 3. Save Razorpay payments (10 min)
Install the Supabase CLI (https://supabase.com/docs/guides/cli), then from this repo folder:

```bash
supabase login
supabase link --project-ref <your-project-ref>     # the id in your project URL
supabase secrets set RAZORPAY_WEBHOOK_SECRET=<make-up-a-long-random-secret>
supabase functions deploy razorpay-webhook --no-verify-jwt
```

Your function URL will be:
`https://<your-project-ref>.supabase.co/functions/v1/razorpay-webhook`

In **Razorpay Dashboard → Account & Settings → Webhooks → Add New Webhook**:
- **Webhook URL:** the function URL above
- **Secret:** the same secret you set in `RAZORPAY_WEBHOOK_SECRET`
- **Events:** `payment.captured`, `payment.failed`, `order.paid`, `refund.processed`
  (optional: `payment.authorized`)

Make a test payment in Test Mode → check **Table Editor → payments**.
Webhooks are set up separately for Test Mode and Live Mode, so add it again after going live.

## 4. Admin login and role-based access (5 min)
1. **Turn off public sign-up:** Authentication → Sign In / Providers → turn off **Allow new users to sign up**
   (keep **Email** enabled). Only you can create logins.
2. **Create your login:** Authentication → Users → **Add user → Create new user**
   → your email + a strong password → tick **Auto Confirm User**.
3. **Add the role rules:** SQL Editor → paste everything from [`roles.sql`](roles.sql) → **Run**.
4. **Make yourself admin:** in SQL Editor run the `insert into public.user_roles ...` line from
   step 4 at the bottom of `roles.sql` (remove the `--` in front first).

| Who | contact_messages | payments | user_roles |
|---|---|---|---|
| Website visitor | add only | no access | no access |
| Logged-in non-admin | no access | no access | read own role |
| **Admin** | read, update, delete | read, update, delete | read own role |
| Razorpay webhook | – | add / update | – |

Roles can only be given or removed from the SQL Editor, never from the website or API.

## Viewing the data
Use the Supabase **Table Editor**. Both tables are hidden from the public website.
Amounts are stored in paise (`amount_paise`) and also shown in rupees (`amount_rupees`).
