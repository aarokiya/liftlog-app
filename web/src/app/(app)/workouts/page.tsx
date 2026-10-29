import Link from "next/link";
import { getProfile, getWorkouts, toLiftSets } from "@/lib/data";
import { volumeLoad } from "@/lib/stats";
import { requireUser } from "@/lib/supabase/server";
import { validTimeZone } from "@/lib/time";
import { userTimeZone } from "@/lib/time/server";
import { createWorkout } from "./actions";

export default async function WorkoutsPage() {
  const { supabase, user } = await requireUser();
  const [profile, workouts] = await Promise.all([getProfile(supabase, user.id), getWorkouts(supabase)]);
  const unit = profile.default_unit;
  const tz = await userTimeZone();

  return (
    <div className="flex flex-col gap-4">
      <form action={createWorkout} className="card flex flex-wrap items-end gap-2">
        <label className="flex flex-col text-xs text-muted">
          Name
          <input name="name" placeholder="Push day" className="input" />
        </label>
        <label className="flex flex-col text-xs text-muted">
          Started
          <input name="started_at" type="datetime-local" required className="input" />
        </label>
        <input type="hidden" name="timezone" value={tz} />
        <button className="btn">Add past workout</button>
      </form>
      <ul className="divide-y divide-border rounded-lg border border-border">
        {workouts.map((w) => {
          const sets = toLiftSets([w]);
          return (
            <li key={w.id}>
              <Link href={`/workouts/${w.id}`} className="flex items-center gap-4 px-4 py-3 hover:bg-card">
                <span className="w-28 text-sm text-muted">{new Date(w.started_at).toLocaleDateString("en-US", { timeZone: validTimeZone(w.timezone) ?? tz })}</span>
                <span className="font-medium">{w.name}</span>
                <span className="ml-auto text-sm text-muted">
                  {w.workout_exercises.length} exercises · {Math.round(volumeLoad(sets, unit)).toLocaleString()} {unit}
                </span>
              </Link>
            </li>
          );
        })}
        {workouts.length === 0 && <li className="px-4 py-6 text-center text-sm text-muted">No workouts yet.</li>}
      </ul>
    </div>
  );
}
