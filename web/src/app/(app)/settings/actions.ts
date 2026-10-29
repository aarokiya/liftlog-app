"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/supabase/server";

/** Lengths are typed in inches for lb users and cm for kg users. */
function lengthToCm(value: FormDataEntryValue | null, unit: string): number | null {
  const n = Number(value);
  if (value === null || value === "" || !Number.isFinite(n) || n <= 0) return null;
  return Math.round((unit === "lb" ? n * 2.54 : n) * 10) / 10;
}

function percent(value: FormDataEntryValue | null): number | null {
  const n = Number(value);
  return value === null || value === "" || !Number.isFinite(n) || n < 2 || n > 70 ? null : Math.round(n * 10) / 10;
}

export async function logMeasurement(formData: FormData) {
  const { supabase, user } = await requireUser();
  const unit = String(formData.get("unit"));
  const weight = Number(formData.get("body_weight"));
  const row = {
    user_id: user.id,
    measured_at: new Date().toISOString(),
    body_weight: weight > 0 ? weight : null,
    unit,
    waist_cm: lengthToCm(formData.get("waist"), unit),
    neck_cm: lengthToCm(formData.get("neck"), unit),
    hips_cm: lengthToCm(formData.get("hips"), unit),
    body_fat_pct: percent(formData.get("body_fat")),
    source: "manual",
  };
  if (row.body_weight === null && row.waist_cm === null && row.neck_cm === null && row.hips_cm === null && row.body_fat_pct === null) return;
  const { error } = await supabase.from("body_metrics").insert(row);
  if (error) throw error;
  revalidatePath("/", "layout");
}

export async function updateSettings(formData: FormData) {
  const { supabase, user } = await requireUser();
  const { error } = await supabase
    .from("profiles")
    .update({
      display_name: String(formData.get("display_name") || "") || null,
      default_unit: String(formData.get("default_unit")),
      e1rm_formula: String(formData.get("e1rm_formula")),
      weekly_workout_target: Number(formData.get("weekly_workout_target")),
      bar_weight: Number(formData.get("bar_weight")),
      height_cm: lengthToCm(formData.get("height"), String(formData.get("default_unit"))),
      campus: formData.get("campus") === "gatech" ? "gatech" : null,
      sex: formData.get("sex") === "male" || formData.get("sex") === "female" ? formData.get("sex") : null,
    })
    .eq("id", user.id);
  if (error) throw error;
  revalidatePath("/", "layout");
}
