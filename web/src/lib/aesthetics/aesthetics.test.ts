import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { bodyFatEstimate, bodyPlan, planStartWeight, muscleStatus, navyBodyFatFemale, navyBodyFatMale, recommendations, rfmFemale, rfmMale, shoulderTarget, waistBand, waistToHeight, waistToHip } from ".";

const fixtures = JSON.parse(readFileSync(new URL("../../../../shared/fixtures/aesthetics-cases.json", import.meta.url), "utf8"));

describe("shared aesthetics fixtures", () => {
  it.each(fixtures.navy_male as { name: string; heightCm: number; waistCm: number; neckCm: number; bodyFatPct: number; waistToHeight: number }[])(
    "$name",
    (c) => {
      expect(navyBodyFatMale(c.heightCm, c.waistCm, c.neckCm)).toBe(c.bodyFatPct);
      expect(waistToHeight(c.waistCm, c.heightCm)).toBe(c.waistToHeight);
    },
  );
});

describe("shared female body-fat fixtures", () => {
  it.each(fixtures.navy_female as { name: string; heightCm: number; waistCm: number; hipsCm: number; neckCm: number; bodyFatPct: number }[])(
    "navy $name",
    (c) => {
      expect(navyBodyFatFemale(c.heightCm, c.waistCm, c.hipsCm, c.neckCm)).toBe(c.bodyFatPct);
      expect(bodyFatEstimate("female", c.heightCm, c.waistCm, c.neckCm, c.hipsCm)).toBe(c.bodyFatPct);
    },
  );
  it.each(fixtures.rfm_female as { name: string; heightCm: number; waistCm: number; bodyFatPct: number }[])("rfm $name", (c) => {
    expect(rfmFemale(c.heightCm, c.waistCm)).toBe(c.bodyFatPct);
    expect(bodyFatEstimate("female", c.heightCm, c.waistCm)).toBe(c.bodyFatPct);
  });
});

describe("shared RFM fixtures", () => {
  it.each(fixtures.rfm_male as { name: string; heightCm: number; waistCm: number; hipsCm: number; bodyFatPct: number; waistToHip: number; shoulderTarget: number }[])(
    "$name",
    (c) => {
      expect(rfmMale(c.heightCm, c.waistCm)).toBe(c.bodyFatPct);
      expect(waistToHip(c.waistCm, c.hipsCm)).toBe(c.waistToHip);
      expect(shoulderTarget(c.waistCm)).toBe(c.shoulderTarget);
    },
  );
  it("rejects missing lengths", () => {
    expect(rfmMale(180, 0)).toBeNull();
    expect(waistToHip(80, 0)).toBeNull();
  });
});

describe("shared body plan fixtures", () => {
  it.each(
    fixtures.body_plan as { name: string; bodyWeight: number; unit: "lb" | "kg"; bodyFatPct: number; goalPct?: number; startWeight?: number; sex?: "male" | "female"; expected: object }[],
  )("$name", (c) => expect(bodyPlan(c.bodyWeight, c.unit, c.bodyFatPct, c.goalPct, c.startWeight, c.sex)).toEqual(c.expected));
  it("phase tip replaces the waist tip", () => {
    expect(recommendations("lean", [], "cut")[0]).toContain("Fat loss comes first");
  });
});

describe("plan start weight", () => {
  const row = (measured_at: string, body_weight: number | null, body_fat_pct: number | null, unit = "lb") => ({ measured_at, body_weight, unit, body_fat_pct });
  it("uses the last weigh-in up to a day after the latest body-fat entry", () => {
    const rows = [
      row("2026-03-20T12:00:00Z", 190, null),
      row("2026-03-02T09:00:00Z", null, 22),
      row("2026-03-01T18:00:00Z", 205, 25),
      row("2026-02-20T12:00:00Z", 207, null),
    ];
    expect(planStartWeight(rows, "lb")).toBe(205);
  });
  it("falls back to the first weigh-in after it, converts units, and needs a body-fat entry", () => {
    expect(planStartWeight([row("2026-10-01T00:00:00Z", null, 20), row("2026-10-05T00:00:00Z", 90, null, "kg")], "lb")).toBeCloseTo(198.4, 1);
    expect(planStartWeight([row("2026-10-05T00:00:00Z", 90, null, "kg")], "lb")).toBeNull();
  });
});

describe("priorities", () => {
  it("flags midsection fat and under-trained V-taper muscles", () => {
    expect(waistBand(0.55)).toBe("elevated");
    expect(navyBodyFatMale(180, 40, 40)).toBeNull();
    const statuses = muscleStatus({ side_delts: 6, back: 14, quads: 0 });
    expect(statuses.find((s) => s.muscle === "side_delts")?.status).toBe("under");
    expect(statuses.find((s) => s.muscle === "back")?.status).toBe("on");
    const tips = recommendations("elevated", statuses);
    expect(tips[0]).toContain("0.5");
    expect(tips.join(" ")).toContain("side delts");
    expect(tips.join(" ")).toContain("quads");
  });
});
