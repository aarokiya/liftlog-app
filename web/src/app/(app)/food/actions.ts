"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/supabase/server";
import { MEALS, normalizeBarcode } from "@/lib/food";
import { redirect } from "next/navigation";

const num = (v: FormDataEntryValue | null) => {
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 10) / 10 : 0;
};

export async function logFood(formData: FormData) {
  const { supabase } = await requireUser();
  const name = String(formData.get("name") ?? "").trim().slice(0, 200);
  const meal = String(formData.get("meal"));
  const source = String(formData.get("source"));
  const servings = Number(formData.get("servings") ?? 1);
  if (!name || !["dining", "outside", "custom"].includes(source)) return;
  await supabase.from("food_logs").insert({
    eaten_at: new Date().toISOString(),
    meal: (MEALS as readonly string[]).includes(meal) ? meal : "snack",
    source,
    place: String(formData.get("place") ?? "") || null,
    name,
    serving: String(formData.get("serving") ?? "") || null,
    servings: Number.isFinite(servings) && servings > 0 && servings <= 50 ? servings : 1,
    kcal: num(formData.get("kcal")),
    protein: num(formData.get("protein")),
    carbs: num(formData.get("carbs")),
    fat: num(formData.get("fat")),
  });
  revalidatePath("/food");
}

export async function logWater(formData: FormData) {
  const { supabase } = await requireUser();
  const amount = Math.round(Number(formData.get("amount")) * 10) / 10;
  const unit = String(formData.get("unit"));
  if (!(amount > 0 && amount <= 5000) || !["oz", "ml"].includes(unit)) return;
  await supabase.from("water_logs").insert({ drank_at: new Date().toISOString(), amount, unit });
  revalidatePath("/food");
}

export async function deleteWater(formData: FormData) {
  const { supabase } = await requireUser();
  await supabase.from("water_logs").update({ deleted_at: new Date().toISOString() }).eq("id", String(formData.get("id")));
  revalidatePath("/food");
}

export async function deleteFood(formData: FormData) {
  const { supabase } = await requireUser();
  await supabase.from("food_logs").update({ deleted_at: new Date().toISOString() }).eq("id", String(formData.get("id")));
  revalidatePath("/food");
}

/** Adds a food to the shared databank (and logs one serving of it). */
export async function createFood(formData: FormData) {
  const { supabase, user } = await requireUser();
  const name = String(formData.get("name") ?? "").trim().slice(0, 200);
  if (!name) return;
  const row = {
    source: "user",
    created_by: user.id,
    name,
    brand: String(formData.get("brand") ?? "").trim().slice(0, 120) || null,
    barcode: normalizeBarcode(String(formData.get("barcode") ?? "")),
    serving: String(formData.get("serving") ?? "").trim().slice(0, 120) || "1 serving",
    kcal: num(formData.get("kcal")),
    protein: num(formData.get("protein")),
    carbs: num(formData.get("carbs")),
    fat: num(formData.get("fat")),
  };
  const { error } = await supabase.from("foods").insert(row);
  if (error) return;
  const log = new FormData();
  for (const [k, v] of Object.entries({ ...row, source: "outside", place: row.brand ?? "", meal: String(formData.get("meal") ?? "snack"), servings: "1" })) {
    log.set(k, String(v ?? ""));
  }
  await logFood(log);
  redirect(`/food?tab=search&q=${encodeURIComponent(name)}`);
}
