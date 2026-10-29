"use server";

import { revalidatePath } from "next/cache";
import { exerciseKey, parseRepCount, type Unit } from "@/lib/import/repcount";
import { requireUser } from "@/lib/supabase/server";

export interface ImportState {
  error?: string;
  imported?: number;
  skipped?: number;
  createdExercises?: string[];
  renamed?: Record<string, string>;
  bodyWeights?: number;
  source?: string;
  columns?: Record<string, string>;
}

export async function importRepCount(_prev: ImportState, formData: FormData): Promise<ImportState> {
  const { supabase, user } = await requireUser();
  const file = formData.get("file");
  if (!(file instanceof File) || file.size === 0) return { error: "Choose a CSV file first." };

  let parsed;
  try {
    parsed = parseRepCount(await file.text(), {
      timeZone: String(formData.get("timezone") || "UTC"),
      defaultUnit: (String(formData.get("unit")) as Unit) || "lb",
    });
  } catch (e) {
    return { error: (e as Error).message };
  }
  if (parsed.workouts.length === 0) return { error: "No workouts found in that file.", columns: parsed.columns };

  const { data: library, error: libraryError } = await supabase
    .from("exercises")
    .select("id, name")
    .is("deleted_at", null);
  if (libraryError) return { error: libraryError.message };
  const byKey = new Map(library.map((e) => [exerciseKey(e.name), e.id as string]));

  const createdExercises: string[] = [];
  for (const name of new Set(parsed.workouts.flatMap((w) => w.exercises.map((e) => e.name)))) {
    if (byKey.has(exerciseKey(name))) continue;
    const { data, error } = await supabase
      .from("exercises")
      .insert({ user_id: user.id, name, primary_muscle: "other", secondary_muscles: [] })
      .select("id")
      .single();
    if (error) return { error: `Couldn't create exercise ${name}: ${error.message}` };
    byKey.set(exerciseKey(name), data.id);
    createdExercises.push(name);
  }

  const { data: existing } = await supabase
    .from("workouts")
    .select("started_at")
    .eq("source", parsed.source)
    .is("deleted_at", null);
  const seen = new Set((existing ?? []).map((w) => new Date(w.started_at).toISOString()));

  let imported = 0;
  let skipped = 0;
  for (const workout of parsed.workouts) {
    if (seen.has(workout.startedAt)) {
      skipped++;
      continue;
    }
    const workoutId = crypto.randomUUID();
    const exercises = workout.exercises.map((e, position) => ({
      id: crypto.randomUUID(),
      workout_id: workoutId,
      exercise_id: byKey.get(exerciseKey(e.name))!,
      position,
      sets: e.sets,
    }));
    const { error: workoutError } = await supabase.from("workouts").insert({
      id: workoutId,
      name: workout.name,
      started_at: workout.startedAt,
      ended_at: workout.endedAt,
      timezone: String(formData.get("timezone") || "UTC"),
      source: parsed.source,
    });
    if (workoutError) return { error: workoutError.message, imported };
    const { error: exerciseError } = await supabase
      .from("workout_exercises")
      .insert(exercises.map((e) => ({ id: e.id, workout_id: e.workout_id, exercise_id: e.exercise_id, position: e.position })));
    if (exerciseError) return { error: exerciseError.message, imported };
    const sets = exercises.flatMap((e) =>
      e.sets.map((s, position) => ({
        workout_exercise_id: e.id,
        position,
        set_type: s.type,
        weight: s.weight,
        weight_unit: s.unit,
        reps: s.reps,
        rpe: s.rpe !== null && s.rpe >= 1 && s.rpe <= 10 ? s.rpe : null,
        notes: s.notes,
        completed_at: workout.startedAt,
      })),
    );
    const { error: setError } = await supabase.from("sets").insert(sets);
    if (setError) return { error: setError.message, imported };
    imported++;
  }

  const { data: existingMetrics } = await supabase
    .from("body_metrics")
    .select("measured_at")
    .eq("source", parsed.source)
    .is("deleted_at", null);
  const seenMetrics = new Set((existingMetrics ?? []).map((m) => new Date(m.measured_at).toISOString()));
  const metrics = parsed.workouts
    .filter((w) => w.bodyWeight && !seenMetrics.has(w.startedAt))
    .map((w) => ({ measured_at: w.startedAt, body_weight: w.bodyWeight!.value, unit: w.bodyWeight!.unit, source: parsed.source }));
  if (metrics.length > 0) {
    const { error } = await supabase.from("body_metrics").insert(metrics);
    if (error) return { error: `Workouts imported, but body weight failed: ${error.message}`, imported };
  }

  revalidatePath("/", "layout");
  return {
    imported,
    skipped,
    createdExercises,
    renamed: parsed.renamed,
    bodyWeights: metrics.length,
    source: parsed.source,
    columns: parsed.columns,
  };
}
