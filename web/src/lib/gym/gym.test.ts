import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { TEMPLATES } from "../programs";
import { builtInId, GYMS, patternOf, substitutes } from ".";

const seedIds = new Set(
  [...readFileSync(new URL("../../../../supabase/seed.sql", import.meta.url), "utf8").matchAll(/'(0{8}-0{4}-4000-8000-\d{12})'/g)].map(
    (m) => m[1],
  ),
);

describe("gym profiles", () => {
  it("only references seeded exercises, each in one group", () => {
    for (const gym of GYMS) {
      const ids = gym.substitution_groups.flatMap((g) => g.exercises.map(builtInId));
      expect(ids.filter((id) => !seedIds.has(id))).toEqual([]);
      expect(new Set(ids).size).toBe(ids.length);
    }
  });

  it("only builds built-in programs from equipment the gym has", () => {
    const inGym = new Set(GYMS[0].substitution_groups.flatMap((g) => g.exercises.map(builtInId)));
    const missing = TEMPLATES.flatMap((t) =>
      t.days.flatMap((d) => d.exercises.filter((e) => !inGym.has(builtInId(Number(e.exercise)))).map((e) => `${t.id} ${d.name} ${e.exercise}`)),
    );
    expect(missing).toEqual([]);
  });

  it("suggests same-pattern swaps", () => {
    const crc = GYMS[0];
    expect(patternOf(crc, builtInId(8))).toBe("vertical_pull");
    expect(substitutes(crc, builtInId(8))).toContain(builtInId(38));
    expect(substitutes(crc, builtInId(8))).not.toContain(builtInId(8));
  });
});
