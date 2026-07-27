# /app — routes and layouts

Next.js App Router. Everything that maps to a URL lives here.

**Belongs here**

- `page.tsx`, `layout.tsx`, `loading.tsx`, `error.tsx`, `not-found.tsx`
- Route handlers (`route.ts`) for webhooks and OAuth callbacks
- Server Actions that are used by exactly one route (shared ones go in `/lib`)
- Route groups like `(auth)` and `(dashboard)` for layout scoping without URL segments

**Does not belong here**

- Reusable presentational components → `/components`
- Supabase queries → `/lib`, imported by a Server Component here

**Conventions**

- Components are Server Components by default. Add `'use client'` only when you
  need state, effects, or browser APIs — and push it to the smallest leaf you can.
- Fetch data in the page/layout (server side) and pass it down as props. Client
  Components should receive data, not fetch it.
- Route segment folders are `kebab-case`: `app/trips/[tripId]/edit/page.tsx`.
