// Daily calorie and macro targets for the body plan. Mirrored in LiftKit (Energy) and checked against
// shared/fixtures/energy-cases.json: keep the same operation order so both round to the same numbers.

import type { Sex } from "../stats/advanced";
import type { BodyPlan } from ".";

/** Energy in a kilogram of body-weight change. */
export const KCAL_PER_KG = 7700;
const ACTIVITY = 1.55;
const LB = 2.20462;

// Every value rounded here is positive, where Math.round and Swift's .rounded() agree.
const rnd = (x: number) => Math.round(x);
const round10 = (x: number) => rnd(x / 10) * 10;
const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0);

export interface Targets {
  kcal: number;
  protein: number;
  carbs: number;
  fat: number;
}

export interface BaseTargets {
  targets: Targets;
  kcalFloor: number;
  fatFloor: number;
}

/** Katch-McArdle basal metabolic rate (kcal/day). */
export function bmr(leanKg: number): number {
  return 370 + 21.6 * leanKg;
}

/** Maintenance before any logs: BMR × 1.55 for someone lifting most days. */
export function formulaMaintenance(leanKg: number): number {
  return rnd(bmr(leanKg) * ACTIVITY);
}

/**
 * Maintenance learned from the 28 days before `today`: mean intake on complete days (≥ 40% of `formula`) minus the
 * weight trend × 7700. Needs 10+ complete days and 4+ weigh-ins spanning 14+ days, else returns `formula`. The observed
 * value is clamped to 75–125% of the formula and blended in by how many days were logged (fully at 28).
 * `intake` is kcal by day number; `weights` must be sorted by day.
 */
export function learnedMaintenance(formula: number, intake: Record<number, number>, weights: { day: number; kg: number }[], today: number): number {
  const complete = Object.keys(intake)
    .map(Number)
    .sort((a, b) => a - b)
    .filter((d) => today - 28 <= d && d <= today - 1 && intake[d] >= 0.4 * formula)
    .map((d) => intake[d]);
  const pts = weights.filter((w) => today - 28 <= w.day && w.day <= today);
  if (complete.length < 10 || pts.length < 4) return formula;
  const days = pts.map((p) => p.day);
  if (Math.max(...days) - Math.min(...days) < 14) return formula;
  const n = pts.length;
  const mx = sum(days) / n;
  const my = sum(pts.map((p) => p.kg)) / n;
  const sxx = sum(days.map((d) => (d - mx) * (d - mx)));
  const slope = sum(pts.map((p) => (p.day - mx) * (p.kg - my))) / sxx;
  let observed = sum(complete) / complete.length - slope * KCAL_PER_KG;
  observed = Math.min(Math.max(observed, 0.75 * formula), 1.25 * formula);
  const w = Math.min(1, (complete.length - 7) / 21);
  return rnd(formula + w * (observed - formula));
}

/**
 * The plan's daily targets before carryover: maintenance minus (cuts) or plus (lean bulk) the middle of the weekly
 * rate, never below BMR or 1500 kcal (1200 for women). Fat is at least 0.5 g per kg and 25% of calories; carbs fill
 * the rest. `bodyWeight` and the plan are in `unit`.
 */
export function baseTargets(
  plan: Pick<BodyPlan, "phase" | "leanMass" | "weeklyLow" | "weeklyHigh" | "proteinG">,
  bodyWeight: number,
  unit: "lb" | "kg",
  maintenance: number,
  sex: Sex,
): BaseTargets {
  const toKg = (v: number) => (unit === "kg" ? v : v / LB);
  const leanKg = toKg(plan.leanMass);
  const kcalFloor = Math.max(rnd(bmr(leanKg)), sex === "female" ? 1200 : 1500);
  const midKg = toKg((plan.weeklyLow + plan.weeklyHigh) / 2);
  const delta = ((midKg * KCAL_PER_KG) / 7) * (plan.phase === "lean_bulk" ? 1 : -1);
  const kcal = Math.max(kcalFloor, round10(maintenance + delta));
  const protein = plan.proteinG;
  const fatFloor = rnd(0.5 * toKg(bodyWeight));
  const fat = Math.max(fatFloor, rnd((0.25 * kcal) / 9));
  const carbs = rnd(Math.max(0, (kcal - 4 * protein - 9 * fat) / 4));
  return { targets: { kcal, protein, carbs, fat }, kcalFloor, fatFloor };
}

/**
 * Targets for each day `from`…`through`. A complete day's miss (intake ≥ 50% of that day's target) is repaid evenly
 * over the next 3 days, capped at ±15% of base kcal and ±25% of base fat and never below the floors; protein stays
 * fixed and carbs fill the rest. `intake` is kcal and fat grams by day number.
 */
export function dailyTargets(base: BaseTargets, intake: Record<number, { kcal: number; fat: number }>, from: number, through: number): Record<number, Targets> {
  const t = base.targets;
  const out: Record<number, Targets> = {};
  const devK = new Map<number, number>();
  const devF = new Map<number, number>();
  const owed = (dev: Map<number, number>, d: number) => -((dev.get(d - 1) ?? 0) + (dev.get(d - 2) ?? 0) + (dev.get(d - 3) ?? 0)) / 3;
  for (let d = from; d <= through; d++) {
    const adjK = Math.min(Math.max(owed(devK, d), -0.15 * t.kcal), 0.15 * t.kcal);
    const adjF = Math.min(Math.max(owed(devF, d), -0.25 * t.fat), 0.25 * t.fat);
    const kcal = Math.max(base.kcalFloor, round10(t.kcal + adjK));
    const fat = Math.max(base.fatFloor, rnd(t.fat + adjF));
    const carbs = rnd(Math.max(0, (kcal - 4 * t.protein - 9 * fat) / 4));
    out[d] = { kcal, protein: t.protein, carbs, fat };
    const i = intake[d];
    if (i && i.kcal >= 0.5 * kcal) {
      devK.set(d, i.kcal - kcal);
      devF.set(d, i.fat - fat);
    }
  }
  return out;
}
