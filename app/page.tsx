/**
 * Placeholder landing page.
 *
 * Exists so the scaffold renders and Tailwind is visibly working. Replace it
 * with the real landing page when that feature gets built — nothing else
 * depends on this file.
 */
export default function Home() {
  return (
    <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col justify-center px-6 py-24">
      <h1 className="text-4xl font-semibold tracking-tight text-balance sm:text-5xl">
        AbroadTRIPsite
      </h1>
      <p className="mt-4 text-lg text-pretty text-foreground/70">
        Plan your semester abroad weekend by weekend, then share where you&apos;ve been.
      </p>
      <p className="mt-10 font-mono text-sm text-foreground/50">
        Project scaffold — no features yet. See CLAUDE.md and CONTRIBUTING.md.
      </p>
    </main>
  );
}
