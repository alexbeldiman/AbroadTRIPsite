# /types — shared TypeScript types

Types used by more than one module.

**Belongs here**

- `database.ts` — the `Database` interface mirroring the Postgres schema. This is
  the single source of truth for row shapes and enum unions.
- `index.ts` — ergonomic aliases derived from `database.ts` (`Profile`, `Trip`,
  `TripVisibility`, …) plus app-level composite types.

**Does not belong here**

- Component prop types — colocate those with the component.
- Types used by exactly one module — keep them in that module.

**Conventions**

- Never hand-write a row shape that duplicates `database.ts`. Derive it:
  `type Trip = Database['public']['Tables']['trips']['Row']`.
- Import from `@/types`, not from `@/types/database`, in app code. The barrel in
  `index.ts` is the public surface.

## Keeping `database.ts` honest

`database.ts` is currently **hand-written** to match
`supabase/migrations/20260727120000_init_schema.sql`, because generating it needs
the Supabase CLI logged in and linked to the project.

Once the migration is live, regenerate and diff:

```bash
npx supabase gen types typescript --project-id <project-ref> --schema public > types/database.ts
```

The generated file is the source of truth from that point on. If it differs from
the hand-written version, the generated one wins — and check whether app code
relied on the difference.
