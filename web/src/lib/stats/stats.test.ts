import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  bestE1RMPerSession,
  convert,
  dayNumber,
  estimateOneRepMax,
  linearRegression,
  muscleSets,
  plates,
  repMaxes,
  volumeLoad,
  weekNumber,
  weeklyStreak,
} from ".";

// The same golden cases run in ios/Packages/LiftKit/Tests.
const fixtures = JSON.parse(readFileSync(resolve(__dirname, "../../../../shared/fixtures/stats-cases.json"), "utf8"));
const close = (a: number, b: number) => expect(a).toBeCloseTo(b, 6);

describe("shared stats fixtures", () => {
  it("converts units", () => {
    for (const c of fixtures.conversion) close(convert(c.value, c.from, c.to), c.expected);
  });

  it("estimates 1RM", () => {
    for (const c of fixtures.e1rm) {
      const got = estimateOneRepMax(c.weight, c.reps, c.formula);
      if (c.expected === null) expect(got).toBeNull();
      else close(got!, c.expected);
    }
  });

  it("computes volume", () => {
    for (const c of fixtures.volume) close(volumeLoad(c.sets, c.unit), c.expected);
  });

  it("computes rep maxes", () => {
    for (const c of fixtures.repMaxes) {
      const got = repMaxes(c.sets, c.unit);
      expect(Object.keys(got).sort()).toEqual(Object.keys(c.expected).sort());
      for (const [k, v] of Object.entries(c.expected)) close(got[Number(k)], v as number);
    }
  });

  it("computes best e1RM per session", () => {
    for (const c of fixtures.bestE1RMPerSession) {
      const got = bestE1RMPerSession(c.sets, c.unit, c.formula);
      expect(got.map((g) => g.sessionId)).toEqual(c.expected.map((e: { sessionId: string }) => e.sessionId));
      got.forEach((g, i) => close(g.value, c.expected[i].value));
    }
  });

  it("counts muscle sets", () => {
    for (const c of fixtures.muscleSets) expect(muscleSets(c.sets, c.exercises)).toEqual(c.expected);
  });

  it("calculates plates", () => {
    for (const c of fixtures.plates) {
      const got = plates(c.target, c.bar, c.available);
      expect(got.perSide).toEqual(c.expected.perSide);
      close(got.remainder, c.expected.remainder);
    }
  });

  it("computes weekly streaks", () => {
    for (const c of fixtures.streaks) expect(weeklyStreak(c.dates, c.target, c.asOf)).toEqual(c.expected);
  });

  it("fits linear regression", () => {
    for (const c of fixtures.regression) {
      const got = linearRegression(c.points);
      if (c.expected === null) expect(got).toBeNull();
      else {
        close(got!.slope, c.expected.slope);
        close(got!.intercept, c.expected.intercept);
      }
    }
  });

  it("matches Swift date math", () => {
    expect(dayNumber("1970-01-01")).toBe(0);
    expect(dayNumber("2000-03-01")).toBe(11017);
    expect(weekNumber("1970-01-05")).toBe(1);
    expect(weekNumber("1970-01-04")).toBe(0);
  });
});
