/** Tiny inline SVG trend line; no axes. */
export function Sparkline({
  values,
  up: upProp,
  width = 96,
  height = 28,
  className = "",
}: {
  values: number[];
  up?: boolean;
  width?: number;
  height?: number;
  className?: string;
}) {
  if (values.length < 2) return <svg width={width} height={height} className={className} />;
  const min = Math.min(...values);
  const span = Math.max(...values) - min || 1;
  const pts = values.map((v, i) => [(i / (values.length - 1)) * (width - 4) + 2, height - 2 - ((v - min) / span) * (height - 4)]);
  const up = upProp ?? values[values.length - 1] >= values[0];
  const color = up ? "var(--good)" : "var(--bad)";
  const [lx, ly] = pts[pts.length - 1];
  return (
    <svg width={width} height={height} className={className} aria-hidden>
      <polyline points={pts.map((p) => p.join(",")).join(" ")} fill="none" stroke={color} strokeWidth={1.75} strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={lx} cy={ly} r={2.5} fill={color} />
    </svg>
  );
}
