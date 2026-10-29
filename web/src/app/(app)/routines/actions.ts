"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/supabase/server";

const num = (v: FormDataEntryValue | null) => (v === null || v === "" ? null : Number(v));

export async function createRoutine(formData: FormData) {
  const { supabase } = await requireUser();
  const { data, error } = await supabase
    .from("routines")
    .insert({ name: String(formData.get("name") || "New routine") })
    .select("id")
    .single();
  if (error) throw error;
  redirect(`/routines/${data.id}`);
}

export async function updateRoutine(formData: FormData) {
  const { supabase } = await requireUser();
  const id = String(formData.get("id"));
  await supabase
    .from("routines")
    .update({ name: String(formData.get("name")), notes: String(formData.get("notes") || "") || null })
    .eq("id", id);
  revalidatePath(`/routines/${id}`);
}

export async function deleteRoutine(formData: FormData) {
  const { supabase } = await requireUser();
  await supabase.from("routines").update({ deleted_at: new Date().toISOString() }).eq("id", String(formData.get("id")));
  redirect("/routines");
}

export async function addRoutineExercise(formData: FormData) {
  const { supabase } = await requireUser();
  const routineId = String(formData.get("routine_id"));
  const { count } = await supabase
    .from("routine_exercises")
    .select("id", { count: "exact", head: true })
    .eq("routine_id", routineId);
  const { error } = await supabase.from("routine_exercises").insert({
    routine_id: routineId,
    exercise_id: String(formData.get("exercise_id")),
    position: count ?? 0,
    target_sets: 3,
    rep_min: 8,
    rep_max: 12,
  });
  if (error) throw error;
  revalidatePath(`/routines/${routineId}`);
}

export async function updateRoutineExercise(formData: FormData) {
  const { supabase } = await requireUser();
  const { error } = await supabase
    .from("routine_exercises")
    .update({
      target_sets: num(formData.get("target_sets")) ?? 3,
      rep_min: num(formData.get("rep_min")),
      rep_max: num(formData.get("rep_max")),
      rest_seconds: num(formData.get("rest_seconds")),
      notes: String(formData.get("notes") || "") || null,
      attachment: String(formData.get("attachment") || "").trim().slice(0, 80) || null,
    })
    .eq("id", String(formData.get("id")));
  if (error) throw error;
  revalidatePath(`/routines/${formData.get("routine_id")}`);
}

export async function removeRoutineExercise(formData: FormData) {
  const { supabase } = await requireUser();
  await supabase
    .from("routine_exercises")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", String(formData.get("id")));
  revalidatePath(`/routines/${formData.get("routine_id")}`);
}

export async function swapRoutineExercise(formData: FormData) {
  const { supabase } = await requireUser();
  const exerciseId = String(formData.get("exercise_id") || "");
  if (!exerciseId) return;
  const { error } = await supabase
    .from("routine_exercises")
    .update({ exercise_id: exerciseId })
    .eq("id", String(formData.get("id")));
  if (error) throw error;
  revalidatePath(`/routines/${formData.get("routine_id")}`);
}
