import { notFound } from "next/navigation";
import { getExercises, getProfile, getWorkout } from "@/lib/data";
import { requireUser } from "@/lib/supabase/server";
import { toZonedInput, validTimeZone } from "@/lib/time";
import { userTimeZone } from "@/lib/time/server";
import { addExercise, addSet, deleteSet, deleteWorkout, removeExercise, updateSet, updateWorkout } from "../actions";

const SET_TYPES = ["warmup", "working", "drop", "failure"] as const;

export default async function WorkoutPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase, user } = await requireUser();
  const [workout, exercises, profile] = await Promise.all([
    getWorkout(supabase, id),
    getExercises(supabase),
    getProfile(supabase, user.id),
  ]);
  if (!workout) notFound();
  // Shown and saved in the zone the workout happened in.
  const tz = validTimeZone(workout.timezone) ?? (await userTimeZone());
  const duration = workout.ended_at
    ? Math.round((new Date(workout.ended_at).getTime() - new Date(workout.started_at).getTime()) / 60_000)
    : "";

  return (
    <div className="flex flex-col gap-4">
      <form action={updateWorkout} className="card grid gap-2 md:grid-cols-[2fr_1fr_1fr_auto] md:items-end">
        <input type="hidden" name="id" value={workout.id} />
        <input type="hidden" name="timezone" value={tz} />
        <label className="flex flex-col text-xs text-muted">
          Name
          <input name="name" defaultValue={workout.name} className="input text-base" />
        </label>
        <label className="flex flex-col text-xs text-muted">
          Started
          <input name="started_at" type="datetime-local" defaultValue={toZonedInput(workout.started_at, tz)} className="input" />
        </label>
        <label className="flex flex-col text-xs text-muted">
          Duration (min)
          <input name="duration_minutes" type="number" min={0} defaultValue={duration} className="input" />
        </label>
        <button className="btn">Save</button>
        <textarea name="notes" defaultValue={workout.notes ?? ""} placeholder="Notes" className="input md:col-span-4" />
      </form>

      {workout.workout_exercises.map((we) => (
        <section key={we.id} className="card">
          <div className="mb-2 flex items-center">
            <h2 className="font-medium">{we.exercises?.name ?? "Exercise"}</h2>
            <form action={removeExercise} className="ml-auto">
              <input type="hidden" name="id" value={we.id} />
              <input type="hidden" name="workout_id" value={workout.id} />
              <button className="text-xs text-muted hover:text-red-500">Remove</button>
            </form>
          </div>
          <div className="flex flex-col gap-1">
            {we.sets.map((s, i) => (
              <div key={s.id} className="flex flex-wrap items-center gap-2 text-sm">
                <form action={updateSet} className="flex flex-wrap items-center gap-2">
                  <input type="hidden" name="id" value={s.id} />
                  <input type="hidden" name="workout_id" value={workout.id} />
                  <span className="w-6 text-muted">{i + 1}</span>
                  <select name="set_type" defaultValue={s.set_type} className="input">
                    {SET_TYPES.map((t) => (
                      <option key={t}>{t}</option>
                    ))}
                  </select>
                  {we.exercises?.kind === "duration" ? (
                    <>
                      <input type="hidden" name="weight_unit" value={s.weight_unit} />
                      <input
                        name="minutes"
                        type="number"
                        step="0.5"
                        min={0}
                        defaultValue={s.duration_seconds !== null ? Math.round((s.duration_seconds / 60) * 10) / 10 : ""}
                        className="input w-20"
                        aria-label="Minutes"
                      />
                      <span className="text-muted">min</span>
                    </>
                  ) : (
                    <>
                      <input name="weight" type="number" step="0.5" defaultValue={s.weight ?? ""} className="input w-20" aria-label="Weight" />
                      <select name="weight_unit" defaultValue={s.weight_unit} className="input">
                        <option>lb</option>
                        <option>kg</option>
                      </select>
                      <span className="text-muted">×</span>
                      <input name="reps" type="number" min={0} defaultValue={s.reps ?? ""} className="input w-16" aria-label="Reps" />
                    </>
                  )}
                  <input name="rpe" type="number" step="0.5" min={1} max={10} defaultValue={s.rpe ?? ""} placeholder="RPE" className="input w-16" />
                  <button className="btn-ghost">Save</button>
                </form>
                <form action={deleteSet}>
                  <input type="hidden" name="id" value={s.id} />
                  <input type="hidden" name="workout_id" value={workout.id} />
                  <button className="text-xs text-muted hover:text-red-500" aria-label="Delete set">✕</button>
                </form>
              </div>
            ))}
          </div>
          <form action={addSet} className="mt-2">
            <input type="hidden" name="workout_exercise_id" value={we.id} />
            <input type="hidden" name="workout_id" value={workout.id} />
            <input type="hidden" name="unit" value={profile.default_unit} />
            <button className="btn-ghost">+ Add set</button>
          </form>
        </section>
      ))}

      <form action={addExercise} className="card flex flex-wrap items-center gap-2">
        <input type="hidden" name="workout_id" value={workout.id} />
        <select name="exercise_id" className="input" required>
          {exercises.map((e) => (
            <option key={e.id} value={e.id}>
              {e.name}
            </option>
          ))}
        </select>
        <button className="btn">Add exercise</button>
      </form>

      <form action={deleteWorkout}>
        <input type="hidden" name="id" value={workout.id} />
        <button className="text-sm text-red-500">Delete workout</button>
      </form>
    </div>
  );
}
