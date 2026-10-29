"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/supabase/server";

export async function createExercise(formData: FormData) {
  const { supabase, user } = await requireUser();
  const secondary = String(formData.get("secondary_muscles") || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const { error } = await supabase.from("exercises").insert({
    user_id: user.id,
    name: String(formData.get("name")),
    equipment: String(formData.get("equipment") || "") || null,
    primary_muscle: String(formData.get("primary_muscle")),
    secondary_muscles: secondary,
  });
  if (error) throw error;
  revalidatePath("/exercises");
}
