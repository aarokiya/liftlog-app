import Link from "next/link";
import { programLabel } from "@/lib/programs";
import { requireUser } from "@/lib/supabase/server";
import { createRoutine } from "./actions";

export default async function RoutinesPage() {
  const { supabase } = await requireUser();
  const { data: routines } = await supabase
    .from("routines")
    .select("id, name, program, routine_exercises(id, deleted_at)")
    .is("deleted_at", null)
    .order("position");

  return (
    <div className="flex flex-col gap-4">
      <form action={createRoutine} className="card flex gap-2">
        <input name="name" placeholder="Push A" className="input" />
        <button className="btn">New routine</button>
      </form>
      <ul className="grid gap-3 md:grid-cols-3">
        {(routines ?? []).map((r) => (
          <li key={r.id}>
            <Link href={`/routines/${r.id}`} className="card block hover:border-accent">
              <div className="font-medium">{r.name}</div>
              {r.program && <div className="text-xs text-accent">{programLabel(r.program)}</div>}
              <div className="text-sm text-muted">
                {r.routine_exercises.filter((x: { deleted_at: string | null }) => !x.deleted_at).length} exercises
              </div>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
