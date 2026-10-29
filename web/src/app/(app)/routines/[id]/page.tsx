import { notFound } from "next/navigation";
import { getExercises, getProfile } from "@/lib/data";
import { GYMS, substitutes } from "@/lib/gym";
import { requireUser } from "@/lib/supabase/server";
import { addRoutineExercise, deleteRoutine, removeRoutineExercise, swapRoutineExercise, updateRoutine, updateRoutineExercise } from "../actions";

interface RoutineExercise {
  id: string;
  position: number;
  target_sets: number;
  rep_min: number | null;
  rep_max: number | null;
  rest_seconds: number | null;
  notes: string | null;
  attachment: string | null;
  deleted_at: string | null;
  exercise_id: string;
  exercises: { name: string } | null;
}

export default async function RoutinePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase, user } = await requireUser();
  const [{ data: routine }, exercises, profile] = await Promise.all([
    supabase
      .from("routines")
      .select("id, name, notes, routine_exercises(id, exercise_id, position, target_sets, rep_min, rep_max, rest_seconds, notes, attachment, deleted_at, exercises(name))")
      .eq("id", id)
      .single(),
    getExercises(supabase),
    getProfile(supabase, user.id),
  ]);
  if (!routine) notFound();
  const items = (routine.routine_exercises as unknown as RoutineExercise[])
    .filter((x) => !x.deleted_at)
    .sort((a, b) => a.position - b.position);
  // CRC same-movement swaps only make sense at Georgia Tech.
  // Same-movement swaps come from the CRC list but suit most gyms, so everyone gets them.
  const gym = GYMS[0];
  const gatech = profile.campus === "gatech";
  const nameById = new Map(exercises.map((e) => [e.id, e.name]));

  return (
    <div className="flex flex-col gap-4">
      <form action={updateRoutine} className="card flex flex-col gap-2">
        <input type="hidden" name="id" value={routine.id} />
        <input name="name" defaultValue={routine.name} className="input text-lg" />
        <textarea name="notes" defaultValue={routine.notes ?? ""} placeholder="Notes" className="input" />
        <button className="btn self-start">Save</button>
      </form>
      {items.map((x) => (
        <form key={x.id} action={updateRoutineExercise} className="card flex flex-wrap items-end gap-2 text-sm">
          <input type="hidden" name="id" value={x.id} />
          <input type="hidden" name="routine_id" value={routine.id} />
          <span className="w-full font-medium md:w-56">{x.exercises?.name}</span>
          <label className="flex flex-col text-xs text-muted">
            Sets
            <input name="target_sets" type="number" min={0} defaultValue={x.target_sets} className="input w-16" />
          </label>
          <label className="flex flex-col text-xs text-muted">
            Reps
            <span className="flex items-center gap-1">
              <input name="rep_min" type="number" min={0} defaultValue={x.rep_min ?? ""} className="input w-16" />–
              <input name="rep_max" type="number" min={0} defaultValue={x.rep_max ?? ""} className="input w-16" />
            </span>
          </label>
          <label className="flex flex-col text-xs text-muted">
            Rest (s)
            <input name="rest_seconds" type="number" min={0} defaultValue={x.rest_seconds ?? ""} className="input w-20" />
          </label>
          <input name="attachment" defaultValue={x.attachment ?? ""} maxLength={80} placeholder="Attachment (e.g. Rope · top pulley)" className="input w-56" />
          <input name="notes" defaultValue={x.notes ?? ""} placeholder="Notes" className="input flex-1" />
          <button className="btn-ghost">Save</button>
          <button formAction={removeRoutineExercise} className="text-xs text-muted hover:text-red-500">
            Remove
          </button>
          {substitutes(gym, x.exercise_id).length > 0 && (
            <span className="flex w-full items-center gap-2 text-xs text-muted">
              {gatech ? "Swap at CRC:" : "Swap:"}
              <select name="exercise_id" className="input py-1 text-xs" defaultValue="">
                <option value="" disabled>
                  same movement…
                </option>
                {substitutes(gym, x.exercise_id)
                  .filter((id) => nameById.has(id))
                  .map((id) => (
                    <option key={id} value={id}>
                      {nameById.get(id)}
                    </option>
                  ))}
              </select>
              <button formAction={swapRoutineExercise} className="btn-ghost text-xs">
                Swap
              </button>
            </span>
          )}
        </form>
      ))}
      <form action={addRoutineExercise} className="card flex flex-wrap gap-2">
        <input type="hidden" name="routine_id" value={routine.id} />
        <select name="exercise_id" className="input" required>
          {exercises.map((e) => (
            <option key={e.id} value={e.id}>
              {e.name}
            </option>
          ))}
        </select>
        <button className="btn">Add exercise</button>
      </form>
      <form action={deleteRoutine}>
        <input type="hidden" name="id" value={routine.id} />
        <button className="text-sm text-red-500">Delete routine</button>
      </form>
    </div>
  );
}
