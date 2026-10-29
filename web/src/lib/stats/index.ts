// TypeScript port of ios/Packages/LiftKit. Both are tested against shared/fixtures/stats-cases.json — change them together.

export type WeightUnit = "lb" | "kg";
export type SetType = "warmup" | "working" | "drop" | "failure";
export type OneRepMaxFormula = "epley" | "brzycki" | "lombardi";

export const KG_PER_LB = 0.45359237;
export const MAX_E1RM_REPS = 12;
export const REP_RANGE = { min: 1, max: 20 } as const;
export const SECONDARY_MUSCLE_WEIGHT = 0.5;

export interface LiftSet {
  exerciseId: string;
  sessionId: string;
  weight: number;
  unit: WeightUnit;
  reps: number;
  type: SetType;
}

export interface ExerciseMuscles {
  primary: string;
  secondary: string[];
}

export function convert(value: number, from: WeightUnit, to: WeightUnit): number {
  if (from === to) return value;
  return from === "lb" ? value * KG_PER_LB : value / KG_PER_LB;
}

export const countsTowardStats = (type: SetType) => type !== "warmup";

export function estimateOneRepMax(weight: number, reps: number, formula: OneRepMaxFormula = "epley"): number | null {
  if (!(weight > 0) || reps < 1 || reps > MAX_E1RM_REPS) return null;
  if (reps === 1) return weight;
  switch (formula) {
    case "epley":
      return weight * (1 + reps / 30);
    case "brzycki":
      return (weight * 36) / (37 - reps);
    case "lombardi":
      return weight * Math.pow(reps, 0.1);
  }
}

export function bestE1RMPerSession(
  sets: LiftSet[],
  unit: WeightUnit,
  formula: OneRepMaxFormula = "epley",
): { sessionId: string; value: number }[] {
  const best = new Map<string, number>();
  for (const s of sets) {
    if (!countsTowardStats(s.type)) continue;
    const e = estimateOneRepMax(convert(s.weight, s.unit, unit), s.reps, formula);
    if (e === null) continue;
    best.set(s.sessionId, Math.max(best.get(s.sessionId) ?? 0, e));
  }
  return [...best].map(([sessionId, value]) => ({ sessionId, value }));
}

export function volumeLoad(sets: LiftSet[], unit: WeightUnit): number {
  return sets
    .filter((s) => countsTowardStats(s.type))
    .reduce((sum, s) => sum + convert(s.weight, s.unit, unit) * s.reps, 0);
}

export function repMaxes(sets: LiftSet[], unit: WeightUnit): Record<number, number> {
  const out: Record<number, number> = {};
  for (const s of sets) {
    if (!countsTowardStats(s.type) || s.reps < REP_RANGE.min || s.reps > REP_RANGE.max) continue;
    out[s.reps] = Math.max(out[s.reps] ?? 0, convert(s.weight, s.unit, unit));
  }
  return out;
}

export function muscleSets(sets: LiftSet[], exercises: Record<string, ExerciseMuscles>): Record<string, number> {
  const out: Record<string, number> = {};
  for (const s of sets) {
    if (!countsTowardStats(s.type)) continue;
    const m = exercises[s.exerciseId];
    if (!m) continue;
    out[m.primary] = (out[m.primary] ?? 0) + 1;
    for (const sec of m.secondary) out[sec] = (out[sec] ?? 0) + SECONDARY_MUSCLE_WEIGHT;
  }
  return out;
}

export function plates(target: number, bar: number, available: number[]): { perSide: number[]; remainder: number } {
  let side = (target - bar) / 2;
  if (side < 0) return { perSide: [], remainder: target - bar };
  const perSide: number[] = [];
  for (const p of [...available].filter((p) => p > 0).sort((a, b) => b - a)) {
    while (side >= p - 1e-9) {
      perSide.push(p);
      side -= p;
    }
  }
  return { perSide, remainder: Math.round(side * 2 * 1e6) / 1e6 };
}

export function linearRegression(points: [number, number][]): { slope: number; intercept: number } | null {
  if (points.length < 2) return null;
  const n = points.length;
  const mx = points.reduce((a, [x]) => a + x, 0) / n;
  const my = points.reduce((a, [, y]) => a + y, 0) / n;
  const sxx = points.reduce((a, [x]) => a + (x - mx) ** 2, 0);
  if (sxx === 0) return null;
  const slope = points.reduce((a, [x, y]) => a + (x - mx) * (y - my), 0) / sxx;
  return { slope, intercept: my - slope * mx };
}

/** Days since 1970-01-01 for a `YYYY-MM-DD` local date (Howard Hinnant's days_from_civil). */
export function dayNumber(iso: string): number {
  const [year, month, day] = iso.split("-").map(Number);
  const y = month <= 2 ? year - 1 : year;
  const era = Math.floor(y / 400);
  const yoe = y - era * 400;
  const mp = (month + 9) % 12;
  const doy = Math.floor((153 * mp + 2) / 5) + day - 1;
  const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
  return era * 146097 + doe - 719468;
}

/** Monday-based week index. 1970-01-01 was a Thursday. */
export const weekNumber = (iso: string) => Math.floor((dayNumber(iso) + 3) / 7);

/** Consecutive Monday-based weeks with at least `target` workouts. The in-progress week never breaks the streak. */
export function weeklyStreak(dates: string[], target: number, asOf: string): { current: number; longest: number } {
  const perWeek = new Map<number, number>();
  for (const d of dates) perWeek.set(weekNumber(d), (perWeek.get(weekNumber(d)) ?? 0) + 1);
  const qualifying = new Set([...perWeek].filter(([, n]) => n >= target).map(([w]) => w));

  let longest = 0;
  let run = 0;
  let prev: number | null = null;
  for (const w of [...qualifying].sort((a, b) => a - b)) {
    run = prev !== null && w === prev + 1 ? run + 1 : 1;
    longest = Math.max(longest, run);
    prev = w;
  }

  let w = weekNumber(asOf);
  if (!qualifying.has(w)) w -= 1;
  let current = 0;
  while (qualifying.has(w)) {
    current += 1;
    w -= 1;
  }
  return { current, longest };
}

/** Local `YYYY-MM-DD` for a timestamp in the given IANA timezone. */
export function localDate(timestamp: string | Date, timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(
    new Date(timestamp),
  );
}
