// Supabase Edge Function: send-push
// ---------------------------------------------------------------------------
// Sends a phone notification (with the notification tone) for a row that was
// just added to public.notifications. The database calls this automatically
// (see migrations/2026_10_31_push_notifications.sql) — the app never calls it.
//
// Deploy (no tools needed): Supabase dashboard → Edge Functions →
// "Deploy a new function" → "Via Editor" → name it  send-push  →
// paste this whole file → Deploy. Then open the function's settings and turn
// "Verify JWT" OFF (the database calls it without a login).
//
// Secret needed (Edge Functions → Secrets → Add):
//   FCM_SERVICE_ACCOUNT = the whole content of the Firebase service-account
//                         .json file (Firebase console → Project settings →
//                         Service accounts → Generate new private key).
//
// Why it is safe without a login: it only accepts a notification id, and it
// only sends a notification that is less than 10 minutes old and has never
// been sent before (it marks it as sent first). Nobody can make it send their
// own text, or send the same notification twice.
// ---------------------------------------------------------------------------
import { createClient } from "npm:@supabase/supabase-js@2";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ANDROID_CHANNEL = "society_hub_alerts"; // same id as in notification_service.dart

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ── Google access token from the service account (cached ~55 min) ──────────
type ServiceAccount = { project_id: string; client_email: string; private_key: string };
let cached: { token: string; exp: number } | null = null;

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function googleAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;

  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`)),
  );
  const assertion = `${header}.${claim}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const json = await res.json();
  if (!res.ok || !json.access_token) throw new Error(`Google auth failed: ${JSON.stringify(json)}`);
  cached = { token: json.access_token, exp: now + (json.expires_in ?? 3600) };
  return cached.token;
}

// Visitor at the gate → "call" style: sent as data only, so the app itself
// shows a ringing, full-screen alert with Approve / Decline (Android).
// iPhones get a time-sensitive alert with sound.
function buildMessage(token: string, title: string, body: string, data: Record<string, string>) {
  if (data.type === "visitor_approval") {
    return {
      token,
      data: { ...data, title, body },
      android: { priority: "HIGH", ttl: "180s" },
      apns: {
        headers: { "apns-priority": "10", "apns-expiration": String(Math.floor(Date.now() / 1000) + 180) },
        payload: { aps: { alert: { title, body }, sound: "default", "interruption-level": "time-sensitive" } },
      },
    };
  }
  return {
    token,
    notification: { title, body },
    data,
    android: {
      priority: "HIGH",
      notification: { channel_id: ANDROID_CHANNEL, sound: "default", default_vibrate_timings: true },
    },
    apns: {
      headers: { "apns-priority": "10" },
      payload: { aps: { sound: "default", badge: 1 } },
    },
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });

  let id = "";
  try {
    id = String((await req.json())?.id ?? "");
  } catch { /* fall through */ }
  if (!UUID_RE.test(id)) return reply(400, { error: "Bad request" });

  const rawSa = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!rawSa) return reply(500, { error: "FCM_SERVICE_ACCOUNT secret is not set" });
  let sa: ServiceAccount;
  try {
    sa = JSON.parse(rawSa);
  } catch {
    return reply(500, { error: "FCM_SERVICE_ACCOUNT is not valid JSON" });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // 1. Claim the notification: fresh and never sent before (atomic).
  const since = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const { data: claimed, error: claimErr } = await db
    .from("notifications")
    .update({ pushed_at: new Date().toISOString() })
    .eq("id", id)
    .is("pushed_at", null)
    .gte("created_at", since)
    .select("id, user_id, title, body, data");
  if (claimErr) return reply(500, { error: claimErr.message });
  const n = claimed?.[0];
  if (!n) return reply(200, { skipped: "already sent, too old or not found" });

  // 2. Who receives it?
  const { data: user } = await db.from("users").select("fcm_token").eq("id", n.user_id).maybeSingle();
  const token = user?.fcm_token as string | undefined;
  if (!token) return reply(200, { skipped: "no device registered" });

  // FCM "data" values must all be strings.
  const data: Record<string, string> = { notification_id: String(n.id) };
  for (const [k, v] of Object.entries((n.data ?? {}) as Record<string, unknown>)) {
    if (v !== null && v !== undefined) data[k] = typeof v === "string" ? v : JSON.stringify(v);
  }

  // 3. Send through Firebase Cloud Messaging (HTTP v1).
  const title = String(n.title ?? "SocietyHub").slice(0, 120);
  const body = String(n.body ?? "").slice(0, 400);
  try {
    const access = await googleAccessToken(sa);
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${access}` },
      body: JSON.stringify({ message: buildMessage(token, title, body, data) }),
    });
    if (res.ok) return reply(200, { sent: true });

    const err = await res.json().catch(() => ({}));
    const code = JSON.stringify(err);
    // Phone uninstalled the app / token expired → forget it.
    if (res.status === 404 || code.includes("UNREGISTERED") || code.includes("registration-token-not-registered")) {
      await db.from("users").update({ fcm_token: null }).eq("id", n.user_id).eq("fcm_token", token);
      return reply(200, { skipped: "device no longer registered" });
    }
    // Temporary Firebase problem: mark as not sent, so a later call can send it.
    if (res.status >= 500 || res.status === 429) {
      await db.from("notifications").update({ pushed_at: null }).eq("id", n.id);
    }
    return reply(502, { error: "FCM error", status: res.status, detail: err });
  } catch (e) {
    await db.from("notifications").update({ pushed_at: null }).eq("id", n.id);
    return reply(500, { error: String(e) });
  }
});
