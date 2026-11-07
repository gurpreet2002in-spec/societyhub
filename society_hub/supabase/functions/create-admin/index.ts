// Supabase Edge Function: create-admin
// ---------------------------------------------------------------------------
// Lets a SUPER ADMIN create a society admin account (email + password) from
// the app. It runs on Supabase's servers, so the service-role key never
// leaves Supabase and is never inside the APK.
//
// Deploy (no tools needed): Supabase dashboard → Edge Functions →
// "Deploy a new function" → "Via Editor" → name it  create-admin  →
// paste this whole file → Deploy. Keep "Verify JWT" ON.
//
// Request (POST, JSON, called with the logged-in user's session):
//   { name, email, password, contactNumber?, societyId }
// ---------------------------------------------------------------------------
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // 1. Who is calling? Must be a logged-in super admin.
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return reply(401, { error: "Not logged in" });
  const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
  if (callerErr || !caller?.user) return reply(401, { error: "Not logged in" });

  const { data: callerRow } = await admin
    .from("users").select("role").eq("id", caller.user.id).maybeSingle();
  if (callerRow?.role !== "super_admin") {
    return reply(403, { error: "Only the platform super admin can create admins" });
  }

  // 2. Validate input.
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "Invalid request" });
  }
  const name = String(body.name ?? "").trim().slice(0, 100);
  const email = String(body.email ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  const contact = String(body.contactNumber ?? "").trim().slice(0, 20);
  const societyId = String(body.societyId ?? "");

  if (!name) return reply(400, { error: "Name is required" });
  if (!EMAIL_RE.test(email)) return reply(400, { error: "Enter a valid email address" });
  if (!UUID_RE.test(societyId)) return reply(400, { error: "Choose a society" });

  const { data: society } = await admin
    .from("societies").select("id, name").eq("id", societyId).maybeSingle();
  if (!society) return reply(400, { error: "That society does not exist" });

  // 3. Existing account? Upgrade it instead of creating a duplicate.
  const { data: existing } = await admin
    .from("users").select("id, role").eq("email", email).maybeSingle();

  if (existing) {
    if (existing.role === "super_admin") {
      return reply(400, { error: "That account is the platform super admin" });
    }
    const { error } = await admin.from("users").update({
      role: "admin",
      society_id: societyId,
      status: "active",
      name,
      ...(contact ? { contact_number: contact } : {}),
    }).eq("id", existing.id);
    if (error) return reply(500, { error: "Could not update the existing account" });
    return reply(200, { ok: true, created: false, message: `${email} is now admin of ${society.name}` });
  }

  // 4. New account: e-mail is pre-confirmed so the admin can log in at once.
  if (password.length < 8) return reply(400, { error: "Password must be at least 8 characters" });

  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name, society_id: societyId },
  });
  if (createErr || !created?.user) {
    const msg = /already|registered|exists/i.test(createErr?.message ?? "")
      ? "An account with this email already exists"
      : "Could not create the account";
    return reply(400, { error: msg });
  }

  // The handle_new_user trigger has created the row as a resident of this
  // society; upgrade it to admin. (upsert covers a missing trigger.)
  const { error: rowErr } = await admin.from("users").upsert({
    id: created.user.id,
    email,
    name,
    role: "admin",
    society_id: societyId,
    status: "active",
    ...(contact ? { contact_number: contact } : {}),
  });
  if (rowErr) {
    await admin.auth.admin.deleteUser(created.user.id); // don't leave half an account
    return reply(500, { error: "Could not save the admin profile" });
  }

  return reply(200, { ok: true, created: true, message: `Admin created for ${society.name}` });
});
