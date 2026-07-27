/**
 * Supabase environment configuration.
 *
 * Both variables are `NEXT_PUBLIC_` and therefore inlined into the browser
 * bundle. That is correct and expected: the anon key is a public identifier, not
 * a secret. It grants nothing on its own — every query it makes is still subject
 * to RLS.
 *
 * The service-role key is deliberately absent. It bypasses RLS entirely, so it
 * must never be imported into anything that could reach the client. If we ever
 * genuinely need it, it gets its own server-only module.
 */
/**
 * Is Supabase configured?
 *
 * Used by the proxy so that a checkout without `.env.local` still renders pages
 * instead of returning 500 for every request. Anything that actually talks to
 * the database should call `getSupabaseEnv()` and let it throw.
 */
export function hasSupabaseEnv(): boolean {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  );
}

export function getSupabaseEnv() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Fail loudly at the call site. Without this, a missing variable surfaces as a
  // confusing "fetch failed" or an empty result set that looks like an RLS bug.
  if (!url || !anonKey) {
    const missing = [
      !url && 'NEXT_PUBLIC_SUPABASE_URL',
      !anonKey && 'NEXT_PUBLIC_SUPABASE_ANON_KEY',
    ]
      .filter(Boolean)
      .join(', ');

    throw new Error(
      `Missing Supabase environment variables: ${missing}. ` +
        'Copy .env.example to .env.local and fill in the values from your ' +
        'Supabase project settings (Project Settings > API).',
    );
  }

  return { url, anonKey };
}
