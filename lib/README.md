# /lib — utilities, Supabase clients, data access

Everything that is not a route and not a React component.

**Belongs here**

- `lib/supabase/` — the browser client, the server client, and the proxy session
  helper. Never construct a Supabase client anywhere else.
- Data-access functions: `getTripsForUser()`, `createTrip()`, `getWeekends()`.
  One module per domain (`lib/trips.ts`, `lib/profiles.ts`).
- Pure helpers: date math for the semester grid, currency formatting, slugs.

**Does not belong here**

- JSX. If it renders, it belongs in `/components` or `/app`.
- Type declarations shared across the app → `/types`.

**Conventions**

- **Every database query lives in this folder.** Routes and components import
  these functions; they never build queries inline. RLS is the security boundary,
  but centralising queries means one place to audit when a policy changes.
- Data-access functions take an explicit Supabase client as their first argument
  rather than creating one. The caller knows whether it is on the server or the
  client; the query function should not have to guess.
- Pure helpers get colocated tests when we add a test runner.
- Files are `kebab-case`. Named exports only — no default exports outside `/app`.
