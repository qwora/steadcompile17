// Verifies the caller's Supabase session token with the Auth server.
// The gateway's verify_jwt also accepts the public anon key (role "anon"), which is not a user,
// so every user-facing function calls this instead of trusting the header.
export async function getUserId(req: Request, fetchFn: typeof fetch = fetch): Promise<string | null> {
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.toLowerCase().startsWith("bearer ")) return null;
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !key) return null;
  try {
    const res = await fetchFn(`${url}/auth/v1/user`, {
      headers: { authorization: auth, apikey: key },
      signal: AbortSignal.timeout(3000),
    });
    if (!res.ok) return null;
    const user = await res.json();
    return typeof user?.id === "string" ? user.id : null;
  } catch {
    return null;
  }
}
