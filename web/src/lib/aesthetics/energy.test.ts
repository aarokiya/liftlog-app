import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { baseTargets, bmr, dailyTargets, formulaMaintenance, learnedMaintenance, type BaseTargets, type Phase, type Targets } from ".";

const fixtures = JSON.parse(readFileSync(new URL("../../../../shared/fixtures/energy-cases.json", import.meta.url), "utf8"));

// Fixture day keys are strings.
const byDay = <T>(o: Record<string, T>): Record<number, T> => Object.fromEntries(Object.entries(o).map(([d, v]) => [Number(d), v]));

describe("shared maintenance fixtures", () => {
  it.each(fixtures.maintenance as { name: string; leanMassKg: number; bmr: number; formula: number }[])("$name", (c) => {
    expect(bmr(c.leanMassKg)).toBeCloseTo(c.bmr, 6);
    expect(formulaMaintenance(c.leanMassKg)).toBe(c.formula);
  });
});

describe("shared learned maintenance fixtures", () => {
  it.each(fixtures.learned as { name: string; formula: number; today: number; intake: Record<string, number>; weights: [number, number][]; expected: number }[])(
    "$name",
    (c) => {
      const weights = c.weights.map(([day, kg]) => ({ day, kg }));
      expect(learnedMaintenance(c.formula, byDay(c.intake), weights, c.today)).toBe(c.expected);
    },
  );
});

describe("shared base target fixtures", () => {
  it.each(
    fixtures.base as {
      name: string;
      plan: { phase: Phase; leanMass: number; weeklyLow: number; weeklyHigh: number; proteinG: number };
      bodyWeight: number;
      unit: "lb" | "kg";
      maintenance: number;
      sex: "male" | "female";
      expected: BaseTargets;
    }[],
  )("$name", (c) => expect(baseTargets(c.plan, c.bodyWeight, c.unit, c.maintenance, c.sex)).toEqual(c.expected));
});

describe("shared daily target fixtures", () => {
  it.each(
    fixtures.daily as { name: string; base: BaseTargets; from: number; through: number; intake: Record<string, { kcal: number; fat: number }>; expected: Record<string, Targets> }[],
  )("$name", (c) => expect(dailyTargets(c.base, byDay(c.intake), c.from, c.through)).toEqual(byDay(c.expected)));
});
