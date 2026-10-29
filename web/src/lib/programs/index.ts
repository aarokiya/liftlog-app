import arnold from "../../../../shared/programs/arnold.json";
import ppl from "../../../../shared/programs/ppl.json";
import pplul from "../../../../shared/programs/pplul.json";
import ul from "../../../../shared/programs/ul.json";
import { builtInId } from "../gym";

export interface ProgramExercise {
  /** Built-in exercise number (see supabase/seed.sql) or a full exercise uuid. */
  exercise: number | string;
  sets: number;
  reps: [number, number];
  rest?: number;
  notes?: string;
}

export interface ProgramDay {
  name: string;
  exercises: ProgramExercise[];
}

export interface Program {
  id: string;
  name: string;
  split: string;
  gym?: string;
  schedule?: string;
  days: ProgramDay[];
}

export const TEMPLATES = [ppl, ul, pplul, arnold] as Program[];

/** Display name for a program id: the template's name, or an imported program's slug in title case. */
export function programLabel(id: string): string {
  return TEMPLATES.find((t) => t.id === id)?.name ?? id.replace(/^custom-/, "").split("-").map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
}

export const exerciseUuid = (e: number | string) => (typeof e === "number" ? builtInId(e) : e);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Validates a program pasted as JSON (e.g. one converted from a video) and returns it with a safe id. */
export function parseProgram(text: string): Program {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new Error("That isn't valid JSON.");
  }
  const p = raw as Partial<Program>;
  if (typeof p.name !== "string" || !p.name.trim()) throw new Error("Program needs a name.");
  if (!Array.isArray(p.days) || p.days.length === 0 || p.days.length > 14) throw new Error("Program needs 1-14 days.");
  const days = p.days.map((d, i) => {
    if (typeof d?.name !== "string" || !Array.isArray(d.exercises) || d.exercises.length === 0) {
      throw new Error(`Day ${i + 1} needs a name and exercises.`);
    }
    return {
      name: d.name.trim(),
      exercises: d.exercises.map((e, j) => {
        const where = `${d.name} exercise ${j + 1}`;
        const ok = (typeof e.exercise === "number" && Number.isInteger(e.exercise) && e.exercise > 0) || (typeof e.exercise === "string" && UUID.test(e.exercise));
        if (!ok) throw new Error(`${where}: "exercise" must be a built-in number or exercise id.`);
        if (!Number.isInteger(e.sets) || e.sets < 1 || e.sets > 20) throw new Error(`${where}: sets must be 1-20.`);
        if (!Array.isArray(e.reps) || e.reps.length !== 2 || !(e.reps[0] >= 1 && e.reps[1] >= e.reps[0] && e.reps[1] <= 100)) {
          throw new Error(`${where}: reps must be [min, max].`);
        }
        return { exercise: e.exercise, sets: e.sets, reps: [e.reps[0], e.reps[1]] as [number, number], rest: e.rest, notes: e.notes };
      }),
    };
  });
  const slug = p.name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return { id: `custom-${slug}`, name: p.name.trim(), split: typeof p.split === "string" ? p.split : "Custom", schedule: p.schedule, days };
}

/** Weekly sets per primary muscle, for comparing programs. */
export function weeklySets(program: Program, primaryMuscle: (exerciseId: string) => string | undefined, sessionsPerWeek?: number) {
  const repeat = (sessionsPerWeek ?? program.days.length) / program.days.length;
  const totals: Record<string, number> = {};
  for (const day of program.days) {
    for (const e of day.exercises) {
      const muscle = primaryMuscle(exerciseUuid(e.exercise)) ?? "other";
      totals[muscle] = (totals[muscle] ?? 0) + e.sets * repeat;
    }
  }
  return totals;
}
