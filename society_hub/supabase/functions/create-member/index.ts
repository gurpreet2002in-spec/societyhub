// Supabase Edge Function: create-member
// ---------------------------------------------------------------------------
// Lets a SOCIETY ADMIN create a login for a security GUARD (or a resident) of
// their own society, ready to use at once — no sign-up or approval needed.
// Runs on Supabase's servers, so the service-role key never ships in the app.
//
// Deploy (no tools needed): Supabase dashboard → Edge Functions →
// "Deploy a new function" → "Via Editor" → name it  create-member  →
// paste this whole file → Deploy. Keep "Verify JWT" ON.
//
// Request (POST, JSON, called with the logged-in admin's session):
//   { role: "guard" | "resident", name, email, password,
//     contactNumber?, apartmentNumber?, occupancyType?, societyId? (super admin only) }
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
const ROLES = ["guard", "resident"];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // 1. Who is calling? An ACTIVE society admin (or the platform super admin).
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return reply(401, { error: "Not logged in" });
  const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
  if (callerErr || !caller?.user) return reply(401, { error: "Not logged in" });

  const { data: me } = await admin
    .from("users").select("id, role, society_id, status").eq("id", caller.user.id).maybeSingle();
  const isSuper = me?.role === "super_admin";
  const isAdmin = me?.role === "admin" && me?.status === "active" && !!me?.society_id;
  if (!isSuper && !isAdmin) {
    return reply(403, { error: "Only a society admin can add guards and residents" });
  }

  // 2. Validate input.
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "Invalid request" });
  }
  const role = String(body.role ?? "guard");
  const name = String(body.name ?? "").trim().slice(0, 100);
  const email = String(body.email ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  const contact = String(body.contactNumber ?? "").trim().slice(0, 20);
  const flat = String(body.apartmentNumber ?? "").trim().slice(0, 30);
  const occ = String(body.occupancyType ?? "").trim().toLowerCase();
  // A society admin can only add people to THEIR society.
  const societyId = isSuper ? String(body.societyId ?? "") : String(me!.society_id);

  if (!ROLES.includes(role)) return reply(400, { error: "Role must be guard or resident" });
  if (!name) return reply(400, { error: "Name is required" });
  if (!EMAIL_RE.test(email)) return reply(400, { error: "Enter a valid email (it is the login name)" });
  if (!UUID_RE.test(societyId)) return reply(400, { error: "Choose a society" });
  if (role === "resident" && !flat) return reply(400, { error: "Enter the flat / house number" });

  const profile: Record<string, unknown> = {
    name,
    role,
    society_id: societyId,
    status: "active",
    ...(contact ? { contact_number: contact } : {}),
    ...(role === "resident"
      ? { apartment_number: flat, occupancy_type: occ === "tenant" ? "tenant" : occ === "owner" ? "owner" : null }
      : { apartment_number: null, occupancy_type: null }),
  };

  // 3. Existing account? Re-use it if it is free or already in this society.
  const { data: existing } = await admin
    .from("users").select("id, role, society_id, status").eq("email", email).maybeSingle();
  if (existing) {
    if (existing.role === "super_admin" || existing.role === "admin") {
      return reply(400, { error: "That email belongs to an admin account" });
    }
    if (existing.society_id && existing.society_id !== societyId && existing.status !== "rejected") {
      return reply(400, { error: "That email is already used in another society" });
    }
    const { error } = await admin.from("users").update(profile).eq("id", existing.id);
    if (error) return reply(500, { error: "Could not update the existing account" });
    return reply(200, {
      ok: true,
      created: false,
      message: `${email} already had an account — it is now a ${role}. Their old password still works.`,
    });
  }

  // 4. New account, e-mail pre-confirmed so they can log in at once.
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

  const { error: rowErr } = await admin.from("users").upsert({ id: created.user.id, email, ...profile });
  if (rowErr) {
    await admin.auth.admin.deleteUser(created.user.id); // don't leave half an account
    return reply(500, { error: "Could not save the profile" });
  }

  return reply(200, {
    ok: true,
    created: true,
    message: `${role === "guard" ? "Guard" : "Resident"} login created. They can sign in with ${email}.`,
  });
});
