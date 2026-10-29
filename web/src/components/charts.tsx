"use client";

import { Bar, BarChart, CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

export interface Point {
  label: string;
  value: number;
  trend?: number;
  pr?: boolean;
}

const axis = { stroke: "var(--muted)", fontSize: 12, tickLine: false, axisLine: false };
const tooltip = {
  contentStyle: { background: "var(--card)", border: "1px solid var(--border)", borderRadius: 12, fontSize: 12 },
  labelStyle: { color: "var(--muted)" },
};

export function LineTrendChart({ data, unit, name = "e1RM", height = 260 }: { data: Point[]; unit: string; name?: string; height?: number }) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <LineChart data={data} margin={{ left: 0, right: 8, top: 8 }}>
        <CartesianGrid stroke="var(--border)" vertical={false} />
        <XAxis dataKey="label" {...axis} minTickGap={24} />
        <YAxis {...axis} domain={["auto", "auto"]} width={52} />
        <Tooltip {...tooltip} formatter={(v) => `${(Math.round(Number(v) * 10) / 10).toLocaleString()} ${unit}`} />
        <Line
          type="monotone"
          dataKey="value"
          stroke="var(--accent)"
          strokeWidth={2.5}
          name={name}
          dot={(p: { cx?: number; cy?: number; index?: number; payload?: Point }) => (
            <circle
              key={p.index}
              cx={p.cx}
              cy={p.cy}
              r={p.payload?.pr ? 4.5 : 2.5}
              fill={p.payload?.pr ? "var(--accent)" : "var(--card)"}
              stroke="var(--accent)"
              strokeWidth={1.5}
            />
          )}
        />
        <Line type="linear" dataKey="trend" stroke="var(--muted)" strokeDasharray="4 4" dot={false} name="Trend" />
      </LineChart>
    </ResponsiveContainer>
  );
}

export function BarsChart({ data, unit }: { data: Point[]; unit: string }) {
  return (
    <ResponsiveContainer width="100%" height={240}>
      <BarChart data={data} margin={{ left: 0, right: 8, top: 8 }}>
        <CartesianGrid stroke="var(--border)" vertical={false} />
        <XAxis dataKey="label" {...axis} />
        <YAxis {...axis} width={56} />
        <Tooltip {...tooltip} cursor={{ fill: "var(--accent-soft)" }} formatter={(v) => `${Math.round(Number(v)).toLocaleString()} ${unit}`} />
        <Bar dataKey="value" fill="var(--accent)" radius={[6, 6, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}
