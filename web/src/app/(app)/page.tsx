import Link from "next/link";
import { BarsChart } from "@/components/charts";
import { Sparkline } from "@/components/sparkline";
import { getExercises, getProfile, getWorkouts, sessionSeries, toLiftSets, type DatedSet } from "@/lib/data";
import { bestE1RMPerSession, convert, dayNumber, localDate, muscleSets, volumeLoad, weekNumber, weeklyStreak } from "@/lib/stats";
import { acwr, balance, density, dots, growth, muscleRecency, wilks } from "@/lib/stats/advanced";
import { PHASE_LABELS, bodyFatEstimate, bodyPlan, defaultGoalPct, planStartWeight, muscleStatus, recommendations, shoulderTarget, waistBand, waistToHeight, waistToHip } from "@/lib/aesthetics";
import { requireUser } from "@/lib/supabase/server";
import { userTimeZone } from "@/lib/time/server";
import { MUSCLE_LABELS } from "@/lib/types";

const WEEKS = 12;

function Metric({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="card">
      <div className="label">{label}</div>
      <div className="mt-1 text-2xl font-semibold">{value}</div>
      {sub && <div className="text-xs text-muted">{sub}</div>}
    </div>
  );
}

// Built-in Squat, Bench Press and Deadlift (Barbell) from supabase/seed.sql.
const BIG_THREE = ["00000000-0000-4000-8000-000000000003", "00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000004"];

export default async function Dashboard() {
  const { supabase, user } = await requireUser();
  const [profile, workouts, exercises, { data: metrics }] = await Promise.all([
    getProfile(supabase, user.id),
    getWorkouts(supabase),
    getExercises(supabase),
    supabase
      .from("body_metrics")
      .select("measured_at, body_weight, unit, body_fat_pct, waist_cm, neck_cm, hips_cm")
      .is("deleted_at", null)
      .order("measured_at", { ascending: false })
      .limit(200),
  ]);
  const unit = profile.default_unit;
  const tz = await userTimeZone();
  const today = localDate(new Date(), tz);
  const thisWeek = weekNumber(today);
  const sets = toLiftSets(workouts);
  // Bodyweight sets (e.g. leg raises) count toward sets per muscle and recency, not volume or e1RM.
  const muscleWork = toLiftSets(workouts, { bodyweight: true });

  // Rest-day cardio doesn't count toward the weekly target.
  const lifting = new Set(muscleWork.map((s) => s.sessionId));
  const streak = weeklyStreak(
    workouts.filter((w) => lifting.has(w.id)).map((w) => localDate(w.started_at, w.timezone)),
    profile.weekly_workout_target,
    today,
  );
  const weekSets = muscleWork.filter((s) => weekNumber(s.date) === thisWeek);
  const weeklyVolume = Array.from({ length: WEEKS }, (_, i) => {
    const w = thisWeek - (WEEKS - 1 - i);
    return { label: i === WEEKS - 1 ? "This wk" : `-${WEEKS - 1 - i}w`, value: volumeLoad(sets.filter((s) => weekNumber(s.date) === w), unit) };
  });
  const muscles = Object.fromEntries(
    exercises.map((e) => [e.id, { primary: e.primary_muscle, secondary: e.secondary_muscles }]),
  );
  const muscleCounts = Object.entries(muscleSets(weekSets, muscles)).sort((a, b) => b[1] - a[1]);

  const latest = <K extends "body_weight" | "waist_cm" | "neck_cm" | "hips_cm" | "body_fat_pct">(key: K) => (metrics ?? []).find((m) => m[key] !== null);
  const weightRow = latest("body_weight");
  const waist = latest("waist_cm")?.waist_cm as number | undefined;
  const neck = latest("neck_cm")?.neck_cm as number | undefined;
  const hips = latest("hips_cm")?.hips_cm as number | undefined;
  const height = profile.height_cm ?? undefined;
  const whtr = waist && height ? waistToHeight(waist, height) : null;
  const sex = profile.sex ?? null;
  const measuredBf = (latest("body_fat_pct")?.body_fat_pct as number | undefined) ?? null;
  // The tape formulas differ by sex, so they wait until it's set; the Navy one needs hips for women.
  const tapeBf = sex && waist && height ? bodyFatEstimate(sex, height, waist, neck, hips) : null;
  const usesNavy = !!neck && (sex === "male" || !!hips);
  const bodyFat = measuredBf ?? tapeBf;
  const bfSource = measuredBf !== null ? " (logged)" : tapeBf !== null ? (usesNavy ? " (Navy est.)" : " (RFM est.)") : "";
  const bodyWeight = weightRow ? convert(Number(weightRow.body_weight), weightRow.unit === "kg" ? "kg" : "lb", unit) : null;
  // A logged body-fat % fixes the plan from the weight at that time; tape estimates follow the current weight.
  const startWeight = measuredBf !== null ? planStartWeight(metrics ?? [], unit) ?? undefined : undefined;
  const plan = sex && bodyFat !== null && bodyWeight ? bodyPlan(bodyWeight, unit, bodyFat, undefined, startWeight, sex) : null;
  const goalPct = defaultGoalPct(sex ?? "male");
  const whr = waist && hips ? waistToHip(waist, hips) : null;
  const toLen = (cm: number) => (unit === "lb" ? `${Math.round((cm / 2.54) * 10) / 10} in` : `${cm} cm`);
  // Average weekly sets over the last 4 weeks, so one light week doesn't skew priorities.
  const recent = muscleWork.filter((s) => weekNumber(s.date) > thisWeek - 4 && weekNumber(s.date) <= thisWeek);
  const avgSets = Object.fromEntries(Object.entries(muscleSets(recent, muscles)).map(([m, n]) => [m, n / 4]));
  const statuses = muscleStatus(avgSets);
  const tips = recommendations(whtr ? waistBand(whtr) : null, statuses, plan?.phase ?? null);

  const todayNum = dayNumber(today);
  const ratios = balance(muscleSets(recent, muscles));
  const loadRatio = acwr(sets.map((s) => ({ day: dayNumber(s.date), load: volumeLoad([s], unit) })), todayNum);
  const lastTrained: Record<string, number> = {};
  for (const s of muscleWork) {
    const m = muscles[s.exerciseId]?.primary;
    if (m && s.type !== "warmup") lastTrained[m] = Math.max(lastTrained[m] ?? -Infinity, dayNumber(s.date));
  }
  const recency = Object.entries(muscleRecency(lastTrained, todayNum)).sort((a, b) => b[1] - a[1]);
  // Sessions under 10 minutes (quick tests, back-filled logs) would give absurd rates.
  const densities = workouts
    .filter((w) => w.ended_at && Date.parse(w.ended_at) - Date.parse(w.started_at) >= 600_000)
    .map((w) => ({ w, volume: volumeLoad(sets.filter((s) => s.sessionId === w.id), unit) }))
    // Cardio-only sessions have no volume and would drag the average to zero.
    .filter(({ volume }) => volume > 0)
    .slice(0, 10)
    .map(({ w, volume }) => density(volume, (Date.parse(w.ended_at!) - Date.parse(w.started_at)) / 60000))
    .filter((d): d is number => d !== null);
  const avgDensity = densities.length ? Math.round(densities.reduce((a, b) => a + b, 0) / densities.length) : null;
  const bigThree = BIG_THREE.map((id) => Math.max(0, ...bestE1RMPerSession(sets.filter((s) => s.exerciseId === id), unit, profile.e1rm_formula).map((p) => p.value)));
  const bodyKg = weightRow ? convert(weightRow.body_weight as number, weightRow.unit as "lb" | "kg", "kg") : null;
  const totalKg = bigThree.every((v) => v > 0) ? convert(bigThree.reduce((a, b) => a + b, 0), unit, "kg") : null;
  const scores = sex && totalKg && bodyKg ? { wilks: wilks(totalKg, bodyKg, sex), dots: dots(totalKg, bodyKg, sex) } : null;

  const byExercise = new Map<string, DatedSet[]>();
  for (const s of sets) if (dayNumber(s.date) > todayNum - 90) byExercise.set(s.exerciseId, [...(byExercise.get(s.exerciseId) ?? []), s]);
  const movers = exercises
    .filter((e) => byExercise.has(e.id))
    .map((e) => {
      const pts = sessionSeries(byExercise.get(e.id)!, unit, profile.e1rm_formula)
        .filter((p) => p.e1rm !== null)
        .map((p) => ({ day: p.day, value: p.e1rm! }));
      return { e, pts, g: growth(pts) };
    })
    .filter((m) => m.g && m.g.sessions >= 2 && m.g.changePct !== null)
    .sort((a, b) => b.g!.changePct! - a.g!.changePct!)
    .slice(0, 5);

  if (workouts.length === 0) {
    return (
      <div className="card text-center">
        <p>No workouts yet. Log one on your iPhone, or <Link className="text-accent" href="/workouts">add one here</Link>.</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Metric label="Workouts" value={String(workouts.length)} sub="all time" />
        <Metric label="This week" value={String(new Set(weekSets.map((s) => s.sessionId)).size)} sub={`target ${profile.weekly_workout_target}`} />
        <Metric label="Week streak" value={String(streak.current)} sub={`longest ${streak.longest}`} />
        <Metric label="Lifetime volume" value={`${Math.round(volumeLoad(sets, unit)).toLocaleString()}`} sub={unit} />
      </div>
      {movers.length > 0 && (
        <section className="card">
          <div className="mb-3 flex items-center">
            <h2 className="text-sm font-semibold tracking-tight">Top movers · last 90 days</h2>
            <Link href="/stats" className="ml-auto text-xs text-accent">
              All exercise growth →
            </Link>
          </div>
          <ul className="flex flex-col divide-y divide-border text-sm">
            {movers.map(({ e, pts, g }) => (
              <li key={e.id} className="flex items-center gap-3 py-2">
                <Link href={`/exercises/${e.id}`} className="min-w-0 flex-1 truncate font-medium hover:text-accent">
                  {e.name}
                </Link>
                <Sparkline values={pts.map((p) => p.value)} up={g!.change >= 0} />
                <span className="w-28 text-right text-muted">
                  {Math.round(g!.start)} → {Math.round(g!.recent)} {unit}
                </span>
                <span className={`w-16 text-right font-medium ${g!.change > 0 ? "text-good" : g!.change < 0 ? "text-bad" : ""}`}>
                  {g!.changePct! > 0 ? "+" : ""}
                  {g!.changePct}%
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}
      <section className="card flex flex-col gap-3">
        <h2 className="text-sm font-semibold tracking-tight">Aesthetics</h2>
        <div className="grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
          <div>
            <div className="text-xs text-muted">Body weight</div>
            {weightRow ? `${weightRow.body_weight} ${weightRow.unit}` : "—"}
          </div>
          <div>
            <div className="text-xs text-muted">Waist-to-height</div>
            {whtr ? `${whtr.toFixed(2)} (${waistBand(whtr)})` : "add height + waist"}
          </div>
          <div>
            <div className="text-xs text-muted">Body fat</div>
            {bodyFat !== null ? `${bodyFat}%${bfSource}` : sex ? "add height + waist" : "set sex in Settings"}
          </div>
          <div>
            <div className="text-xs text-muted">Height</div>
            {height ? toLen(height) : "—"}
          </div>
          <div>
            <div className="text-xs text-muted">Waist-to-hip</div>
            {whr ? whr.toFixed(2) : "add hips"}
            {sex && <div className="text-xs text-muted">{sex === "female" ? "under 0.80 is lean for women" : "under 0.90 is lean for men"}</div>}
          </div>
          {sex === "male" && (
            <div>
              <div className="text-xs text-muted">Shoulder target</div>
              {waist ? toLen(shoulderTarget(waist)) : "add waist"}
              <div className="text-xs text-muted">1.618 × waist, around the delts</div>
            </div>
          )}
        </div>
        {plan && (
          <div className="rounded-xl border border-border p-3 text-sm" style={{ background: "var(--accent-soft)" }}>
            <div className="flex flex-wrap items-baseline gap-x-2">
              <span className="font-semibold">Plan: {PHASE_LABELS[plan.phase]}</span>
              <span className="text-xs text-muted">
                at {bodyFat}% body fat{bfSource}
              </span>
            </div>
            <div className="mt-2 grid grid-cols-2 gap-3 md:grid-cols-4">
              <div>
                <div className="text-xs text-muted">First checkpoint</div>
                {plan.checkpoint} {unit}
                <div className="text-xs text-muted">then reassess · {goalPct}% would be {plan.goalWeight} {unit}</div>
              </div>
              <div>
                <div className="text-xs text-muted">{plan.phase === "lean_bulk" ? "Gain per week" : "Lose per week"}</div>
                {plan.weeklyLow}–{plan.weeklyHigh} {unit}
              </div>
              <div>
                <div className="text-xs text-muted">Time to checkpoint</div>
                {plan.weeks ? `~${plan.weeks} weeks` : "—"}
                <div className="text-xs text-muted">{plan.toLose > 0 ? `${plan.toLose} ${unit} to lose` : "at or below checkpoint"}</div>
              </div>
              <div>
                <div className="text-xs text-muted">Protein</div>
                {plan.proteinG} g/day
                <div className="text-xs text-muted">2.2 g per kg of goal weight</div>
              </div>
            </div>
          </div>
        )}
        <ul className="grid gap-1 text-sm">
          {statuses.map((s) => (
            <li key={s.muscle} className="flex items-center gap-3">
              <span className="w-28 text-muted">
                {MUSCLE_LABELS[s.muscle] ?? s.muscle}
                {s.priority ? " ★" : ""}
              </span>
              <span className="w-24">
                {s.actual} / {s.min}–{s.max}
              </span>
              <span className={s.status === "under" ? "text-red-500" : s.status === "over" ? "text-amber-500" : "text-accent"}>
                {s.status}
              </span>
            </li>
          ))}
        </ul>
        <p className="text-xs text-muted">Average weekly sets over the last 4 weeks vs. target. ★ = V-taper priority.</p>
        {tips.length > 0 && (
          <ul className="list-disc pl-5 text-sm">
            {tips.map((t) => (
              <li key={t}>{t}</li>
            ))}
          </ul>
        )}
        <Link href="/settings" className="text-xs text-accent">
          {sex ? "Log height, waist, hips and neck" : "Set your sex and log height, waist, hips and neck for body fat and a plan"}
        </Link>
      </section>
      <section className="card flex flex-col gap-3">
        <h2 className="text-sm font-semibold tracking-tight">Training balance</h2>
        <div className="grid grid-cols-2 gap-3 text-sm md:grid-cols-4">
          <div>
            <div className="text-xs text-muted">Push : pull sets</div>
            {ratios.pushPull ?? "—"}
            <div className="text-xs text-muted">aim 0.7–1.0 for posture and V-taper</div>
          </div>
          <div>
            <div className="text-xs text-muted">Quad : hamstring sets</div>
            {ratios.quadHam ?? "—"}
            <div className="text-xs text-muted">aim 1.0–1.5</div>
          </div>
          <div>
            <div className="text-xs text-muted">Workload (7d : 28d)</div>
            <span className={loadRatio !== null && (loadRatio > 1.5 || loadRatio < 0.8) ? "text-amber-500" : ""}>{loadRatio ?? "—"}</span>
            <div className="text-xs text-muted">0.8–1.3 is steady progression</div>
          </div>
          <div>
            <div className="text-xs text-muted">Density</div>
            {avgDensity !== null ? `${avgDensity} ${unit}/min` : "—"}
            <div className="text-xs text-muted">last 10 timed workouts</div>
          </div>
          <div>
            <div className="text-xs text-muted">Big-3 e1RM total</div>
            {totalKg ? `${Math.round(bigThree.reduce((a, b) => a + b, 0))} ${unit}` : "log squat, bench, deadlift"}
          </div>
          <div>
            <div className="text-xs text-muted">Wilks / DOTS</div>
            {scores ? `${scores.wilks} / ${scores.dots}` : sex ? "needs big-3 + body weight" : "set sex in Settings"}
          </div>
        </div>
        {recency.length > 0 && (
          <div className="text-sm">
            <div className="mb-1 text-xs text-muted">Days since last trained</div>
            <div className="flex flex-wrap gap-2">
              {recency.map(([m, d]) => (
                <span key={m} className={`rounded border border-border px-2 py-0.5 ${d >= 7 ? "text-red-500" : d >= 4 ? "text-amber-500" : ""}`}>
                  {MUSCLE_LABELS[m] ?? m} {d}d
                </span>
              ))}
            </div>
          </div>
        )}
      </section>
      <section className="card">
        <h2 className="card-title">Weekly volume ({unit})</h2>
        <BarsChart data={weeklyVolume} unit={unit} />
      </section>
      <section className="card">
        <h2 className="card-title">Hard sets per muscle this week</h2>
        {muscleCounts.length === 0 ? (
          <p className="text-sm text-muted">No sets logged this week yet.</p>
        ) : (
          <ul className="grid gap-1 text-sm">
            {muscleCounts.map(([m, n]) => (
              <li key={m} className="flex items-center gap-3">
                <span className="w-28 text-muted">{MUSCLE_LABELS[m] ?? m}</span>
                <span className="h-2 rounded bg-accent" style={{ width: `${Math.min(n, 25) * 4}%` }} />
                <span>{n}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
