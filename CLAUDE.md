@AGENTS.md

# AbroadTRIPsite

Read this before writing code. It is the shared context for both human
contributors and Claude Code sessions.

> **Status: foundation only.** The scaffold, schema, and conventions exist. No
> product features are built yet. There is no auth flow, no trip UI, and no data
> access layer beyond the Supabase clients.

---

## The product

A travel planner and social sharing app for students studying abroad for a
semester.

**Core loop**

1. A student signs in and enters their study-abroad city and semester
   start/end dates.
2. They see their semester laid out as a grid of open weekends (and possibly
   weekdays).
3. They plan trips into those weekends.
4. They book through external sites — **we link out, we never handle booking or
   payment** — and log what they booked.
5. After the trip they rate it and add recommendations.
6. Each trip carries its own privacy setting controlling who can see it.
7. Their profile shows a map of everywhere they have been.

**What makes this app different is the privacy model.** A trip is not simply
public or private; visibility resolves through owner, participants, follow
relationships, and explicit shares. Treat that as a product feature, not as
security boilerplate. If a change touches who can see what, it deserves the same
scrutiny as a UI change users would notice.

---

## Stack

| Layer     | Choice                                                |
| --------- | ----------------------------------------------------- |
| Framework | Next.js 16 (App Router), React 19                     |
| Language  | TypeScript, strict mode + `noUncheckedIndexedAccess`  |
| Styling   | Tailwind CSS v4 (CSS-first — no `tailwind.config.js`) |
| Backend   | Supabase — Postgres, Auth, Row Level Security         |
| Hosting   | Vercel                                                |

### Version gotchas that will bite you

- **Next.js 16 renamed `middleware` to `proxy`.** The file is `proxy.ts` and the
  export is `proxy`, not `middleware`. The runtime is Node.js and cannot be
  configured. Most tutorials online still say `middleware.ts`.
- **`cookies()` is async.** `await cookies()`, and therefore
  `await createClient()` for the server client.
- **Tailwind v4 has no JS config file.** Theme customisation goes in
  `@theme` inside `app/globals.css`.
- **Next.js 16 ships its own docs** in `node_modules/next/dist/docs/`. When
  something contradicts what you remember about Next.js, read those first —
  they are authoritative for the installed version.

---

## Commands

```bash
npm run dev           # dev server on :3000
npm run build         # production build
npm run lint          # ESLint
npm run typecheck     # tsc --noEmit
npm run format        # Prettier, writes
npm run format:check  # Prettier, verifies only
```

`lint`, `typecheck`, and `format:check` must all pass before a PR merges.

---

## Folder conventions

```
/app          routes and layouts (App Router)
/components   reusable UI — no data fetching
/lib          utilities, Supabase clients, ALL data access
/types        shared TypeScript types
/supabase     migrations (auto-deploy on push to main)
```

Each folder has its own `README.md` with specifics. The rules that matter most:

- **Every database query lives in `/lib`.** Routes and components import query
  functions; they never build queries inline. When an RLS policy changes, there
  is one place to audit.
- **Components receive data as props.** They do not fetch. Fetch in the Server
  Component and pass down.
- **Server Components by default.** `'use client'` goes on the smallest leaf that
  genuinely needs interactivity.
- **Never construct a Supabase client outside `lib/supabase/`.**

### Naming

| Thing                | Convention           | Example             |
| -------------------- | -------------------- | ------------------- |
| Files and folders    | `kebab-case`         | `trip-card.tsx`     |
| React components     | `PascalCase`         | `TripCard`          |
| Functions, variables | `camelCase`          | `getTripsForUser`   |
| Constants            | `SCREAMING_SNAKE`    | `TRIP_VISIBILITIES` |
| Database tables      | `snake_case`, plural | `trip_segments`     |
| Database columns     | `snake_case`         | `destination_city`  |
| Enum values          | `snake_case`         | `'planned'`         |

Named exports everywhere except `/app`, where Next.js requires default exports
for pages and layouts.

---

## Database

Schema lives in `supabase/migrations/`. TypeScript mirror lives in
`types/database.ts` — **change both in the same commit.**

### Tables

| Table               | Purpose                                                      |
| ------------------- | ------------------------------------------------------------ |
| `profiles`          | One row per auth user. Created automatically on signup.      |
| `trips`             | The central object. Owns visibility.                         |
| `trip_segments`     | Bookable pieces: flight, train, bus, stay, reservation.      |
| `trip_participants` | Companions on a trip, with invite status.                    |
| `trip_shares`       | Explicit per-user grants, used when `visibility = 'custom'`. |
| `recommendations`   | Post-trip place notes.                                       |
| `follows`           | Social graph. `pending` → `accepted`.                        |
| `destinations`      | Seeded reference data. Read-only. **Currently empty.**       |

### Enums

```
account_visibility  public | private
trip_status         idea | planned | booked | completed
trip_visibility     public | followers | custom | private
segment_type        flight | train | bus | stay | reservation
segment_status      wanted | booked
participant_role    owner | companion
invite_status       invited | accepted | declined
follow_status       pending | accepted
```

---

## Row Level Security — read this before touching a policy

Two Supabase project settings define the danger:

- **Automatically expose new tables** is ON.
- **Automatic RLS** is ON.

Together: a new table is immediately reachable through the Data API, with RLS on
and no policies — so it **silently returns zero rows rather than erroring**. That
failure mode is indistinguishable from "no data yet", which is exactly why it
wastes an afternoon. **Every new table needs explicit policies in the same
migration that creates it.**

Never write manual `GRANT` statements. Supabase manages role grants.

### Trip read resolution

Read access resolves in this order:

1. **Owner** — always.
2. **Participant** — any participant whose `invite_status` is `invited` or
   `accepted`. A pending invitee can see what they were invited to; **declining
   revokes that access.**
3. **Otherwise, by `visibility`:**
   - `public` — anyone, **unless the owner's account is private**, in which case
     accepted followers only.
   - `followers` — accepted followers of the owner. Pending never counts.
   - `custom` — only users with a row in `trip_shares`.
   - `private` — nobody else.

`trip_segments` and `recommendations` inherit trip read access via
`public.can_read_trip()`, so child access can never drift from the parent.

### Why the helper functions exist — do not inline them

Writing the `trips` policy to consult `trip_participants`, and the
`trip_participants` policy to consult `trips`, makes Postgres recurse and error
with _"infinite recursion detected in policy for relation"_.

The `SECURITY DEFINER` functions in the migration break that cycle: they are
owned by the table owner, so their internal reads bypass RLS. This is the
standard Supabase pattern and it is load-bearing. **If you "simplify" a policy by
inlining one of these back into a subquery, you will reintroduce the recursion.**

Each is pinned to `search_path = ''` with fully-qualified names so a
caller-controlled `search_path` cannot redirect it.

| Function                       | Answers                                                                  |
| ------------------------------ | ------------------------------------------------------------------------ |
| `is_accepted_follower(a, b)`   | Does a have an _accepted_ follow of b?                                   |
| `account_is_private(user)`     | Is that account private?                                                 |
| `is_trip_participant(trip)`    | Is the caller an active participant? (invited or accepted, not declined) |
| `is_trip_shared_with_me(trip)` | Explicit `custom` share for the caller?                                  |
| `is_trip_owner(trip)`          | Does the caller own it?                                                  |
| `can_read_trip(trip)`          | Full read rule, for child tables                                         |

Note that the `trips` SELECT policy **inlines** the same logic rather than
calling `can_read_trip()` — it already has the row, so re-querying would be
wasteful. **The two must be kept in sync.** Change one, change the other.

### Write access

- Own profile: yourself only.
- Trips: owner only.
- `trip_segments`, `recommendations`: **trip owner only.** Companions cannot edit
  them yet — see open questions.
- `trip_participants`: owner manages the roster; an invitee may update their own
  row to accept or decline.
- `follows`: you create follows where you are the follower; only the person being
  followed can flip status to `accepted`. A follower cannot self-approve — that
  is what protects private accounts.
- `destinations`: nobody. No write policy exists. Seed via migration.

### Deliberate decisions worth knowing

1. **Pending invitees can read; declined invitees cannot.** An invitee needs to
   see what they are deciding about, but declining revokes that access —
   `is_trip_participant()` matches `invite_status in ('invited', 'accepted')`.
   Note this makes decline a one-way door: the row still exists, so re-inviting
   someone means the owner updating `invite_status` back to `'invited'`.
2. **An explicit `custom` share outranks a private account.** The owner named
   that person deliberately.
3. **A participant can set `role = 'owner'` on their own row.** Harmless —
   ownership is `trips.owner_id`, and every write policy checks that column.
   `trip_participants.role` is display metadata.
4. **Follower lists are private.** Only the two parties see a `follows` row.
   Surfacing "who follows this public account" is a product decision nobody has
   made yet.

### ⚠️ The policies have not been tested against real users

They parse, and the logic has been reviewed, but **no one has verified them with
two live accounts.** Before building any feature that depends on privacy, do
this:

1. Create two users, A and B.
2. Give A one trip at each of the four visibility levels.
3. From B, with no follow, then a pending follow, then an accepted follow, then
   an explicit share, confirm reads succeed and fail exactly as the table above
   says.
4. Repeat with A's account set to `private`.

Until that is done, treat the privacy model as _written but unverified_.

---

## Auth

Supabase Auth via `@supabase/ssr`.

- `lib/supabase/client.ts` — Client Components.
- `lib/supabase/server.ts` — Server Components, Route Handlers, Server Actions.
  `await createClient()`. **Never hoist to a module constant** — it closes over
  one request's cookies and would leak sessions between users.
- `proxy.ts` → `lib/supabase/proxy.ts` — refreshes the session on every request.
  Without it, Server Components cannot persist refreshed tokens and users get
  logged out at token expiry.

The proxy deliberately does **not** redirect or gate routes. Route protection
belongs with the auth feature.

Only the anon key is used. **RLS is the security boundary** — the client is
untrusted by design. The service-role key bypasses RLS entirely and is
deliberately absent from `.env.example`.

Use `getUser()`, not `getSession()`, when a decision depends on identity:
`getUser()` revalidates against the auth server; `getSession()` trusts the
cookie.

---

## Out of scope

Not being built, and not to be added without a conversation first:

- **Payments and booking.** We link out to external providers. We never take
  payment, hold a booking, or store card details.
- **A native mobile app.** Responsive web only.
- **Real-time collaborative editing** of trips.
- **Messaging or DMs.** The social layer is follows, shared trips, and
  recommendations — not a chat product.
- **Recommendation algorithms / ML.**
- **Multi-semester or multi-year planning.** One study-abroad semester per
  profile for now.
- **Group or organisation accounts.** Individual students only.
- **Email notifications.** Not until there is a reason.
- **New dependencies.** Ask before adding one. The current list is deliberately
  short.

---

## Open questions

Unresolved. Do not silently pick an answer — raise it.

- Should companions be able to edit `trip_segments` and `recommendations`? Owner
  only today because loosening is easy and tightening after real data is not.
- Declining an invitation now revokes read access, and nothing re-grants it. Is
  re-inviting a declined companion a flow we want? Today it means the owner
  updating `invite_status` back to `'invited'` on the existing row.
- Should the weekend grid include weekdays, and how are partial weeks at semester
  boundaries handled?
- Should follower/following lists be public for public accounts?
- Username selection: the signup trigger assigns a provisional username from the
  email local part. A real picker is unbuilt.
- `destinations` is empty. Seed source and coverage undecided.

---

## Working agreements

- Two developers. **Consistency matters more than cleverness.** If you are about
  to do something clever, do the boring thing instead.
- We split work **by feature, not by layer** — each person owns a slice end to
  end, schema through UI. See `CONTRIBUTING.md`.
- Migrations are **append-only**. Once merged, a migration has run against the
  production database. Never edit it; write a new one.
- Explain guesses rather than burying them. If the spec did not cover it, say so
  in the PR.
