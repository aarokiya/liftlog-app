import { describe, expect, it } from "vitest";
import { exerciseKey, parseCsv, parseDate, parseDropNote, parseRepCount } from "./repcount";

describe("parseCsv", () => {
  it("handles quotes, escaped quotes, CRLF and BOM", () => {
    expect(parseCsv('\uFEFFa,b\r\n"x, y","say ""hi"""\r\n')).toEqual([
      ["a", "b"],
      ["x, y", 'say "hi"'],
    ]);
  });

  it("detects semicolon delimiters", () => {
    expect(parseCsv("a;b\n1,5;2")).toEqual([
      ["a", "b"],
      ["1,5", "2"],
    ]);
  });
});

describe("parseDate", () => {
  it("treats naive timestamps as wall-clock time in the given zone", () => {
    expect(parseDate("2024-03-01 18:30", "America/New_York")?.toISOString()).toBe("2024-03-01T23:30:00.000Z");
  });

  it("respects explicit offsets", () => {
    expect(parseDate("2024-03-01T18:30:00Z", "America/New_York")?.toISOString()).toBe("2024-03-01T18:30:00.000Z");
  });

  it("parses US dates with am/pm", () => {
    expect(parseDate("3/1/2024 6:30 PM", "UTC")?.toISOString()).toBe("2024-03-01T18:30:00.000Z");
  });
});

describe("parseRepCount", () => {
  const csv = [
    "Date,Workout,Exercise,Set Type,Weight (lbs),Reps,Notes",
    "2024-03-01 18:30,Push,Bench Press (Barbell),Warmup,95,10,",
    "2024-03-01 18:30,Push,Bench Press (Barbell),Normal,185,5,felt good",
    "2024-03-01 18:30,Push,Bench Press (Barbell),Normal,185,5,",
    "2024-03-01 18:30,Push,Lateral Raise (Dumbbell),Drop,20,12,",
    "2024-03-03 09:00,Legs,Squat (Barbell),Normal,225,5,",
    ",,,,,,",
  ].join("\n");

  it("groups rows into workouts, exercises and sets", () => {
    const { workouts, columns } = parseRepCount(csv, { timeZone: "UTC", defaultUnit: "lb" });
    expect(columns).toMatchObject({ date: "Date", workout: "Workout", exercise: "Exercise", weight: "Weight (lbs)" });
    expect(workouts).toHaveLength(2);
    expect(workouts[0].name).toBe("Push");
    expect(workouts[0].exercises.map((e) => e.name)).toEqual(["Bench Press (Barbell)", "Lateral Raise (Dumbbell)"]);
    expect(workouts[0].exercises[0].sets.map((s) => s.type)).toEqual(["warmup", "working", "working"]);
    expect(workouts[0].exercises[0].sets[1]).toMatchObject({ weight: 185, unit: "lb", reps: 5, notes: "felt good" });
    expect(workouts[0].exercises[1].sets[0].type).toBe("drop");
  });

  it("reads the unit from the weight header", () => {
    const { workouts } = parseRepCount("Date,Exercise,Weight (kg),Reps\n2024-01-01,Squat,100,5", {
      timeZone: "UTC",
      defaultUnit: "lb",
    });
    expect(workouts[0].exercises[0].sets[0]).toMatchObject({ weight: 100, unit: "kg" });
  });

  it("explains a header it can't use", () => {
    expect(() => parseRepCount("foo,bar\n1,2", { timeZone: "UTC", defaultUnit: "lb" })).toThrow(/date and exercise/);
  });
});

describe("exerciseKey", () => {
  it("ignores word order and punctuation", () => {
    expect(exerciseKey("Bench Press (Barbell)")).toBe(exerciseKey("Barbell bench press"));
  });
});

describe("Gymin export", () => {
  const csv = [
    "workout_type,date,exercise,set_number,weight_lb,reps,set_note,workout_start_time,workout_end_time,duration_min,body_weight_lb",
    "Pull,2026-01-05,Lat pulldown,1,150,8,,2026-01-05 17:00,2026-01-05 18:10,70,180.5",
    "Pull,2026-01-05,Lat pulldown,2,160,3,Dropped 130 6,2026-01-05 17:00,2026-01-05 18:10,70,180.5",
    "Pull,2026-01-05,Rear Dealt,1,,,,2026-01-05 17:00,2026-01-05 18:10,70,180.5",
    "Pull,2026-01-05,Mystery Machine,1,40,12,,2026-01-05 17:00,2026-01-05 18:10,70,180.5",
  ].join("\n");
  const result = parseRepCount(csv, { timeZone: "America/New_York", defaultUnit: "lb" });

  it("detects the source and prefers start/end timestamps", () => {
    expect(result.source).toBe("gymin");
    expect(result.columns.date).toBe("workout_start_time");
    expect(result.workouts[0].startedAt).toBe("2026-01-05T22:00:00.000Z");
    expect(result.workouts[0].endedAt).toBe("2026-01-05T23:10:00.000Z");
    expect(result.workouts[0].name).toBe("Pull");
  });

  it("reads body weight and skips empty planned sets", () => {
    expect(result.workouts[0].bodyWeight).toEqual({ value: 180.5, unit: "lb" });
    expect(result.skippedRows).toBe(1);
    expect(result.workouts[0].exercises.map((e) => e.name)).toEqual(["Lat Pulldown (Cable)", "Mystery Machine"]);
    expect(result.renamed).toEqual({ "Lat pulldown": "Lat Pulldown (Cable)" });
  });

  it("turns drop notes into drop sets", () => {
    const sets = result.workouts[0].exercises[0].sets;
    expect(sets).toHaveLength(3);
    expect(sets[2]).toMatchObject({ weight: 130, reps: 6, type: "drop" });
    expect(sets[1].notes).toBe("Dropped 130 6");
  });
});

describe("parseDropNote", () => {
  it.each([
    ["Dropped 135 6", { weight: 135, reps: 6 }],
    ["Dropped 110 for 4", { weight: 110, reps: 4 }],
    ["Dropped set 35", { weight: 35, reps: null }],
    ["47.5 dropset 5", { weight: 47.5, reps: 5 }],
    ["Attempted 200 before", null],
    ["Not to failure", null],
  ])("%s", (note, expected) => {
    expect(parseDropNote(note)).toEqual(expected);
  });
});
