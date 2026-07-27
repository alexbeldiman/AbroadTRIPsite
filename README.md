# AbroadTRIPsite

A travel planner and social sharing app for students studying abroad for a
semester.

Enter your study-abroad city and semester dates, and your semester lays itself
out as a grid of open weekends. Plan trips into them, book through external
sites, and log what you booked. Rate trips afterwards, add recommendations, and
watch your profile map fill in.

Each trip has its own privacy setting — public, followers-only, a specific list
of people, or nobody but you.

> **Status: foundation only.** Scaffold, database schema, and conventions are in
> place. No product features are built yet.

---

## Stack

- **Next.js 16** (App Router) + **React 19** + **TypeScript** (strict)
- **Tailwind CSS v4**
- **Supabase** — Postgres, Auth, Row Level Security
- **Vercel** for hosting

---

## Setup

**Prerequisites:** Node.js 20.9+ (Next.js 16 minimum) and npm. Check with
`node --version`.

**1. Clone and install**

```bash
git clone https://github.com/alexbeldiman/AbroadTRIPsite.git
cd AbroadTRIPsite
npm install
```

**2. Configure environment**

```bash
cp .env.example .env.local
```

Fill in both values from your Supabase dashboard under
**Project Settings → API**:

| Variable                        | Where to find it                   |
| ------------------------------- | ---------------------------------- |
| `NEXT_PUBLIC_SUPABASE_URL`      | Project URL                        |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Project API keys → `anon` `public` |

Both are `NEXT_PUBLIC_` and ship to the browser. That is fine — the anon key is a
public identifier, not a secret, and Row Level Security is what protects the
data. **Do not add the service-role key**; it bypasses RLS entirely.

`.env.local` is gitignored. Never commit real keys.

> Without `.env.local` the app still starts and renders pages, but logs a warning
> and cannot authenticate.

**3. Run**

```bash
npm run dev
```

Open <http://localhost:3000>.

---

## Commands

| Command                | Does                           |
| ---------------------- | ------------------------------ |
| `npm run dev`          | Dev server on port 3000        |
| `npm run build`        | Production build               |
| `npm run start`        | Serve a production build       |
| `npm run lint`         | ESLint                         |
| `npm run lint:fix`     | ESLint, autofixing what it can |
| `npm run typecheck`    | `tsc --noEmit`                 |
| `npm run format`       | Prettier, writes               |
| `npm run format:check` | Prettier, verifies only        |

---

## Database

The schema lives in `supabase/migrations/`.

**Migrations deploy automatically.** The Supabase project is connected to this
GitHub repo, so anything merged to `main` under `supabase/migrations/` runs
against the hosted database on push. There is no manual apply step — which makes
review the only safety net. Migrations are append-only: never edit one that has
already merged, write a new one instead.

To test a migration before pushing (needs Docker):

```bash
npx supabase start
npx supabase db reset
```

`db reset` replays every migration from scratch against a local Postgres and
surfaces syntax errors and RLS recursion in seconds.

Row Level Security is a core product feature here, not a hardening detail. Read
the RLS section of [CLAUDE.md](CLAUDE.md) before changing a policy.

---

## Project layout

```
app/          routes and layouts
components/   reusable UI
lib/          utilities, Supabase clients, data access
types/        shared TypeScript types
supabase/     migrations
```

Every folder has a `README.md` explaining what belongs in it.

---

## Docs

- **[CLAUDE.md](CLAUDE.md)** — product, schema, RLS model, conventions,
  out-of-scope list. Read before writing code.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — branches, commits, PRs, how we split
  work.

---

## Licence

MIT — see [LICENSE](LICENSE).
