import { describe, expect, it } from "vitest";
import { CAMPUS, CAMPUS_MENUS, FAST_FOOD, HALLS, STAPLES, placeMenu, waterRemoval, currentMeal, localDate, parseNutrislice, totals, waterGoal, waterTotal, waterUnitFor, brandFoods, uniqueFoods, type FoodItem } from ".";

const food = (name: string, brand: string | null = null, kcal = 100): FoodItem => ({ id: name, name, brand, serving: "1 bar", kcal, protein: 1, carbs: 1, fat: 1 });

describe("snack brands", () => {
  it("keeps only the brand's products", () => {
    const items = [food("Candies, MARS SNACKFOOD US, M&M's Milk Chocolate"), food("Candies, MARS SNACKFOOD US, MILKY WAY Bar"), food("Seven-layer salad")];
    expect(brandFoods(items, { name: "M&M's", q: "m&m candies" }).map((i) => i.name)).toEqual(["Candies, MARS SNACKFOOD US, M&M's Milk Chocolate"]);
    expect(brandFoods([food("Seven-layer salad"), food("Classic Potato Chips", "Lay's")], { name: "Lay's", q: "lay's" })).toHaveLength(1);
    expect(brandFoods([food("Sweet Chili Pistachios", "Wonderful")], { name: "Wonderful Pistachios", q: "x", match: "wonderful" })).toHaveLength(1);
    expect(brandFoods([food("Unrelated")], { name: "Doritos", q: "doritos" })).toHaveLength(1);
  });

  it("drops identical rows", () => {
    expect(uniqueFoods([food("Dr Pepper, Soda", "Dr Pepper"), food("Dr Pepper, Soda", "Dr Pepper"), food("Dr Pepper, Soda", "Dr Pepper", 150)])).toHaveLength(2);
  });
});

describe("georgia tech", () => {
  it("links every place to a dining hall, a menu, or a note on how to log it", () => {
    expect(new Set(CAMPUS.map((p) => `${p.area}|${p.name}`)).size).toBe(CAMPUS.length);
    for (const p of CAMPUS) {
      if (p.hall) expect(HALLS.map((h) => h.id), p.name).toContain(p.hall);
      else if (p.menu) expect(placeMenu(p.menu).length, p.name).toBeGreaterThan(0);
    }
    expect(CAMPUS.filter((p) => p.hall)).toHaveLength(HALLS.length);
  });

  it("ships campus menus with sane macros and unique ids", () => {
    const ids = new Set(FAST_FOOD.map((i) => i.id));
    for (const i of CAMPUS_MENUS) {
      expect(ids.has(i.id), i.id).toBe(false);
      ids.add(i.id);
      expect(i.kcal, i.id).toBeGreaterThan(0);
      if (i.kcal < 20) continue; // black coffee and tea: a few kcal, so rounding swamps the ratio
      const fromMacros = 4 * i.protein + 4 * i.carbs + 9 * i.fat;
      expect(Math.abs(fromMacros - i.kcal) / i.kcal, i.id).toBeLessThan(0.25);
    }
  });
});

describe("water", () => {
  it("sums mixed units in the display unit without changing stored amounts", () => {
    const logs = [{ amount: 16.9, unit: "oz" }, { amount: 500, unit: "ml" }];
    expect(waterTotal(logs, "oz")).toBe(33.8);
    expect(waterTotal(logs, "ml")).toBe(999.8);
    expect(waterUnitFor("lb")).toBe("oz");
    expect(waterUnitFor("kg")).toBe("ml");
  });

  it("removes water newest first, deleting whole logs and shortening the last", () => {
    const logs = [
      { id: "c", amount: 8, unit: "oz" },
      { id: "b", amount: 500, unit: "ml" },
      { id: "a", amount: 16.9, unit: "oz" },
    ];
    expect(waterRemoval(logs, 8, "oz")).toEqual({ remove: ["c"], shorten: [] });
    // 8 oz + 500 ml (16.9 oz) = 24.9 oz; 30 oz takes both and 5.1 oz off the oldest.
    expect(waterRemoval(logs, 30, "oz")).toEqual({ remove: ["c", "b"], shorten: [{ id: "a", amount: 11.8 }] });
    // 4 oz off a 500 ml log leaves it in ml.
    expect(waterRemoval(logs.slice(1), 4, "oz")).toEqual({ remove: [], shorten: [{ id: "b", amount: 381.7 }] });
    expect(waterRemoval(logs, 1000, "oz").remove).toEqual(["c", "b", "a"]);
  });

  it("sets the daily goal from body weight, plus half a litre on training days", () => {
    expect(waterGoal(88.2, false, "oz")).toBe(104);
    expect(waterGoal(88.2, true, "oz")).toBe(121);
    expect(waterGoal(80, true, "ml")).toBe(3300);
  });
});

const week = {
  days: [
    { date: "2026-10-27", menu_items: [] },
    {
      date: "2026-10-28",
      menu_items: [
        { text: "Grill Station", is_station_header: true },
        { food: { id: 1, name: "Grilled Chicken Breast", rounded_nutrition_info: { calories: 157, g_protein: 30, g_carbs: 0, g_fat: 3.2 }, serving_size_info: { serving_size_amount: "1", serving_size_unit: "breast" } } },
        { food: { id: 1, name: "Grilled Chicken Breast", rounded_nutrition_info: { calories: 157 } } },
        { text: "Soup", is_station_header: true },
        { food: { id: 2, name: "Lentil Soup", rounded_nutrition_info: { calories: null }, serving_size_info: null } },
      ],
    },
  ],
};

describe("nutrislice", () => {
  it("tags stations, dedupes and fills missing nutrition", () => {
    const items = parseNutrislice(week, "2026-10-28");
    expect(items.map((i) => [i.station, i.name, i.serving, i.kcal, i.protein])).toEqual([
      ["Grill Station", "Grilled Chicken Breast", "1 breast", 157, 30],
      ["Soup", "Lentil Soup", "1 serving", 0, 0],
    ]);
    expect(parseNutrislice(week, "2026-10-29")).toEqual([]);
  });
});

describe("food helpers", () => {
  it("multiplies by servings", () => {
    expect(totals([{ servings: 2, kcal: 100, protein: 10, carbs: 5, fat: 1.5 }, { servings: 0.5, kcal: 200, protein: 20, carbs: 0, fat: 0 }])).toEqual({ kcal: 300, protein: 30, carbs: 10, fat: 3 });
  });
  it("uses Atlanta time", () => {
    expect(localDate(new Date("2026-10-29T02:00:00Z"))).toBe("2026-10-28");
    expect(currentMeal(new Date("2026-10-28T12:00:00Z"))).toBe("breakfast");
    expect(currentMeal(new Date("2026-10-28T17:00:00Z"))).toBe("lunch");
  });
  it("ships the bundled libraries", () => {
    expect(FAST_FOOD.length).toBeGreaterThan(200);
    expect(STAPLES.some((s) => s.station === "Cereal")).toBe(true);
    expect(STAPLES.some((s) => s.station === "Bakery")).toBe(true);
  });
});

describe("databank", () => {
  it("normalizes barcodes", async () => {
    const { normalizeBarcode } = await import(".");
    expect(normalizeBarcode("00818290011787")).toBe("818290011787");
    expect(normalizeBarcode(" 0818290-011787 ")).toBe("818290011787");
    expect(normalizeBarcode("123")).toBeNull();
  });

  it("parses Open Food Facts per serving, else per 100 g", async () => {
    const { parseOpenFoodFacts } = await import(".");
    const served = parseOpenFoodFacts(
      { product: { product_name: "Greek Yogurt", brands: "Chobani, Inc", serving_size: "1 cup (170 g)", serving_quantity: 170, nutriments: { "energy-kcal_serving": 100, proteins_serving: 16, carbohydrates_100g: 3.5, fat_100g: 0 } } },
      "818290011787",
    );
    expect(served).toMatchObject({ name: "Greek Yogurt", brand: "Chobani", serving: "1 cup (170 g)", kcal: 100, protein: 16, carbs: 6, fat: 0 });
    const per100 = parseOpenFoodFacts({ product: { product_name: "Spread", nutriments: { "energy-kcal_100g": 539, proteins_100g: 6.3 } } }, "3017624010701");
    expect(per100).toMatchObject({ serving: "100 g", serving_g: null, kcal: 539, protein: 6.3 });
    expect(parseOpenFoodFacts({ status: 0 }, "1234567")).toBeNull();
  });
});
