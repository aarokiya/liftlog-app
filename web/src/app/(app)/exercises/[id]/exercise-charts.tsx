"use client";

import { useState } from "react";
import { LineTrendChart } from "@/components/charts";
import { linearRegression } from "@/lib/stats";

export interface ChartSession {
  date: string;
  day: number;
  e1rm: number | null;
  top: number;
  volume: number;
  reps: number;
}

const METRICS = [
  { id: "e1rm", label: "Est. 1RM" },
  { id: "top", label: "Top set" },
  { id: "volume", label: "Volume" },
  { id: "reps", label: "Total reps" },
] as const;
const WINDOWS = [
  { id: "all", label: "All", days: Infinity },
  { id: "180", label: "6 mo", days: 180 },
  { id: "90", label: "3 mo", days: 90 },
  { id: "30", label: "1 mo", days: 30 },
] as const;

export function ExerciseCharts({ sessions, unit, today }: { sessions: ChartSession[]; unit: string; today: number }) {
  const [metric, setMetric] = useState<(typeof METRICS)[number]["id"]>("e1rm");
  const [win, setWin] = useState<(typeof WINDOWS)[number]["id"]>("all");
  const days = WINDOWS.find((w) => w.id === win)!.days;
  const pts = sessions
    .filter((s) => s.day > today - days)
    .map((s) => ({ ...s, value: s[metric] }))
    .filter((s): s is typeof s & { value: number } => s.value !== null);
  const fit = linearRegression(pts.map((p) => [p.day, p.value]));
  let best = -Infinity;
  const data = pts.map((p) => {
    const pr = p.value > best;
    best = Math.max(best, p.value);
    return { label: p.date.slice(5), value: p.value, pr, trend: fit ? fit.intercept + fit.slope * p.day : undefined };
  });
  const label = METRICS.find((m) => m.id === metric)!.label;

  return (
    <section className="card">
      <div className="mb-3 flex flex-wrap items-center gap-2">
        {METRICS.map((m) => (
          <button key={m.id} onClick={() => setMetric(m.id)} className={`chip ${metric === m.id ? "chip-on" : ""}`}>
            {m.label}
          </button>
        ))}
        <span className="ml-auto flex gap-1">
          {WINDOWS.map((w) => (
            <button key={w.id} onClick={() => setWin(w.id)} className={`chip ${win === w.id ? "chip-on" : ""}`}>
              {w.label}
            </button>
          ))}
        </span>
      </div>
      {data.length === 0 ? (
        <p className="py-10 text-center text-sm text-muted">No sessions in this window.</p>
      ) : (
        <LineTrendChart data={data} unit={metric === "reps" ? "reps" : unit} name={label} />
      )}
      <p className="mt-2 text-xs text-muted">Filled dots are sessions that beat every earlier one. Dashed line is the trend.</p>
    </section>
  );
}
