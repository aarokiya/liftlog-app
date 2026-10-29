// Advanced stats. Mirrored in ios/Packages/LiftKit/Sources/LiftKit/Advanced.swift and checked against
// shared/fixtures/advanced-cases.json.
import { linearRegression } from ".";

const poly = (x: number, coeffs: number[]) => coeffs.reduce((sum, c, i) => sum + c * x ** i, 0);

const WILKS = {
  male: [-216.0475144, 16.2606339, -0.002388645, -0.00113732, 7.01863e-6, -1.291e-8],
  female: [594.31747775582, -27.23842536447, 0.82112226871, -0.00930733913, 4.731582e-5, -9.054e-8],
};
const DOTS = {
  male: [-307.75076, 24.0900756, -0.1918759221, 0.0007391293, -0.000001093],
  female: [-57.96288, 13.6175032, -0.1126655495, 0.0005158568, -0.0000010706],
};

export type Sex = "male" | "female";

/** Original Wilks score for a total and body weight in kg. */
export function wilks(totalKg: number, bodyKg: number, sex: Sex = "male"): number | null {
  if (totalKg <= 0 || bodyKg <= 0) return null;
  return Math.round(((totalKg * 500) / poly(bodyKg, WILKS[sex])) * 100) / 100;
}

/** DOTS score for a total and body weight in kg. */
export function dots(totalKg: number, bodyKg: number, sex: Sex = "male"): number | null {
  if (totalKg <= 0 || bodyKg <= 0) return null;
  return Math.round(((totalKg * 500) / poly(bodyKg, DOTS[sex])) * 100) / 100;
}

/** Weekly e1RM change as a fraction; under 0.5%/week across at least 4 sessions counts as a plateau. */
export function plateau(points: { day: number; value: number }[], minSessions = 4): { weeklyChange: number; plateaued: boolean } | null {
  if (points.length < minSessions) return null;
  const line = linearRegression(points.map((p) => [p.day, p.value]));
  const mean = points.reduce((s, p) => s + p.value, 0) / points.length;
  if (!line || mean <= 0) return null;
  const weeklyChange = Math.round(((line.slope * 7) / mean) * 10000) / 10000;
  return { weeklyChange, plateaued: weeklyChange < 0.005 };
}

const sum = (m: Record<string, number>, keys: string[]) => keys.reduce((s, k) => s + (m[k] ?? 0), 0);

/** Push:pull and quad:hamstring set ratios from muscleSets output; null when the denominator is zero. */
export function balance(muscleSets: Record<string, number>) {
  const ratio = (a: number, b: number) => (b > 0 ? Math.round((a / b) * 100) / 100 : null);
  return {
    pushPull: ratio(sum(muscleSets, ["chest", "front_delts", "triceps"]), sum(muscleSets, ["back", "rear_delts", "biceps"])),
    quadHam: ratio(sum(muscleSets, ["quads"]), sum(muscleSets, ["hamstrings"])),
  };
}

/** Acute:chronic workload ratio: last 7 days' load vs. the weekly average of the last 28. */
export function acwr(loads: { day: number; load: number }[], today: number): number | null {
  // Needs four weeks of history; before that both windows hold the same sessions and the ratio means nothing.
  if (!loads.length || today - Math.min(...loads.map((l) => l.day)) < 27) return null;
  const within = (days: number) => loads.filter((l) => l.day > today - days && l.day <= today).reduce((s, l) => s + l.load, 0);
  const chronic = within(28) / 4;
  return chronic > 0 ? Math.round((within(7) / chronic) * 100) / 100 : null;
}

/** Days since each muscle last got a primary set. */
export function muscleRecency(lastDay: Record<string, number>, today: number): Record<string, number> {
  return Object.fromEntries(Object.entries(lastDay).map(([m, d]) => [m, today - d]));
}

/** Volume per minute of session time. */
export function density(volume: number, minutes: number): number | null {
  return minutes > 0 ? Math.round((volume / minutes) * 10) / 10 : null;
}

export interface Growth {
  start: number;
  recent: number;
  best: number;
  change: number;
  changePct: number | null;
  weeklyRate: number | null;
  prs: number;
  lastPrDay: number;
  sessions: number;
  spanDays: number;
}

const round1 = (v: number) => Math.round(v * 10) / 10;

/**
 * Growth of a per-session series (e.g. best e1RM): first session vs. the best of the last 3 sessions,
 * regression slope per week, and how many sessions set a new all-time best.
 */
export function growth(points: { day: number; value: number }[]): Growth | null {
  if (points.length === 0) return null;
  const sorted = [...points].sort((a, b) => a.day - b.day);
  const start = sorted[0].value;
  const recent = Math.max(...sorted.slice(-3).map((p) => p.value));
  let best = start;
  let prs = 0;
  let lastPrDay = sorted[0].day;
  for (const p of sorted.slice(1)) {
    if (p.value > best) {
      best = p.value;
      prs++;
      lastPrDay = p.day;
    }
  }
  const line = linearRegression(sorted.map((p) => [p.day, p.value]));
  return {
    start,
    recent,
    best,
    change: round1(recent - start),
    changePct: start > 0 ? round1(((recent - start) / start) * 100) : null,
    weeklyRate: line ? round1(line.slope * 7) : null,
    prs,
    lastPrDay,
    sessions: sorted.length,
    spanDays: sorted[sorted.length - 1].day - sorted[0].day,
  };
}
