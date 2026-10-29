import Link from "next/link";
import { getProfile } from "@/lib/data";
import { exerciseUuid, programLabel, TEMPLATES, weeklySets } from "@/lib/programs";
import { requireUser } from "@/lib/supabase/server";
import { MUSCLE_LABELS } from "@/lib/types";
import { activateProgram, importProgram } from "./actions";

export default async function ProgramsPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  const { supabase, user } = await requireUser();
  const [profile, { data: exercises }, { data: routines }] = await Promise.all([
    getProfile(supabase, user.id),
    supabase.from("exercises").select("id, name, primary_muscle").is("deleted_at", null),
    supabase.from("routines").select("id, name, program, program_day").not("program", "is", null).is("deleted_at", null).order("program_day"),
  ]);
  const byId = new Map((exercises ?? []).map((e) => [e.id as string, e]));
  const custom = [...new Set((routines ?? []).map((r) => r.program as string))].filter((p) => !TEMPLATES.some((t) => t.id === p));

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold">Programs</h1>
        <p className="text-sm text-muted">
          Switching creates the program&apos;s days as routines (once) and makes it your active split on the phone and here.
          {profile.campus === "gatech"
            ? " Exercises use Georgia Tech CRC equipment; swap any of them from the routine page."
            : " They use machines, cables and free weights; if your gym lacks one, swap it for the same movement from the routine page."}
        </p>
      </div>
      {error && <p className="text-sm text-red-500">{error}</p>}
      <div className="grid gap-4 md:grid-cols-2">
        {TEMPLATES.map((t) => {
          const active = profile.active_program === t.id;
          const sets = weeklySets(t, (id) => byId.get(id)?.primary_muscle, t.split === "UL" ? 4 : t.split === "PPLUL" ? 5 : 6);
          return (
            <section key={t.id} className={`card flex flex-col gap-3 ${active ? "border-accent" : ""}`}>
              <div className="flex items-start justify-between gap-2">
                <div>
                  <h2 className="font-medium">
                    {t.name} {active && <span className="text-xs text-accent">active</span>}
                  </h2>
                  <p className="text-xs text-muted">{t.schedule}</p>
                </div>
                {!active && (
                  <form action={activateProgram}>
                    <input type="hidden" name="id" value={t.id} />
                    <button className="btn">Switch</button>
                  </form>
                )}
              </div>
              {t.days.map((d) => (
                <div key={d.name} className="text-sm">
                  <div className="font-medium">{d.name}</div>
                  <ul className="text-muted">
                    {d.exercises.map((e, i) => (
                      <li key={i}>
                        {byId.get(exerciseUuid(e.exercise))?.name ?? "Unknown exercise"}: {e.sets}{e.reps ? ` × ${e.reps[0]}–${e.reps[1]}` : ""}
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
              <p className="text-xs text-muted">
                Weekly sets:{" "}
                {Object.entries(sets)
                  .sort((a, b) => b[1] - a[1])
                  .map(([m, n]) => `${MUSCLE_LABELS[m as keyof typeof MUSCLE_LABELS] ?? m} ${Math.round(n)}`)
                  .join(", ")}
              </p>
            </section>
          );
        })}
        {custom.map((id) => (
          <section key={id} className={`card flex flex-col gap-2 ${profile.active_program === id ? "border-accent" : ""}`}>
            <div className="flex items-start justify-between gap-2">
              <h2 className="font-medium">
                {programLabel(id)} {profile.active_program === id && <span className="text-xs text-accent">active</span>}
              </h2>
              {profile.active_program !== id && (
                <form action={activateProgram}>
                  <input type="hidden" name="id" value={id} />
                  <button className="btn">Switch</button>
                </form>
              )}
            </div>
            <ul className="text-sm">
              {(routines ?? [])
                .filter((r) => r.program === id)
                .map((r) => (
                  <li key={r.id}>
                    <Link href={`/routines/${r.id}`} className="hover:text-accent">
                      {r.name}
                    </Link>
                  </li>
                ))}
            </ul>
          </section>
        ))}
      </div>
      <form action={importProgram} className="card flex flex-col gap-2">
        <h2 className="font-medium">Import a program</h2>
        <p className="text-xs text-muted">
          Paste program JSON (for example one converted from a split video). Format: see docs/PROGRAMS.md. Importing a program
          with the same name replaces it.
        </p>
        <textarea name="json" required rows={6} className="input font-mono text-xs" placeholder='{"name": "...", "days": [...]}' />
        <button className="btn self-start">Import and switch</button>
      </form>
    </div>
  );
}
