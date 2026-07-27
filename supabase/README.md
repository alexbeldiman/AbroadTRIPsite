# /supabase — database migrations

The Supabase project is connected to this GitHub repo. **Anything merged into
`main` under `migrations/` runs against the hosted database automatically.**
There is no manual apply step, which makes review the only safety net.

**Belongs here**

- `migrations/` — timestamp-prefixed, forward-only SQL.

**Conventions**

- Filename: `YYYYMMDDHHMMSS_short_description.sql`, e.g.
  `20260727120000_init_schema.sql`. The timestamp ordering is what determines
  execution order, so never renumber an applied migration.
- **Migrations are append-only.** Once a migration has been merged, it has run in
  production. Never edit it — write a new one that alters what the old one did.
- Every new table needs explicit RLS policies in the same migration that creates
  it. The project has "automatically expose new tables" **and** automatic RLS
  enabled, so a table without policies is exposed to the Data API and silently
  returns **zero rows** — it does not error. That failure mode looks exactly like
  "no data yet", which is why it bites.
- Never write manual `GRANT` statements. Supabase manages role grants; RLS
  policies are the access control mechanism.
- `SECURITY DEFINER` functions must set `search_path = ''` and fully qualify every
  table reference, or a caller-controlled `search_path` can redirect them.

## Local testing (optional but recommended for schema changes)

Requires Docker and the Supabase CLI:

```bash
npx supabase start
npx supabase db reset
```

`db reset` replays every migration from scratch against a local Postgres. It
catches syntax errors and RLS policy recursion in seconds — far better than
finding them in the deploy log after a push.
