import { createBrowserClient } from '@supabase/ssr';

import { getSupabaseEnv } from './env';
import type { Database } from '@/types/database';

/**
 * Supabase client for use in Client Components (`'use client'`).
 *
 * Reads and writes auth state via browser cookies, which is what lets the
 * server client in `./server.ts` see the same session. Safe to call on every
 * render — the underlying client is memoised per browser context.
 *
 * Only ever runs with the anon key, so RLS is the security boundary. Nothing
 * here is trusted; the database decides what this user may read.
 */
export function createClient() {
  const { url, anonKey } = getSupabaseEnv();
  return createBrowserClient<Database>(url, anonKey);
}
