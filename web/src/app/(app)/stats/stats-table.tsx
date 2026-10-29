"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { Sparkline } from "@/components/sparkline";
import { growth, type Growth } from "@/lib/stats/advanced";
import { MUSCLE_LABELS } from "@/lib/types";

export interface GrowthRow {
  id: string;
  name: string;
  muscle: string;
  points: { day: number; e1rm: number | null; top: number; volume: number }[];
}

const WINDOWS = [
  { id: "all", label: "All time", days: Infinity },
  { id: "90", label: "90 days", days: 90 },
  { id: "30", label: "30 days", days: 30 },
] as const;
const METRICS = [
  { id: "e1rm", label: "Est. 1RM" },
  { id: "top", label: "Top set" },
] as const;
const SORTS = [
  { id: "gain", label: "Biggest gain" },
  { id: "rate", label: "Fastest trend" },
  { id: "prs", label: "Most PRs" },
  { id: "sessions", label: "Most sessions" },
  { id: "recent", label: "Recently trained" },
  { id: "name", label: "Name" },
] as const;

const fmt = (v: number) => (Math.round(v * 10) / 10).toLocaleString();
const signed = (v: number) => `${v > 0 ? "+" : ""}${fmt(v)}`;

export function StatsTable({ rows, unit, today }: { rows: GrowthRow[]; unit: string; today: number }) {
  const [win, setWin] = useState<(typeof WINDOWS)[number]["id"]>("all");
  const [metric, setMetric] = useState<(typeof METRICS)[number]["id"]>("e1rm");
  const [sort, setSort] = useState<(typeof SORTS)[number]["id"]>("gain");
  const [muscle, setMuscle] = useState("all");
  const [q, setQ] = useState("");

  const computed = useMemo(() => {
    const days = WINDOWS.find((w) => w.id === win)!.days;
    return rows
      .map((r) => {
        const pts = r.points
          .filter((p) => p.day > today - days)
          .map((p) => ({ day: p.day, value: metric === "e1rm" ? p.e1rm : p.top }))
          .filter((p): p is { day: number; value: number } => p.value !== null && p.value > 0);
        return { ...r, pts, g: growth(pts), last: r.points[r.points.length - 1].day };
      })
      .filter((r): r is typeof r & { g: Growth } => r.g !== null);
  }, [rows, win, metric, today]);

  const muscles = useMemo(() => [...new Set(rows.map((r) => r.muscle))].sort(), [rows]);
  const visible = computed
    .filter((r) => (muscle === "all" || r.muscle === muscle) && r.name.toLowerCase().includes(q.toLowerCase()))
    .sort((a, b) => {
      switch (sort) {
        case "gain":
          return (b.g.changePct ?? -Infinity) - (a.g.changePct ?? -Infinity);
        case "rate":
          return (b.g.weeklyRate ?? -Infinity) - (a.g.weeklyRate ?? -Infinity);
        case "prs":
          return b.g.prs - a.g.prs;
        case "sessions":
          return b.g.sessions - a.g.sessions;
        case "recent":
          return b.last - a.last;
        default:
          return a.name.localeCompare(b.name);
      }
    });

  const comparable = computed.filter((r) => r.g.sessions >= 2);
  const improving = comparable.filter((r) => r.g.change > 0).length;
  const prs = computed.reduce((n, r) => n + r.g.prs, 0);
  const top = [...comparable].sort((a, b) => (b.g.changePct ?? 0) - (a.g.changePct ?? 0))[0];
  const pcts = comparable.map((r) => r.g.changePct ?? 0).sort((a, b) => a - b);
  const median = pcts.length ? pcts[Math.floor(pcts.length / 2)] : null;

  return (
    <div className="flex flex-col gap-4">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Summary label="Lifts improving" value={`${improving} / ${comparable.length}`} sub="with 2+ sessions" />
        <Summary label="New records" value={String(prs)} sub={`${METRICS.find((m) => m.id === metric)!.label} PRs`} />
        <Summary label="Median change" value={median !== null ? `${signed(median)}%` : "—"} tone={median} />
        <Summary label="Top gainer" value={top ? `${signed(top.g.changePct ?? 0)}%` : "—"} sub={top?.name} tone={top?.g.changePct ?? null} />
      </div>

      <div className="card flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          {WINDOWS.map((w) => (
            <button key={w.id} onClick={() => setWin(w.id)} className={`chip ${win === w.id ? "chip-on" : ""}`}>
              {w.label}
            </button>
          ))}
          <span className="mx-1 h-5 w-px bg-border" />
          {METRICS.map((m) => (
            <button key={m.id} onClick={() => setMetric(m.id)} className={`chip ${metric === m.id ? "chip-on" : ""}`}>
              {m.label}
            </button>
          ))}
        </div>
        <div className="flex flex-wrap gap-2">
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search exercises" className="input w-full sm:w-auto sm:flex-1" />
          <select value={muscle} onChange={(e) => setMuscle(e.target.value)} className="input">
            <option value="all">All muscles</option>
            {muscles.map((m) => (
              <option key={m} value={m}>
                {MUSCLE_LABELS[m] ?? m}
              </option>
            ))}
          </select>
          <select value={sort} onChange={(e) => setSort(e.target.value as typeof sort)} className="input">
            {SORTS.map((s) => (
              <option key={s.id} value={s.id}>
                {s.label}
              </option>
            ))}
          </select>
        </div>

        <ul className="-mx-4 flex flex-col divide-y divide-border border-t border-border md:hidden">
          {visible.map((r) => (
            <li key={r.id}>
              <Link href={`/exercises/${r.id}`} className="flex items-center gap-3 px-4 py-3">
                <div className="min-w-0 flex-1">
                  <div className="truncate font-medium">{r.name}</div>
                  <div className="text-xs text-muted">
                    {fmt(r.g.start)} → {fmt(r.g.recent)} {unit} · {ago(today - r.last)}
                  </div>
                </div>
                <Sparkline values={r.pts.map((p) => p.value)} up={r.g.change >= 0} width={64} />
                <div className="w-16 text-right">
                  <div className={`font-semibold ${tone(r.g.sessions > 1 ? r.g.change : null)}`}>
                    {r.g.sessions > 1 ? `${signed(r.g.changePct ?? 0)}%` : "—"}
                  </div>
                  {r.g.prs > 0 && <div className="text-xs text-accent">{r.g.prs} PR{r.g.prs === 1 ? "" : "s"}</div>}
                </div>
              </Link>
            </li>
          ))}
          {visible.length === 0 && <li className="px-4 py-8 text-center text-sm text-muted">No lifts match in this window.</li>}
        </ul>
        <div className="-mx-4 hidden overflow-x-auto md:-mx-5 md:block">
          <table className="w-full min-w-[640px] text-sm">
            <thead>
              <tr className="label text-left">
                <th className="px-4 py-2 md:px-5">Exercise</th>
                <th className="py-2">Trend</th>
                <th className="py-2 text-right">Start → now</th>
                <th className="py-2 text-right">Change</th>
                <th className="py-2 text-right">/ week</th>
                <th className="py-2 text-right">PRs</th>
                <th className="px-4 py-2 text-right md:px-5">Last</th>
              </tr>
            </thead>
            <tbody>
              {visible.map((r) => (
                <tr key={r.id} className="border-t border-border transition hover:bg-accent-soft/40">
                  <td className="px-4 py-2.5 md:px-5">
                    <Link href={`/exercises/${r.id}`} className="font-medium hover:text-accent">
                      {r.name}
                    </Link>
                    <div className="text-xs text-muted">
                      {MUSCLE_LABELS[r.muscle] ?? r.muscle} · {r.g.sessions} session{r.g.sessions === 1 ? "" : "s"}
                    </div>
                  </td>
                  <td className="py-2.5">
                    <Sparkline values={r.pts.map((p) => p.value)} up={r.g.change >= 0} />
                  </td>
                  <td className="py-2.5 text-right text-muted">
                    {fmt(r.g.start)} → <span className="font-medium text-foreground">{fmt(r.g.recent)}</span> {unit}
                  </td>
                  <td className={`py-2.5 text-right font-medium ${tone(r.g.sessions > 1 ? r.g.change : null)}`}>
                    {r.g.sessions > 1 ? (
                      <>
                        {signed(r.g.change)} <span className="text-xs">({signed(r.g.changePct ?? 0)}%)</span>
                      </>
                    ) : (
                      "—"
                    )}
                  </td>
                  <td className={`py-2.5 text-right ${tone(r.g.weeklyRate)}`}>{r.g.weeklyRate !== null ? signed(r.g.weeklyRate) : "—"}</td>
                  <td className="py-2.5 text-right">{r.g.prs > 0 ? <span className="rounded-full bg-accent-soft px-2 py-0.5 text-xs font-medium text-accent">{r.g.prs}</span> : "—"}</td>
                  <td className="px-4 py-2.5 text-right text-muted md:px-5">{ago(today - r.last)}</td>
                </tr>
              ))}
              {visible.length === 0 && (
                <tr>
                  <td colSpan={7} className="px-4 py-8 text-center text-muted">
                    No lifts match in this window.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
        <p className="text-xs text-muted">
          Change compares your first session in the window with the best of your last 3. PRs count sessions that beat every earlier one.
        </p>
      </div>
    </div>
  );
}

const tone = (v: number | null | undefined) => (v === null || v === undefined || v === 0 ? "" : v > 0 ? "text-good" : "text-bad");
const ago = (d: number) => (d <= 0 ? "today" : d === 1 ? "yesterday" : `${d}d ago`);

function Summary({ label, value, sub, tone: t }: { label: string; value: string; sub?: string; tone?: number | null }) {
  return (
    <div className="card">
      <div className="label">{label}</div>
      <div className={`mt-1 text-2xl font-semibold ${tone(t)}`}>{value}</div>
      {sub && <div className="truncate text-xs text-muted">{sub}</div>}
    </div>
  );
}
