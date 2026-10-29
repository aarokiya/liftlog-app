// Workout CSV import (RepCount, Gymin and similar). Neither app documents its export columns, so headers are
// matched by alias and the parser reports which columns it used so a mismatch is visible before anything is written.

export type Unit = "lb" | "kg";
export type SetType = "warmup" | "working" | "drop" | "failure";

export interface ParsedSet {
  weight: number | null;
  unit: Unit;
  reps: number | null;
  type: SetType;
  rpe: number | null;
  notes: string | null;
}

export interface ParsedExercise {
  name: string;
  sets: ParsedSet[];
}

export interface ParsedWorkout {
  name: string;
  startedAt: string;
  endedAt: string | null;
  bodyWeight: { value: number; unit: Unit } | null;
  exercises: ParsedExercise[];
}

export type ImportSource = "repcount" | "gymin";

export interface ParseResult {
  source: ImportSource;
  workouts: ParsedWorkout[];
  columns: Partial<Record<Field, string>>;
  /** Original exercise name → built-in name it was matched to. */
  renamed: Record<string, string>;
  skippedRows: number;
}

type Field =
  | "date"
  | "end"
  | "workout"
  | "exercise"
  | "weight"
  | "unit"
  | "reps"
  | "setType"
  | "warmup"
  | "rpe"
  | "notes"
  | "duration"
  | "bodyWeight";

// Earlier aliases win, so a full start timestamp is preferred over a date-only column.
const ALIASES: Record<Field, string[]> = {
  date: ["workout start time", "start time", "started at", "datetime", "date", "workout date", "start", "time"],
  end: ["workout end time", "end time", "ended at", "end"],
  workout: ["workout", "workout name", "workout type", "routine", "routine name", "session", "title"],
  exercise: ["exercise", "exercise name", "exercise title", "movement"],
  weight: ["weight", "weight lb", "weight lbs", "weight kg", "load", "kg", "lb", "lbs"],
  unit: ["unit", "units", "weight unit"],
  reps: ["reps", "repetitions", "rep count"],
  setType: ["set type", "type", "set kind"],
  warmup: ["warmup", "warm up", "is warmup", "warm-up"],
  rpe: ["rpe"],
  notes: ["notes", "note", "comment", "set notes", "set note"],
  duration: ["duration", "workout duration", "duration minutes", "duration min"],
  bodyWeight: ["body weight lb", "body weight lbs", "body weight kg", "body weight", "bodyweight"],
};

// Common names and typos in phone-app exports → built-in exercise names (keys go through nameKey).
const BUILT_IN_ALIASES: Record<string, string> = {
  "bench press": "Bench Press (Barbell)",
  "lat pulldown": "Lat Pulldown (Cable)",
  "cable row": "Seated Cable Row",
  "pec deck": "Pec Deck (Machine)",
  "machine lat raise": "Lateral Raise (Machine)",
  "machine lateral raise": "Lateral Raise (Machine)",
  "rear delt": "Rear Delt Fly (Machine)",
  "rear dealt": "Rear Delt Fly (Machine)",
  "shoulder machine press": "Shoulder Press (Machine)",
  "machine shoulder press": "Shoulder Press (Machine)",
  "chest press": "Chest Press (Machine)",
  "iso lat incline": "Incline Chest Press (Hammer Strength)",
  "preacher curl": "Preacher Curl (EZ Bar)",
  "tricep extension": "Overhead Triceps Extension (Cable)",
  "seated press down": "Seated Dip (Machine)",
  pushdown: "Triceps Pushdown (Cable)",
  "close grip bench press": "Close-Grip Bench Press (Barbell)",
  "straight leg deadlift": "Stiff-Leg Deadlift (Barbell)",
  "stiff leg deadlift": "Stiff-Leg Deadlift (Barbell)",
  forearm: "Wrist Curl (Dumbbell)",
  crunche: "Crunch",
  "cable crunche": "Cable Crunch",
  "ab machine": "Ab Crunch (Machine)",
  "spinal erector": "Back Extension",
  "leg extension": "Leg Extension (Machine)",
  "leg curl": "Seated Leg Curl (Machine)",
  "calf raise": "Standing Calf Raise (Machine)",
  adducter: "Hip Adduction (Machine)",
  adductor: "Hip Adduction (Machine)",
  "leg raise": "Leg Raise (Captain's Chair)",
  "hammer curl": "Hammer Curl (Dumbbell)",
};

const nameKey = (name: string) =>
  name
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, " ")
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => (w.length > 3 && w.endsWith("s") && !w.endsWith("ss") ? w.slice(0, -1) : w))
    .join(" ");

/** Maps an exported exercise name to a built-in name when it's a known alias; otherwise returns it trimmed. */
export function canonicalExerciseName(name: string): string {
  return BUILT_IN_ALIASES[nameKey(name)] ?? name.trim();
}

/** "Dropped 135 6", "Dropped 110 for 4", "Dropped set 35", "47.5 dropset 5" → the extra drop set. */
export function parseDropNote(note: string | null): { weight: number; reps: number | null } | null {
  if (!note) return null;
  const n = note.trim();
  const m =
    n.match(/^drop(?:ped)?(?:\s*set)?\s+(\d+(?:\.\d+)?)(?:\s*(?:lbs?|kg))?(?:\s+(?:for\s+|x\s*)?(\d+))?\b/i) ??
    n.match(/^(\d+(?:\.\d+)?)\s*(?:lbs?|kg)?\s*drop\s*set(?:\s+(?:for\s+|x\s*)?(\d+))?\b/i);
  return m ? { weight: Number(m[1]), reps: m[2] ? Number(m[2]) : null } : null;
}

const normalize = (h: string) => h.toLowerCase().replace(/[()_\-]/g, " ").replace(/\s+/g, " ").trim();

export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  const src = text.replace(/^\uFEFF/, "");
  const delimiter = detectDelimiter(src);
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (quoted) {
      if (c === '"' && src[i + 1] === '"') {
        field += '"';
        i++;
      } else if (c === '"') {
        quoted = false;
      } else {
        field += c;
      }
    } else if (c === '"') {
      quoted = true;
    } else if (c === delimiter) {
      row.push(field);
      field = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && src[i + 1] === "\n") i++;
      row.push(field);
      if (row.some((f) => f.trim() !== "")) rows.push(row);
      row = [];
      field = "";
    } else {
      field += c;
    }
  }
  row.push(field);
  if (row.some((f) => f.trim() !== "")) rows.push(row);
  return rows;
}

function detectDelimiter(text: string): string {
  const firstLine = text.split(/\r?\n/, 1)[0] ?? "";
  const counts = [",", ";", "\t"].map((d) => [d, firstLine.split(d).length] as const);
  return counts.sort((a, b) => b[1] - a[1])[0][0];
}

function mapColumns(header: string[]): Partial<Record<Field, number>> {
  const normalized = header.map(normalize);
  const result: Partial<Record<Field, number>> = {};
  for (const field of Object.keys(ALIASES) as Field[]) {
    for (const alias of ALIASES[field]) {
      const index = normalized.indexOf(alias);
      if (index >= 0) {
        result[field] = index;
        break;
      }
    }
  }
  return result;
}

function parseNumber(value: string | undefined): number | null {
  if (value === undefined) return null;
  const cleaned = value.trim().replace(/[^\d.,-]/g, "");
  if (cleaned === "") return null;
  const n = Number(cleaned.includes(",") && !cleaned.includes(".") ? cleaned.replace(",", ".") : cleaned.replace(/,/g, ""));
  return Number.isFinite(n) ? n : null;
}

function parseUnit(value: string | undefined, header: string, fallback: Unit): Unit {
  const v = `${value ?? ""} ${header}`.toLowerCase();
  if (/\bkgs?\b/.test(v)) return "kg";
  if (/\blbs?\b/.test(v)) return "lb";
  return fallback;
}

function parseSetType(type: string | undefined, warmup: string | undefined): SetType {
  const t = (type ?? "").toLowerCase();
  if (t.includes("warm") || /^(true|yes|1|y)$/i.test((warmup ?? "").trim())) return "warmup";
  if (t.includes("drop")) return "drop";
  if (t.includes("fail")) return "failure";
  return "working";
}

/** Converts a wall-clock time in `timeZone` to a UTC instant. */
export function zonedToUtc(y: number, mo: number, d: number, h: number, mi: number, s: number, timeZone: string): Date {
  const guess = Date.UTC(y, mo - 1, d, h, mi, s);
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    })
      .formatToParts(new Date(guess))
      .map((p) => [p.type, p.value]),
  );
  const asZoned = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, +parts.second);
  return new Date(guess - (asZoned - guess));
}

export function parseDate(value: string, timeZone: string): Date | null {
  const v = value.trim();
  if (!v) return null;
  if (/[zZ]$|[+-]\d{2}:?\d{2}$/.test(v)) {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  let m = v.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?/);
  if (m) return zonedToUtc(+m[1], +m[2], +m[3], +(m[4] ?? 12), +(m[5] ?? 0), +(m[6] ?? 0), timeZone);
  m = v.match(/^(\d{1,2})[/.](\d{1,2})[/.](\d{4})(?:,?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap]m)?)?/i);
  if (m) {
    let hour = +(m[4] ?? 12);
    if (m[7]) hour = (hour % 12) + (m[7].toLowerCase() === "pm" ? 12 : 0);
    return zonedToUtc(+m[3], +m[1], +m[2], hour, +(m[5] ?? 0), +(m[6] ?? 0), timeZone);
  }
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}

export function parseRepCount(text: string, opts: { timeZone: string; defaultUnit: Unit }): ParseResult {
  const [header, ...rows] = parseCsv(text);
  if (!header) return { source: "repcount", workouts: [], columns: {}, renamed: {}, skippedRows: 0 };
  const cols = mapColumns(header);
  const normalizedHeader = header.map(normalize);
  const source: ImportSource =
    normalizedHeader.includes("workout type") && normalizedHeader.includes("set number") ? "gymin" : "repcount";
  const renamed: Record<string, string> = {};
  const columns = Object.fromEntries(Object.entries(cols).map(([k, i]) => [k, header[i!]])) as ParseResult["columns"];
  if (cols.date === undefined || cols.exercise === undefined) {
    throw new Error(`Couldn't find date and exercise columns. Header was: ${header.join(", ")}`);
  }
  const get = (row: string[], field: Field) => (cols[field] === undefined ? undefined : row[cols[field]!]);
  const byKey = new Map<string, ParsedWorkout>();
  let skippedRows = 0;

  for (const row of rows) {
    const date = parseDate(get(row, "date") ?? "", opts.timeZone);
    const rawName = get(row, "exercise")?.trim();
    const weight = parseNumber(get(row, "weight"));
    const reps = parseNumber(get(row, "reps"));
    const notes = get(row, "notes")?.trim() || null;
    // Planned-but-never-filled sets carry no information.
    if (!date || !rawName || (weight === null && reps === null && !notes)) {
      skippedRows++;
      continue;
    }
    const exerciseName = canonicalExerciseName(rawName);
    if (exerciseName !== rawName) renamed[rawName] = exerciseName;
    const workoutName = get(row, "workout")?.trim() || "Workout";
    const key = `${date.toISOString()}|${workoutName}`;
    let workout = byKey.get(key);
    if (!workout) {
      const minutes = parseNumber(get(row, "duration"));
      const end = parseDate(get(row, "end") ?? "", opts.timeZone);
      const bodyWeight = parseNumber(get(row, "bodyWeight"));
      const bodyWeightHeader = cols.bodyWeight === undefined ? "" : header[cols.bodyWeight];
      workout = {
        name: workoutName,
        startedAt: date.toISOString(),
        endedAt:
          end && end > date
            ? end.toISOString()
            : minutes
              ? new Date(date.getTime() + minutes * 60_000).toISOString()
              : null,
        bodyWeight: bodyWeight ? { value: bodyWeight, unit: parseUnit(undefined, bodyWeightHeader, opts.defaultUnit) } : null,
        exercises: [],
      };
      byKey.set(key, workout);
    }
    let exercise = workout.exercises.at(-1);
    if (!exercise || exercise.name !== exerciseName) {
      exercise = workout.exercises.find((e) => e.name === exerciseName);
      if (!exercise) {
        exercise = { name: exerciseName, sets: [] };
        workout.exercises.push(exercise);
      }
    }
    const weightHeader = cols.weight === undefined ? "" : header[cols.weight];
    const unit = parseUnit(get(row, "unit"), weightHeader, opts.defaultUnit);
    exercise.sets.push({
      weight,
      unit,
      reps,
      type: parseSetType(get(row, "setType"), get(row, "warmup")),
      rpe: parseNumber(get(row, "rpe")),
      notes,
    });
    const drop = parseDropNote(notes);
    if (drop) exercise.sets.push({ weight: drop.weight, unit, reps: drop.reps, type: "drop", rpe: null, notes: null });
  }

  const workouts = [...byKey.values()].sort((a, b) => a.startedAt.localeCompare(b.startedAt));
  return { source, workouts, columns, renamed, skippedRows };
}

/** Loose key for matching exercise names: "Bench Press (Barbell)" ≈ "barbell bench press". */
export function exerciseKey(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, " ")
    .split(/\s+/)
    .filter(Boolean)
    .sort()
    .join(" ");
}
