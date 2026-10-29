import Link from "next/link";
import { getExercises, getProfile, getWorkouts, sessionSeries, toLiftSets, type DatedSet } from "@/lib/data";
import { dayNumber, localDate } from "@/lib/stats";
import { requireUser } from "@/lib/supabase/server";
import { userTimeZone } from "@/lib/time/server";
import { StatsTable, type GrowthRow } from "./stats-table";

export default async function StatsPage() {
  const { supabase, user } = await requireUser();
  const [profile, workouts, exercises] = await Promise.all([getProfile(supabase, user.id), getWorkouts(supabase), getExercises(supabase)]);
  const unit = profile.default_unit;
  const byExercise = new Map<string, DatedSet[]>();
  for (const s of toLiftSets(workouts)) byExercise.set(s.exerciseId, [...(byExercise.get(s.exerciseId) ?? []), s]);

  const rows: GrowthRow[] = exercises
    .filter((e) => byExercise.has(e.id))
    .map((e) => ({
      id: e.id,
      name: e.name,
      muscle: e.primary_muscle,
      points: sessionSeries(byExercise.get(e.id)!, unit, profile.e1rm_formula).map((p) => ({ day: p.day, e1rm: p.e1rm, top: p.top, volume: p.volume })),
    }))
    .filter((r) => r.points.length > 0);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Exercise growth</h1>
        <p className="text-sm text-muted">
          How each lift has moved: first session vs. your best of the last 3, weekly trend and new records. Estimated 1RM uses {profile.e1rm_formula}.
        </p>
      </div>
      {rows.length === 0 ? (
        <div className="card text-center text-sm text-muted">
          No lifts logged yet. <Link href="/import" className="text-accent">Import your history</Link> or log a workout on your iPhone.
        </div>
      ) : (
        <StatsTable rows={rows} unit={unit} today={dayNumber(localDate(new Date(), await userTimeZone()))} />
      )}
    </div>
  );
}
