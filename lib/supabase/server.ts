import { cookies } from 'next/headers';
import { createServerClient } from '@supabase/ssr';

import { getSupabaseEnv } from './env';
import type { Database } from '@/types/database';

/**
 * Supabase client for Server Components, Route Handlers and Server Actions.
 *
 * Must be awaited — `cookies()` is async in Next.js 15+.
 *
 *   const supabase = await createClient();
 *   const { data } = await supabase.from('trips').select();
 *
 * Create a new client per request. Never hoist one into a module-level constant:
 * it closes over that request's cookies, so a shared instance would leak one
 * user's session into another user's request.
 */
export async function createClient() {
  const { url, anonKey } = getSupabaseEnv();
  const cookieStore = await cookies();

  return createServerClient<Database>(url, anonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // Server Components cannot set cookies. This throw is expected and
          // safe to swallow *because* proxy.ts refreshes the session on every
          // request — the refreshed cookie is already on the response by the
          // time we get here. If you remove the proxy, sessions will silently
          // stop refreshing and users will be logged out at token expiry.
        }
      },
    },
  });
}
