import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { exerciseUuid, parseProgram, TEMPLATES } from ".";

const seed = readFileSync(new URL("../../../../supabase/seed.sql", import.meta.url), "utf8");
const seedIds = new Set([...seed.matchAll(/'(0{8}-0{4}-4000-8000-\d{12})'/g)].map((m) => m[1]));

describe("program templates", () => {
  it("cover PPL, UL, PPLUL and Arnold with seeded exercises", () => {
    expect(TEMPLATES.map((t) => t.split)).toEqual(["PPL", "UL", "PPLUL", "Arnold"]);
    for (const t of TEMPLATES) {
      for (const day of t.days) for (const e of day.exercises) expect(seedIds.has(exerciseUuid(e.exercise))).toBe(true);
    }
  });
});

describe("parseProgram", () => {
  it("accepts a valid program and slugs its id", () => {
    const p = parseProgram(JSON.stringify({ name: "Video Split #2", days: [{ name: "Day 1", exercises: [{ exercise: 1, sets: 3, reps: [6, 10] }] }] }));
    expect(p.id).toBe("custom-video-split-2");
    expect(p.split).toBe("Custom");
  });

  it("rejects bad input with a useful message", () => {
    expect(() => parseProgram("{")).toThrow("valid JSON");
    expect(() => parseProgram(JSON.stringify({ name: "x", days: [{ name: "A", exercises: [{ exercise: 1, sets: 3, reps: [10, 6] }] }] }))).toThrow(
      "reps",
    );
  });
});
