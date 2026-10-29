"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { exerciseUuid, parseProgram, TEMPLATES, type Program } from "@/lib/programs";
import { requireUser } from "@/lib/supabase/server";

type Supabase = Awaited<ReturnType<typeof requireUser>>["supabase"];

function fail(message: string): never {
  redirect(`/programs?error=${encodeURIComponent(message)}`);
}

async function createRoutines(supabase: Supabase, program: Program) {
  const { data: last } = await supabase.from("routines").select("position").order("position", { ascending: false }).limit(1);
  const base = (last?.[0]?.position ?? -1) + 1;
  for (const [day, d] of program.days.entries()) {
    const routineId = crypto.randomUUID();
    const { error } = await supabase.from("routines").insert({
      id: routineId,
      name: d.name,
      notes: day === 0 ? (program.schedule ?? null) : null,
      position: base + day,
      program: program.id,
      program_day: day,
    });
    if (error) fail(error.message);
    const { error: itemsError } = await supabase.from("routine_exercises").insert(
      d.exercises.map((e, position) => ({
        routine_id: routineId,
        exercise_id: exerciseUuid(e.exercise),
        position,
        target_sets: e.sets,
        rep_min: e.reps?.[0] ?? null,
        rep_max: e.reps?.[1] ?? null,
        attachment: e.attachment ?? null,
        rest_seconds: e.rest ?? null,
        notes: e.notes ?? null,
      })),
    );
    if (itemsError) fail(`${d.name}: ${itemsError.message}`);
  }
}

async function setActive(supabase: Supabase, userId: string, programId: string | null) {
  const { error } = await supabase.from("profiles").update({ active_program: programId }).eq("id", userId);
  if (error) fail(error.message);
  revalidatePath("/", "layout");
}

export async function activateProgram(formData: FormData) {
  const { supabase, user } = await requireUser();
  const id = String(formData.get("id"));
  const { count } = await supabase
    .from("routines")
    .select("id", { count: "exact", head: true })
    .eq("program", id)
    .is("deleted_at", null);
  if (!count) {
    const template = TEMPLATES.find((t) => t.id === id);
    if (!template) fail("That program has no routines left; import it again.");
    await createRoutines(supabase, template);
  }
  await setActive(supabase, user.id, id);
  redirect("/programs");
}

export async function importProgram(formData: FormData) {
  const { supabase, user } = await requireUser();
  let program: Program;
  try {
    program = parseProgram(String(formData.get("json") ?? ""));
  } catch (e) {
    fail((e as Error).message);
  }
  // Re-importing a program with the same name replaces its routines.
  await supabase
    .from("routines")
    .update({ deleted_at: new Date().toISOString() })
    .eq("program", program.id)
    .is("deleted_at", null);
  await createRoutines(supabase, program);
  await setActive(supabase, user.id, program.id);
  redirect("/programs");
}
