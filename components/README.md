# /components — reusable UI

Presentational, reusable React components. If it renders and more than one route
could use it, it goes here.

**Belongs here**

- Buttons, inputs, modals, cards, badges, empty states
- Composite UI like `WeekendGrid`, `TripCard`, `RatingStars`
- Layout primitives (`Container`, `Stack`) and skeleton loaders

**Does not belong here**

- Supabase clients or database queries. Components receive data via props; they
  do not fetch it. This keeps them trivially testable and reusable, and it keeps
  every query in one place (`/lib`) where the RLS implications are reviewable.
- Route-specific one-offs used by a single page — colocate those next to the page.

**Conventions**

- One component per file. File is `kebab-case`, the exported component is
  `PascalCase`: `trip-card.tsx` exports `TripCard`.
- Props interfaces are named `<ComponentName>Props` and exported when a parent
  might need them.
- Default to Server Components. Mark `'use client'` only where interactivity
  actually lives.
- Subfolders group by domain once a folder gets busy: `components/trips/`,
  `components/profile/`, `components/ui/` for generic primitives.
