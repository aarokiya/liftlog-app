import Link from "next/link";
import { getExercises } from "@/lib/data";
import { requireUser } from "@/lib/supabase/server";
import { MUSCLE_LABELS } from "@/lib/types";
import { createExercise } from "./actions";

export default async function ExercisesPage() {
  const { supabase } = await requireUser();
  const exercises = await getExercises(supabase);
  const byMuscle: Record<string, typeof exercises> = {};
  for (const e of exercises) (byMuscle[e.primary_muscle] ??= []).push(e);

  return (
    <div className="flex flex-col gap-4">
      <form action={createExercise} className="card flex flex-wrap items-end gap-2">
        <input name="name" required placeholder="Custom exercise name" className="input" />
        <select name="primary_muscle" className="input">
          {Object.entries(MUSCLE_LABELS).map(([id, label]) => (
            <option key={id} value={id}>
              {label}
            </option>
          ))}
        </select>
        <input name="secondary_muscles" placeholder="secondary, comma separated" className="input" />
        <input name="equipment" placeholder="equipment" className="input w-28" />
        <button className="btn">Add exercise</button>
      </form>
      {Object.entries(byMuscle).map(([muscle, list]) => (
        <section key={muscle}>
          <h2 className="mb-1 text-sm font-medium text-muted">{MUSCLE_LABELS[muscle] ?? muscle}</h2>
          <ul className="grid gap-1 md:grid-cols-3">
            {list.map((e) => (
              <li key={e.id}>
                <Link href={`/exercises/${e.id}`} className="block rounded px-2 py-1 hover:bg-card">
                  {e.name} {e.user_id && <span className="text-xs text-muted">custom</span>}
                </Link>
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}
