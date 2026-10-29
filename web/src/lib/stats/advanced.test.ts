import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { acwr, balance, density, dots, growth, muscleRecency, plateau, wilks } from "./advanced";

const fx = JSON.parse(readFileSync(new URL("../../../../shared/fixtures/advanced-cases.json", import.meta.url), "utf8"));

describe("shared advanced fixtures", () => {
  it("scores", () => {
    for (const c of fx.scores) {
      expect(wilks(c.totalKg, c.bodyKg)).toBe(c.wilks);
      expect(dots(c.totalKg, c.bodyKg)).toBe(c.dots);
    }
  });
  it("balance", () => {
    for (const c of fx.balance) expect(balance(c.muscleSets)).toEqual(c.expected);
  });
  it("acwr", () => {
    for (const c of fx.acwr) expect(acwr(c.loads, c.today)).toBe(c.expected);
  });
  it("plateau", () => {
    for (const c of fx.plateau) expect(plateau(c.points)).toEqual(c.expected);
  });
  it("growth", () => {
    for (const c of fx.growth) expect(growth(c.points)).toEqual(c.expected);
    expect(growth([])).toBeNull();
  });
  it("small helpers", () => {
    expect(muscleRecency({ chest: 10, quads: 3 }, 12)).toEqual({ chest: 2, quads: 9 });
    expect(density(5800, 58)).toBe(100);
    expect(density(100, 0)).toBeNull();
    expect(plateau([{ day: 0, value: 1 }])).toBeNull();
  });
});
