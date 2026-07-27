import type { NextRequest } from 'next/server';

import { updateSession } from '@/lib/supabase/proxy';

/**
 * Runs before every matched request.
 *
 * Next.js 16 renamed the `middleware` file convention to `proxy` — if you are
 * following a tutorial that says `middleware.ts` with an exported `middleware`
 * function, this is the equivalent. The runtime is Node.js and is not
 * configurable.
 *
 * Its only job right now is refreshing the Supabase session. Auth redirects are
 * intentionally not here; see lib/supabase/proxy.ts.
 */
export async function proxy(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    /*
     * Every path except:
     * - _next/static, _next/image  (build output — never needs a session)
     * - favicon.ico, and common static asset extensions
     *
     * Without this exclusion the proxy runs on every CSS, JS and image request,
     * which adds an auth round-trip to each one.
     */
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|avif|ico|woff2?)$).*)',
  ],
};
