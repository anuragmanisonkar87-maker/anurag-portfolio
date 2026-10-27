// Supabase Edge Function: receives Razorpay webhooks and saves payments.
//
// Razorpay -> (signed POST) -> this function -> public.payments table
//
// Secrets needed (set once):
//   supabase secrets set RAZORPAY_WEBHOOK_SECRET=<the secret you typed in Razorpay>
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase automatically.
//
// Deploy (no JWT check, because Razorpay cannot send a Supabase login token;
// the Razorpay signature check below protects it instead):
//   supabase functions deploy razorpay-webhook --no-verify-jwt

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const WEBHOOK_SECRET = Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? "";
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

// HMAC-SHA256 of the raw body, hex encoded (this is how Razorpay signs webhooks)
async function sign(body: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Constant-time compare so the signature can't be guessed byte by byte
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const SAVED_EVENTS = new Set([
  "payment.authorized",
  "payment.captured",
  "payment.failed",
  "order.paid",
  "refund.processed",
]);

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (!WEBHOOK_SECRET) return new Response("Webhook secret not configured", { status: 500 });

  const raw = await req.text(); // must be the exact raw body for the signature check
  const given = req.headers.get("x-razorpay-signature") ?? "";
  const expected = await sign(raw, WEBHOOK_SECRET);
  if (!given || !safeEqual(given, expected)) {
    return new Response("Invalid signature", { status: 401 });
  }

  let body: any;
  try {
    body = JSON.parse(raw);
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }

  const event: string = body.event ?? "";
  if (!SAVED_EVENTS.has(event)) {
    return new Response(JSON.stringify({ ok: true, ignored: event }), { status: 200 });
  }

  // refund.processed carries the payment inside payload.payment too
  const p = body?.payload?.payment?.entity;
  if (!p?.id) {
    return new Response(JSON.stringify({ ok: true, ignored: "no payment entity" }), { status: 200 });
  }

  const row = {
    razorpay_payment_id: p.id,
    razorpay_order_id: p.order_id ?? null,
    event,
    status: event === "refund.processed" ? "refunded" : p.status ?? null,
    amount_paise: p.amount ?? null,
    currency: p.currency ?? null,
    method: p.method ?? null,
    customer_email: p.email ?? null,
    customer_phone: p.contact ?? null,
    description: p.description ?? null,
    notes: p.notes ?? null,
    paid_at: p.created_at ? new Date(p.created_at * 1000).toISOString() : null,
    raw: body,
    updated_at: new Date().toISOString(),
  };

  // One row per payment; later events (captured, refunded) update the same row
  const { error } = await supabase
    .from("payments")
    .upsert(row, { onConflict: "razorpay_payment_id" });

  if (error) {
    console.error("DB error", error);
    // 500 makes Razorpay retry later
    return new Response("DB error", { status: 500 });
  }
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
