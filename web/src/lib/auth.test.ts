import { describe, expect, it } from "vitest";
import { safeNext } from "./auth";

describe("safeNext", () => {
  it("only allows same-site paths", () => {
    expect(safeNext("/settings?welcome=1")).toBe("/settings?welcome=1");
    expect(safeNext("https://evil.example")).toBe("/");
    expect(safeNext("//evil.example")).toBe("/");
    expect(safeNext("/\\evil.example")).toBe("/");
    expect(safeNext(null)).toBe("/");
  });
});
