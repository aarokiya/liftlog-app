"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/supabase/server";
import { DEFAULT_TIME_ZONE, fromZonedInput, validTimeZone } from "@/lib/time";

const now = () => new Date().toISOString();
const num = (v: FormDataEntryValue | null) => (v === null || v === "" ? null : Number(v));
const zoneOf = (formData: FormData) => validTimeZone(String(formData.get("timezone") ?? "")) ?? DEFAULT_TIME_ZONE;

export async function createWorkout(formData: FormData) {
  const { supabase } = await requireUser();
  const timezone = zoneOf(formData);
  const local = String(formData.get("started_at") || "");
  const started = local ? fromZonedInput(local, timezone).toISOString() : now();
  const { data, error } = await supabase
    .from("workouts")
    .insert({
      name: String(formData.get("name") || "Workout"),
      started_at: started,
      ended_at: started,
      timezone,
      source: "web",
    })
    .select("id")
    .single();
  if (error) throw error;
  redirect(`/workouts/${data.id}`);
}

export async function updateWorkout(formData: FormData) {
  const { supabase } = await requireUser();
  const id = String(formData.get("id"));
  const startedAt = fromZonedInput(String(formData.get("started_at")), zoneOf(formData)).toISOString();
  const minutes = num(formData.get("duration_minutes"));
  // A blank duration means "unknown", except on workouts logged in the app, where no end time means in progress.
  const { data: current } = await supabase.from("workouts").select("source").eq("id", id).single();
  const clearEnd = minutes === null && current?.source !== "app";
  const { error } = await supabase
    .from("workouts")
    .update({
      name: String(formData.get("name")),
      notes: String(formData.get("notes") || "") || null,
      started_at: startedAt,
      ...(minutes !== null
        ? { ended_at: new Date(new Date(startedAt).getTime() + minutes * 60_000).toISOString() }
        : clearEnd
          ? { ended_at: null }
          : {}),
    })
    .eq("id", id);
  if (error) throw error;
  revalidatePath(`/workouts/${id}`);
}

export async function deleteWorkout(formData: FormData) {
  const { supabase } = await requireUser();
  await supabase.from("workouts").update({ deleted_at: now() }).eq("id", String(formData.get("id")));
  redirect("/workouts");
}

export async function addExercise(formData: FormData) {
  const { supabase } = await requireUser();
  const workoutId = String(formData.get("workout_id"));
  const { count } = await supabase
    .from("workout_exercises")
    .select("id", { count: "exact", head: true })
    .eq("workout_id", workoutId);
  const { error } = await supabase
    .from("workout_exercises")
    .insert({ workout_id: workoutId, exercise_id: String(formData.get("exercise_id")), position: count ?? 0 });
  if (error) throw error;
  revalidatePath(`/workouts/${workoutId}`);
}

export async function removeExercise(formData: FormData) {
  const { supabase } = await requireUser();
  await supabase.from("workout_exercises").update({ deleted_at: now() }).eq("id", String(formData.get("id")));
  revalidatePath(`/workouts/${formData.get("workout_id")}`);
}

export async function addSet(formData: FormData) {
  const { supabase } = await requireUser();
  const workoutExerciseId = String(formData.get("workout_exercise_id"));
  const { data: last } = await supabase
    .from("sets")
    .select("position, weight, weight_unit, reps")
    .eq("workout_exercise_id", workoutExerciseId)
    .is("deleted_at", null)
    .order("position", { ascending: false })
    .limit(1)
    .maybeSingle();
  const { error } = await supabase.from("sets").insert({
    workout_exercise_id: workoutExerciseId,
    position: (last?.position ?? -1) + 1,
    weight: last?.weight ?? null,
    weight_unit: last?.weight_unit ?? String(formData.get("unit") || "lb"),
    reps: last?.reps ?? null,
    completed_at: now(),
  });
  if (error) throw error;
  revalidatePath(`/workouts/${formData.get("workout_id")}`);
}

export async function updateSet(formData: FormData) {
  const { supabase } = await requireUser();
  const { error } = await supabase
    .from("sets")
    .update({
      set_type: String(formData.get("set_type")),
      weight: num(formData.get("weight")),
      weight_unit: String(formData.get("weight_unit")),
      reps: num(formData.get("reps")),
      rpe: num(formData.get("rpe")),
    })
    .eq("id", String(formData.get("id")));
  if (error) throw error;
  revalidatePath(`/workouts/${formData.get("workout_id")}`);
}

export async function deleteSet(formData: FormData) {
  const { supabase } = await requireUser();
  await supabase.from("sets").update({ deleted_at: now() }).eq("id", String(formData.get("id")));
  revalidatePath(`/workouts/${formData.get("workout_id")}`);
}
