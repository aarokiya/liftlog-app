import Link from "next/link";
import { notFound } from "next/navigation";
import { formatWeight, getProfile, getWorkouts, sessionSeries, toLiftSets } from "@/lib/data";
import { dayNumber, localDate, repMaxes, volumeLoad } from "@/lib/stats";
import { growth, plateau } from "@/lib/stats/advanced";
import { requireUser } from "@/lib/supabase/server";
import { userTimeZone } from "@/lib/time/server";
import { MUSCLE_LABELS } from "@/lib/types";
import { ExerciseCharts } from "./exercise-charts";

function Stat({ label, value, sub, tone }: { label: string; value: string; sub?: React.ReactNode; tone?: string }) {
  return (
    <div className="card">
      <div className="label">{label}</div>
      <div className={`mt-1 text-2xl font-semibold ${tone ?? ""}`}>{value}</div>
      {sub && <div className="text-xs text-muted">{sub}</div>}
    </div>
  );
}

export default async function ExercisePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase, user } = await requireUser();
  const [{ data: exercise }, profile, workouts] = await Promise.all([
    supabase.from("exercises").select("id, name, primary_muscle, equipment").eq("id", id).single(),
    getProfile(supabase, user.id),
    getWorkouts(supabase),
  ]);
  if (!exercise) notFound();
  const unit = profile.default_unit;
  const sets = toLiftSets(workouts).filter((s) => s.exerciseId === id);
  const sessions = sessionSeries(sets, unit, profile.e1rm_formula);
  const e1rmPoints = sessions.filter((s) => s.e1rm !== null).map((s) => ({ day: s.day, value: s.e1rm! }));
  const g = growth(e1rmPoints);
  const stall = plateau(e1rmPoints.slice(-6));
  const prs = Object.entries(repMaxes(sets, unit)).sort((a, b) => Number(a[0]) - Number(b[0]));
  const today = dayNumber(localDate(new Date(), await userTimeZone()));

  let running = -Infinity;
  const timeline = sessions
    .filter((s) => s.e1rm !== null)
    .flatMap((s) => {
      if (s.e1rm! <= running) return [];
      const prev = running;
      running = s.e1rm!;
      return [{ date: s.date, value: s.e1rm!, delta: Number.isFinite(prev) ? s.e1rm! - prev : null }];
    })
    .reverse()
    .slice(0, 8);
  const tone = (v: number | null | undefined) => (!v ? "" : v > 0 ? "text-good" : "text-bad");

  return (
    <div className="flex flex-col gap-6">
      <div>
        <Link href="/stats" className="text-sm text-muted hover:text-accent">
          ← All exercise growth
        </Link>
        <h1 className="mt-1 text-2xl font-semibold tracking-tight">{exercise.name}</h1>
        <p className="text-sm text-muted">
          {MUSCLE_LABELS[exercise.primary_muscle] ?? exercise.primary_muscle}
          {exercise.equipment ? ` · ${exercise.equipment}` : ""}
        </p>
      </div>
      {sessions.length === 0 ? (
        <p className="card text-sm text-muted">No sets logged for this exercise yet.</p>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            <Stat label="Best e1RM" value={g ? formatWeight(g.best, unit) : "—"} sub={g ? `${g.prs} PR${g.prs === 1 ? "" : "s"} since first session` : undefined} />
            <Stat
              label="Growth"
              value={g && g.sessions > 1 ? `${g.change > 0 ? "+" : ""}${g.change} ${unit}` : "—"}
              sub={g && g.changePct !== null && g.sessions > 1 ? `${g.changePct > 0 ? "+" : ""}${g.changePct}% over ${g.spanDays} days` : "needs 2+ sessions"}
              tone={tone(g?.change)}
            />
            <Stat
              label="Trend"
              value={g?.weeklyRate != null ? `${g.weeklyRate > 0 ? "+" : ""}${g.weeklyRate} ${unit}/wk` : "—"}
              tone={tone(g?.weeklyRate)}
              sub={
                stall && (
                  <span className={stall.plateaued ? "text-amber-500" : ""}>
                    {stall.plateaued ? "Plateau · " : "Last 6 · "}
                    {(stall.weeklyChange * 100).toFixed(1)}%/wk
                  </span>
                )
              }
            />
            <Stat label="Sessions" value={String(sessions.length)} sub={`${Math.round(volumeLoad(sets, unit)).toLocaleString()} ${unit} total volume`} />
          </div>

          <ExerciseCharts sessions={sessions.map(({ date, day, e1rm, top, volume, reps }) => ({ date, day, e1rm, top, volume, reps }))} unit={unit} today={today} />

          <div className="grid gap-6 md:grid-cols-2">
            <section className="card">
              <h2 className="card-title">PR timeline</h2>
              {timeline.length === 0 ? (
                <p className="text-sm text-muted">No estimated-max sessions yet.</p>
              ) : (
                <ol className="flex flex-col gap-2 text-sm">
                  {timeline.map((t) => (
                    <li key={t.date + t.value} className="flex items-center gap-3">
                      <span className="h-2 w-2 rounded-full bg-accent" />
                      <span className="w-24 text-muted">{t.date}</span>
                      <span className="font-medium">{formatWeight(t.value, unit)}</span>
                      <span className="ml-auto text-xs text-good">{t.delta !== null ? `+${Math.round(t.delta * 10) / 10}` : "first"}</span>
                    </li>
                  ))}
                </ol>
              )}
            </section>
            <section className="card">
              <h2 className="card-title">Rep-range records</h2>
              <div className="grid grid-cols-3 gap-2 sm:grid-cols-4">
                {prs.map(([reps, w]) => (
                  <div key={reps} className="rounded-xl border border-border px-3 py-2">
                    <div className="text-xs text-muted">{reps} rep{reps === "1" ? "" : "s"}</div>
                    <div className="font-semibold">{formatWeight(w, unit)}</div>
                  </div>
                ))}
              </div>
            </section>
          </div>

          <section className="card">
            <h2 className="card-title">Recent sessions</h2>
            <div className="-mx-4 overflow-x-auto md:-mx-5">
              <table className="w-full min-w-[480px] text-sm">
                <thead>
                  <tr className="label text-left">
                    <th className="px-4 py-2 md:px-5">Date</th>
                    <th className="py-2 text-right">Top set</th>
                    <th className="py-2 text-right">e1RM</th>
                    <th className="py-2 text-right">Sets / reps</th>
                    <th className="px-4 py-2 text-right md:px-5">Volume</th>
                  </tr>
                </thead>
                <tbody>
                  {[...sessions].reverse().slice(0, 10).map((s) => (
                    <tr key={s.sessionId} className="border-t border-border">
                      <td className="px-4 py-2 md:px-5">
                        <Link href={`/workouts/${s.sessionId}`} className="hover:text-accent">
                          {s.date}
                        </Link>
                      </td>
                      <td className="py-2 text-right">{formatWeight(s.top, unit)}</td>
                      <td className="py-2 text-right">{s.e1rm !== null ? formatWeight(s.e1rm, unit) : "—"}</td>
                      <td className="py-2 text-right text-muted">
                        {s.sets} / {s.reps}
                      </td>
                      <td className="px-4 py-2 text-right md:px-5">{Math.round(s.volume).toLocaleString()}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}
    </div>
  );
}
