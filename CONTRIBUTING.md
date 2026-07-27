# Contributing

Two developers, one codebase. These conventions exist so we spend our review time
on decisions rather than on formatting and merge conflicts.

---

## How we split work

**By feature, not by layer.** Each person owns a slice end to end — database
schema, data access, and UI.

One of us does not write "all the backend" while the other writes "all the
frontend". Whoever takes _trip creation_ writes the migration for it, the query
functions in `/lib`, and the components and routes. Whoever takes _the follow
graph_ does the same for follows.

Why: layer splits mean every feature needs both people and nothing ships until
both are done. Feature splits mean each person can finish something. It also
keeps the person making a schema decision close to the UI consequences of it —
which matters a lot with our RLS model, where a policy choice directly determines
what a screen can display.

The cost is that we each touch every layer, so the conventions below have to be
followed by both of us for the code to stay coherent.

**Coordinate before you start** on anything that changes shared surface area:

- A new table, or a new column on an existing table
- Any change to an RLS policy or a helper function
- Anything in `types/`
- A new dependency

Everything else, just go.

---

## Branches

Branch off `main`:

```
feat/    a new capability          feat/weekend-grid
fix/     a bug fix                 fix/trip-date-overlap
chore/   tooling, deps, docs, CI   chore/project-setup
```

Lowercase, hyphen-separated, short. Name the thing, not the ticket.

One branch per feature slice. If a branch grows past roughly 400 changed lines,
it probably wants splitting.

---

## Commits

[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>): <subject>

<optional body — the why, not the what>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `style`, `perf`.

```
feat(trips): add weekend grid to semester view
fix(auth): refresh session before rendering profile
chore: add prettier and eslint-config-prettier
docs: document trip visibility resolution order
```

Rules:

- Subject in the imperative — "add", not "added" or "adds".
- No trailing full stop. Under 72 characters.
- The body explains **why**. The diff already shows what.
- Commit working increments. Do not commit code that fails `npm run build`.

---

## Before you open a PR

All four must pass:

```bash
npm run lint
npm run typecheck
npm run format:check
npm run build
```

---

## Pull requests

Every change goes through a PR. No pushing to `main`.

**The description should cover**

- What changed, and why.
- Anything you guessed at, or any decision the spec did not cover. This is the
  most useful part of the description — flag it rather than burying it in the
  diff.
- A screenshot or short clip for anything with UI.
- **An explicit callout if the PR contains a migration.** See below.
- How you tested it.

**Reviewing**

- Both of us review anything touching RLS, `types/`, or a migration. Everything
  else needs one approval.
- Reviews are about correctness and consistency with existing patterns. Prettier
  already settled formatting — do not spend review comments on it.
- If you disagree with a review comment, say so and explain. Do not silently
  implement something you think is wrong.

---

## Migrations need extra care

**Migrations under `supabase/migrations/` run automatically against the hosted
database when merged to `main`.** There is no manual apply step and no staging
gate. Review is the only thing between a bad migration and production data.

So:

- **Call out the migration in the PR title or description.** Never let one slip
  through unmentioned.
- **Migrations are append-only.** Once merged, it has run. Never edit an existing
  migration — write a new one that alters what it did. Never renumber one.
- Filename: `YYYYMMDDHHMMSS_short_description.sql`. Timestamp ordering determines
  execution order.
- **Every new table needs explicit RLS policies in the same migration.** The
  project auto-exposes new tables with RLS on, so a table without policies is
  live and silently returns zero rows. It does not error.
- Never write manual `GRANT` statements.
- Update `types/database.ts` in the same commit. The schema and its TypeScript
  mirror must never disagree.
- Test locally first if you have Docker: `npx supabase db reset`.

---

## Code conventions

Full detail in [CLAUDE.md](CLAUDE.md) and the `README.md` in each folder. The
short version:

- **Every database query lives in `/lib`.** Never inline a query in a component
  or route.
- **Components receive data as props.** They do not fetch it.
- **Server Components by default.** `'use client'` on the smallest leaf that
  needs it.
- **Never construct a Supabase client outside `lib/supabase/`.**
- Files `kebab-case`, components `PascalCase`, database `snake_case`.
- Named exports, except where Next.js requires a default.

**Comment the why, not the what.** Especially around privacy logic — a future
reader needs to know which product rule a policy encodes, not what the SQL says.

---

## Dependencies

Ask before adding one. The current list is short on purpose, and every addition
is something both of us have to learn and maintain.

If we do add one: production dependencies need a real justification; dev
dependencies are easier but still worth a sentence in the PR.
