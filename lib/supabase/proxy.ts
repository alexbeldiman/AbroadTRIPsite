import { NextResponse, type NextRequest } from 'next/server';
import { createServerClient } from '@supabase/ssr';

import { getSupabaseEnv, hasSupabaseEnv } from './env';
import type { Database } from '@/types/database';

let warnedAboutMissingEnv = false;

/**
 * Refreshes the Supabase auth session on every matched request.
 *
 * Why this is necessary: Server Components cannot set cookies. When an access
 * token expires, the server client in `./server.ts` can refresh it in memory but
 * cannot persist the new token — so without this, users get silently logged out
 * once the token lifetime elapses.
 *
 * Called from the root `proxy.ts`. In Next.js 16 the `middleware` convention was
 * renamed to `proxy`; the runtime is always Node.js and cannot be configured.
 *
 * This deliberately does NOT redirect or gate routes. It only refreshes the
 * session. Route protection is a product decision and belongs with the auth
 * feature, not in shared plumbing.
 */
export async function updateSession(request: NextRequest) {
  // This response object is what carries refreshed cookies back to the browser.
  // Keep it — recreating it later would drop any cookie Supabase has set.
  let response = NextResponse.next({ request });

  // The proxy runs on every request, so throwing here would 500 the entire site
  // — including static pages — on a checkout that has no .env.local yet. Warn
  // once and carry on unauthenticated instead. Code that actually queries the
  // database still throws a clear error via getSupabaseEnv().
  if (!hasSupabaseEnv()) {
    if (!warnedAboutMissingEnv) {
      warnedAboutMissingEnv = true;
      console.warn(
        '[supabase] NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY are not set. ' +
          'Skipping session refresh — auth will not work. ' +
          'Copy .env.example to .env.local to fix this.',
      );
    }
    return response;
  }

  const { url, anonKey } = getSupabaseEnv();

  const supabase = createServerClient<Database>(url, anonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet, headers) {
        // Mirror onto the request so anything downstream in this same pass sees
        // the refreshed token...
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }

        response = NextResponse.next({ request });

        // ...and onto the response so the browser actually stores it.
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }

        // Supabase supplies no-store headers alongside auth cookies. Applying
        // them matters: a CDN or reverse proxy that cached this response would
        // hand one user's session token to the next visitor.
        for (const [key, value] of Object.entries(headers)) {
          response.headers.set(key, value);
        }
      },
    },
  });

  // Touching the user is what triggers the refresh. Do not remove it, and do not
  // replace it with getSession() — getUser() revalidates the token against the
  // Supabase auth server, whereas getSession() trusts whatever the cookie says.
  await supabase.auth.getUser();

  return response;
}
