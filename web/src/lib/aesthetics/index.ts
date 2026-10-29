// Body-composition and aesthetics priorities. Formulas are mirrored in LiftKit/Aesthetics.swift
// and checked against shared/fixtures/aesthetics-cases.json.

import { convert } from "../stats";
import type { Sex } from "../stats/advanced";

export * from "./energy";

/** U.S. Navy circumference method (men), all lengths in cm. */
export function navyBodyFatMale(heightCm: number, waistCm: number, neckCm: number): number | null {
  if (heightCm <= 0 || waistCm <= neckCm) return null;
  const pct = 495 / (1.0324 - 0.19077 * Math.log10(waistCm - neckCm) + 0.15456 * Math.log10(heightCm)) - 450;
  return Math.round(pct * 10) / 10;
}

/** Relative fat mass (men): needs only height and waist, used when there's no neck measurement. */
export function rfmMale(heightCm: number, waistCm: number): number | null {
  if (heightCm <= 0 || waistCm <= 0) return null;
  return Math.round((64 - (20 * heightCm) / waistCm) * 10) / 10;
}

/** U.S. Navy circumference method (women), all lengths in cm; needs hips as well as waist and neck. */
export function navyBodyFatFemale(heightCm: number, waistCm: number, hipsCm: number, neckCm: number): number | null {
  if (heightCm <= 0 || waistCm + hipsCm <= neckCm) return null;
  const pct = 495 / (1.29579 - 0.35004 * Math.log10(waistCm + hipsCm - neckCm) + 0.221 * Math.log10(heightCm)) - 450;
  return Math.round(pct * 10) / 10;
}

/** Relative fat mass (women). */
export function rfmFemale(heightCm: number, waistCm: number): number | null {
  if (heightCm <= 0 || waistCm <= 0) return null;
  return Math.round((76 - (20 * heightCm) / waistCm) * 10) / 10;
}

/** Tape estimate: the Navy formula when its measurements are there (neck, plus hips for women), else RFM. */
export function bodyFatEstimate(sex: Sex, heightCm: number, waistCm: number, neckCm?: number | null, hipsCm?: number | null): number | null {
  if (sex === "female") {
    return (neckCm && hipsCm ? navyBodyFatFemale(heightCm, waistCm, hipsCm, neckCm) : null) ?? rfmFemale(heightCm, waistCm);
  }
  return (neckCm ? navyBodyFatMale(heightCm, waistCm, neckCm) : null) ?? rfmMale(heightCm, waistCm);
}

/** Default goal body fat: 12% for men, 22% for women (women carry about 10 points more essential fat). */
export const defaultGoalPct = (sex: Sex) => (sex === "female" ? 22 : 12);

export function waistToHip(waistCm: number, hipsCm: number): number | null {
  return hipsCm > 0 ? Math.round((waistCm / hipsCm) * 1000) / 1000 : null;
}

/** Shoulder circumference at the golden ratio (1.618 × waist), the classic V-taper target. */
export function shoulderTarget(waistCm: number): number {
  return Math.round(waistCm * 1.618 * 10) / 10;
}

export function waistToHeight(waistCm: number, heightCm: number): number | null {
  return heightCm > 0 ? Math.round((waistCm / heightCm) * 1000) / 1000 : null;
}

export type WaistBand = "lean" | "healthy" | "elevated" | "high";

/** Waist-to-height bands; 0.5 is the usual cut-off for excess midsection fat. */
export function waistBand(ratio: number): WaistBand {
  if (ratio < 0.43) return "lean";
  if (ratio < 0.5) return "healthy";
  if (ratio < 0.6) return "elevated";
  return "high";
}

export type Phase = "cut" | "slow_cut" | "lean_bulk";

export const PHASE_LABELS: Record<Phase, string> = { cut: "Cut", slow_cut: "Slow cut", lean_bulk: "Lean bulk" };

/** Diet phase from body fat. Men: cut at 20%+, slow cut at 15–20%, lean bulk below 15%; women: 10 points higher. */
export function phase(bodyFatPct: number, sex: Sex = "male"): Phase {
  const shift = sex === "female" ? 10 : 0;
  return bodyFatPct >= 20 + shift ? "cut" : bodyFatPct >= 15 + shift ? "slow_cut" : "lean_bulk";
}

// Weekly body-weight change as a fraction of body weight (loss for cuts, gain for lean bulk).
const PHASE_RATES: Record<Phase, [number, number]> = { cut: [0.005, 0.01], slow_cut: [0.0025, 0.005], lean_bulk: [0.001, 0.0025] };

export interface BodyPlan {
  phase: Phase;
  leanMass: number;
  goalWeight: number;
  /** First target: ~7% of body weight off (never past the goal), then reassess by waist and photos. */
  checkpoint: number;
  /** Weight to lose to reach the checkpoint, not the goal. */
  toLose: number;
  weeklyLow: number;
  weeklyHigh: number;
  /** Weeks to the checkpoint at the middle of the weekly range. */
  weeks: number | null;
  proteinG: number;
}

const round1 = (v: number) => Math.round(v * 10) / 10;

/**
 * `startWeight` is the body weight when `bodyFatPct` was measured (defaults to `bodyWeight`). Lean mass, the goal and
 * the checkpoint come from it, so they hold still while the weight to lose counts down.
 * Goal weight keeps current lean mass at `goalPct` body fat; protein is 2.2 g per kg of goal weight. */
export function bodyPlan(
  bodyWeight: number,
  unit: "lb" | "kg",
  bodyFatPct: number,
  goalPctOrDefault?: number,
  startWeight?: number,
  sex: Sex = "male",
): BodyPlan {
  const goalPct = goalPctOrDefault ?? defaultGoalPct(sex);
  const p = phase(bodyFatPct, sex);
  const [lo, hi] = PHASE_RATES[p];
  const start = startWeight ?? bodyWeight;
  const lean = start * (1 - bodyFatPct / 100);
  const goal = lean / (1 - goalPct / 100);
  const checkpoint = Math.max(goal, start * 0.93);
  const toLose = Math.max(0, bodyWeight - checkpoint);
  const goalKg = unit === "kg" ? goal : goal / 2.20462;
  return {
    phase: p,
    leanMass: round1(lean),
    goalWeight: round1(goal),
    checkpoint: round1(checkpoint),
    toLose: round1(toLose),
    weeklyLow: round1(bodyWeight * lo),
    weeklyHigh: round1(bodyWeight * hi),
    weeks: p === "lean_bulk" || toLose === 0 ? null : Math.ceil(toLose / ((bodyWeight * (lo + hi)) / 2)),
    proteinG: Math.round(goalKg * 2.2),
  };
}

const PHASE_TIPS: Record<Phase, string> = {
  cut: "Fat loss comes first: lose 0.5–1% of body weight a week, keep lifting heavy and keep protein high so the weight that comes off is fat, not muscle. The waist will show progress before the shoulders do.",
  slow_cut: "Lose slowly (0.25–0.5% of body weight a week) so the V-taper keeps building while the midsection tightens.",
  lean_bulk: "You're lean enough that adding muscle is the priority: a small surplus (about 0.1–0.25% of body weight gained a week) is enough.",
};

export interface MuscleTarget {
  muscle: string;
  min: number;
  max: number;
  priority: boolean;
}

// Weekly hard sets. Priorities build the V-taper (shoulder width, lats, upper chest) and a visible midsection;
// legs stay at a solid maintenance dose so the lower body isn't left behind.
export const AESTHETIC_TARGETS: MuscleTarget[] = [
  { muscle: "side_delts", min: 12, max: 20, priority: true },
  { muscle: "back", min: 12, max: 20, priority: true },
  { muscle: "chest", min: 10, max: 16, priority: true },
  { muscle: "rear_delts", min: 8, max: 14, priority: true },
  { muscle: "core", min: 6, max: 12, priority: true },
  { muscle: "quads", min: 8, max: 14, priority: false },
  { muscle: "hamstrings", min: 6, max: 12, priority: false },
  { muscle: "glutes", min: 4, max: 10, priority: false },
  { muscle: "calves", min: 6, max: 12, priority: false },
  { muscle: "biceps", min: 6, max: 14, priority: false },
  { muscle: "triceps", min: 6, max: 14, priority: false },
];

export interface MuscleStatus extends MuscleTarget {
  actual: number;
  status: "under" | "on" | "over";
}

export function muscleStatus(weeklySets: Record<string, number>, targets = AESTHETIC_TARGETS): MuscleStatus[] {
  return targets.map((t) => {
    const actual = Math.round((weeklySets[t.muscle] ?? 0) * 10) / 10;
    return { ...t, actual, status: actual < t.min ? "under" : actual > t.max ? "over" : "on" };
  });
}

export function recommendations(band: WaistBand | null, statuses: MuscleStatus[], dietPhase: Phase | null = null): string[] {
  const tips: string[] = [];
  if (dietPhase) {
    tips.push(PHASE_TIPS[dietPhase]);
  } else if (band === "elevated" || band === "high") {
    tips.push(
      "Waist-to-height is above 0.5, so losing midsection fat will change your look more than extra volume: aim for about 0.5–1% of body weight lost per week and keep protein high.",
    );
  } else if (band === "lean") {
    tips.push("You're lean enough that adding muscle is the priority; a small calorie surplus will help.");
  }
  const under = statuses.filter((s) => s.status === "under");
  const priorityUnder = under.filter((s) => s.priority).map((s) => s.muscle.replace("_", " "));
  const otherUnder = under.filter((s) => !s.priority).map((s) => s.muscle.replace("_", " "));
  if (priorityUnder.length) tips.push(`Add sets for ${priorityUnder.join(", ")}: these drive the V-taper.`);
  if (otherUnder.length) tips.push(`Below maintenance for ${otherUnder.join(", ")}.`);
  return tips;
}

export interface MetricRow {
  measured_at: string;
  body_weight: number | string | null;
  unit: string;
  body_fat_pct: number | string | null;
}

/**
 * Body weight (in `unit`) when the latest body-fat % was logged: the last weigh-in up to a day after it, else the first
 * one after. The body plan's goal and checkpoint are fixed from this weight. Mirrors BodyMetric.planStartWeight on iOS.
 */
export function planStartWeight(rows: MetricRow[], unit: "lb" | "kg"): number | null {
  const time = (r: MetricRow) => new Date(r.measured_at).getTime();
  const bf = rows.filter((r) => r.body_fat_pct !== null).sort((a, b) => time(b) - time(a))[0];
  if (!bf) return null;
  const weights = rows.filter((r) => r.body_weight !== null).sort((a, b) => time(a) - time(b));
  const cutoff = time(bf) + 86_400_000;
  const row = weights.filter((r) => time(r) <= cutoff).at(-1) ?? weights.find((r) => time(r) > cutoff);
  return row ? convert(Number(row.body_weight), row.unit === "kg" ? "kg" : "lb", unit) : null;
}
