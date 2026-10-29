import { describe, expect, it } from "vitest";
import { fromZonedInput, toZonedInput, validTimeZone } from ".";

describe("zoned wall-clock times", () => {
  it("shows an evening workout on its local day", () => {
    expect(toZonedInput("2026-10-24T00:02:00Z", "America/New_York")).toBe("2026-10-23T20:02");
    expect(toZonedInput("2026-10-24T00:02:00Z", "UTC")).toBe("2026-10-24T00:02");
  });

  it("round-trips through the input, including across daylight saving", () => {
    for (const iso of ["2026-10-24T00:02:00.000Z", "2026-03-08T12:30:00.000Z", "2026-11-01T05:30:00.000Z", "2026-07-01T23:59:00.000Z"]) {
      expect(fromZonedInput(toZonedInput(iso, "America/New_York"), "America/New_York").toISOString()).toBe(iso);
    }
    expect(fromZonedInput("2026-10-23T20:02", "America/New_York").toISOString()).toBe("2026-10-24T00:02:00.000Z");
    expect(fromZonedInput("2026-06-01T09:00", "Asia/Kolkata").toISOString()).toBe("2026-06-01T03:30:00.000Z");
  });

  it("rejects unknown zones", () => {
    expect(validTimeZone("America/New_York")).toBe("America/New_York");
    expect(validTimeZone("Not/AZone")).toBeNull();
    expect(validTimeZone(undefined)).toBeNull();
  });
});
