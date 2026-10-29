import type { SupabaseClient } from "@supabase/supabase-js";
import {
  bestE1RMPerSession,
  convert,
  countsTowardStats,
  dayNumber,
  localDate,
  volumeLoad,
  type LiftSet,
  type OneRepMaxFormula,
  type WeightUnit,
} from "./stats";
import type { Exercise, Profile, WorkoutRow } from "./types";

const WORKOUT_SELECT = `id, name, notes, started_at, ended_at, timezone,
  workout_exercises(id, exercise_id, position, notes, deleted_at,
    exercises(id, name, kind, primary_muscle, secondary_muscles),
    sets(id, position, set_type, weight, weight_unit, reps, duration_seconds, rpe, notes, deleted_at))`;

export async function getProfile(supabase: SupabaseClient, userId: string): Promise<Profile> {
  const { data } = await supabase.from("profiles").select("*").eq("id", userId).single();
  return (
    data ?? {
      id: userId,
      display_name: null,
      default_unit: "lb",
      e1rm_formula: "epley",
      weekly_workout_target: 3,
      bar_weight: 45,
      plate_inventory: [45, 35, 25, 10, 5, 2.5],
    }
  );
}

/** Live (non-deleted) children, sorted by position. */
function clean(workout: WorkoutRow): WorkoutRow {
  return {
    ...workout,
    workout_exercises: workout.workout_exercises
      .filter((we) => !we.deleted_at)
      .sort((a, b) => a.position - b.position)
      .map((we) => ({ ...we, sets: we.sets.filter((s) => !s.deleted_at).sort((a, b) => a.position - b.position) })),
  };
}

export async function getWorkouts(supabase: SupabaseClient, opts: { since?: string; limit?: number } = {}) {
  let q = supabase.from("workouts").select(WORKOUT_SELECT).is("deleted_at", null).order("started_at", { ascending: false });
  if (opts.since) q = q.gte("started_at", opts.since);
  if (opts.limit) q = q.limit(opts.limit);
  const { data, error } = await q;
  if (error) throw error;
  return (data as unknown as WorkoutRow[]).map(clean);
}

export async function getWorkout(supabase: SupabaseClient, id: string) {
  const { data, error } = await supabase.from("workouts").select(WORKOUT_SELECT).eq("id", id).single();
  if (error) return null;
  return clean(data as unknown as WorkoutRow);
}

export async function getExercises(supabase: SupabaseClient): Promise<Exercise[]> {
  const { data, error } = await supabase
    .from("exercises")
    .select("id, user_id, name, kind, equipment, primary_muscle, secondary_muscles")
    .is("deleted_at", null)
    .order("name");
  if (error) throw error;
  return data;
}

export interface DatedSet extends LiftSet {
  date: string;
  startedAt: string;
}

/** Flattens workouts into stats-engine sets; sessionId is the workout id. */
/**
 * Logged sets as stats input. Sets without a weight are skipped unless `bodyweight` is set, which keeps them (as 0)
 * for counting sets per muscle; volume, e1RM and PRs always use weighted sets only.
 */
export function toLiftSets(workouts: WorkoutRow[], { bodyweight = false } = {}): DatedSet[] {
  return workouts.flatMap((w) =>
    w.workout_exercises.flatMap((we) =>
      we.sets
        .filter((s) => s.reps !== null && (s.weight !== null || (bodyweight && s.reps > 0)))
        .map((s) => ({
          exerciseId: we.exercise_id,
          sessionId: w.id,
          weight: Number(s.weight ?? 0),
          unit: s.weight_unit,
          reps: s.reps!,
          type: s.set_type,
          date: localDate(w.started_at, w.timezone),
          startedAt: w.started_at,
        })),
    ),
  );
}

export function formatWeight(value: number, unit: string) {
  return `${Math.round(value * 10) / 10} ${unit}`;
}

export interface SessionPoint {
  sessionId: string;
  date: string;
  day: number;
  e1rm: number | null;
  top: number;
  volume: number;
  reps: number;
  sets: number;
}

/** One point per workout for a single exercise's sets, oldest first. Warmups are ignored. */
export function sessionSeries(sets: DatedSet[], unit: WeightUnit, formula: OneRepMaxFormula): SessionPoint[] {
  const bySession = new Map<string, DatedSet[]>();
  for (const s of sets) {
    if (!countsTowardStats(s.type)) continue;
    const list = bySession.get(s.sessionId) ?? [];
    list.push(s);
    bySession.set(s.sessionId, list);
  }
  const e1rm = new Map(bestE1RMPerSession(sets, unit, formula).map((p) => [p.sessionId, p.value]));
  return [...bySession]
    .map(([sessionId, list]) => ({
      sessionId,
      date: list[0].date,
      day: dayNumber(list[0].date),
      e1rm: e1rm.get(sessionId) ?? null,
      top: Math.max(...list.map((s) => convert(s.weight, s.unit, unit))),
      volume: volumeLoad(list, unit),
      reps: list.reduce((n, s) => n + s.reps, 0),
      sets: list.length,
    }))
    .sort((a, b) => a.date.localeCompare(b.date) || a.sessionId.localeCompare(b.sessionId));
}
