import fastFood from "../../../../shared/food/fast-food.json";
import restaurants from "../../../../shared/food/restaurants.json";
import snackBrands from "../../../../shared/food/snack-brands.json";
import staples from "../../../../shared/food/dining-staples.json";

export interface FoodItem {
  id: string;
  name: string;
  brand?: string | null;
  station?: string | null;
  serving: string;
  kcal: number;
  protein: number;
  carbs: number;
  fat: number;
}

const OFFICIAL = restaurants.items as FoodItem[];
const OFFICIAL_CHAINS = new Set(OFFICIAL.map((i) => i.brand));
/** Official chain menus (restaurants.json) replace the older USDA items (fast-food.json) for the same chain. */
export const FAST_FOOD: FoodItem[] = [...OFFICIAL, ...(fastFood.items as FoodItem[]).filter((i) => !OFFICIAL_CHAINS.has(i.brand))];
/** Restaurant names A–Z, with USDA's unbranded fast food last. */
export const RESTAURANTS = [...new Set(FAST_FOOD.map((f) => f.brand ?? "Generic"))].sort((a, b) =>
  a === "Generic" ? 1 : b === "Generic" ? -1 : a.localeCompare(b),
);

/** Snack and drink brands; each searches the foods databank with `q`. */
export interface SnackBrand {
  name: string;
  q: string;
  /** Text a product's name or brand must contain; defaults to `name`. */
  match?: string;
}

const squash = (s: string) =>
  s
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");

/** Search results that are really this brand (the search also matches lookalikes, e.g. "layer" for Lay's); all of them if none match. */
export function brandFoods(items: FoodItem[], brand: SnackBrand): FoodItem[] {
  const key = squash(brand.match ?? brand.name);
  const hits = items.filter((i) => squash(`${i.name} ${i.brand ?? ""}`).includes(key));
  return hits.length ? hits : items;
}

/** Drops rows that look identical: same name, brand, serving and calories. */
export function uniqueFoods(items: FoodItem[]): FoodItem[] {
  const seen = new Set<string>();
  return items.filter((i) => {
    const key = `${i.name}|${i.brand ?? ""}|${i.serving}|${Math.round(i.kcal)}`.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
export const SNACK_GROUPS = snackBrands.groups as { name: string; brands: SnackBrand[] }[];
export const STAPLES = staples.items as FoodItem[];
export const MEALS = ["breakfast", "lunch", "dinner", "snack"] as const;
export type Meal = (typeof MEALS)[number];

export const HALLS = [
  { id: "north-ave-dining-hall", name: "North Ave Dining Hall", meals: ["breakfast", "lunch", "dinner", "overnight"] },
  { id: "west-village", name: "West Village", meals: ["breakfast", "lunch", "dinner"] },
  { id: "brittain", name: "Brittain Dining Hall", meals: ["breakfast", "lunch", "dinner"] },
];

export const TIME_ZONE = "America/New_York";

/** YYYY-MM-DD in Atlanta time. */
/** `YYYY-MM-DD` in `timeZone` (Georgia Tech's by default, which dining-hall menus use). */
export function localDate(date: Date = new Date(), timeZone: string = TIME_ZONE): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone }).format(date);
}

export function currentMeal(date: Date = new Date()): Meal {
  const hour = Number(new Intl.DateTimeFormat("en-US", { timeZone: TIME_ZONE, hour: "numeric", hour12: false }).format(date)) % 24;
  return hour < 11 ? "breakfast" : hour < 16 ? "lunch" : "dinner";
}

interface NutrisliceWeek {
  days: {
    date: string;
    menu_items: {
      text?: string | null;
      is_station_header?: boolean;
      food?: {
        id: number;
        name: string;
        rounded_nutrition_info?: { calories?: number | null; g_protein?: number | null; g_carbs?: number | null; g_fat?: number | null } | null;
        serving_size_info?: { serving_size_amount?: string | null; serving_size_unit?: string | null } | null;
      } | null;
    }[];
  }[];
}

/** One day's items from a Nutrislice week, tagged with the station they're listed under (deduped per station). */
export function parseNutrislice(week: NutrisliceWeek, date: string): FoodItem[] {
  const day = week.days.find((d) => d.date === date);
  if (!day) return [];
  let station = "Menu";
  const seen = new Set<string>();
  const items: FoodItem[] = [];
  for (const item of day.menu_items) {
    if (item.is_station_header) {
      station = item.text ?? station;
      continue;
    }
    const food = item.food;
    if (!food || seen.has(`${station}|${food.name}`)) continue;
    seen.add(`${station}|${food.name}`);
    const n = food.rounded_nutrition_info ?? {};
    const serving = [food.serving_size_info?.serving_size_amount, food.serving_size_info?.serving_size_unit].filter(Boolean).join(" ");
    items.push({
      id: `ns-${food.id}-${station}`,
      name: food.name,
      station,
      serving: serving || "1 serving",
      kcal: n.calories ?? 0,
      protein: n.g_protein ?? 0,
      carbs: n.g_carbs ?? 0,
      fat: n.g_fat ?? 0,
    });
  }
  return items;
}

/** Georgia Tech Dining menu from Nutrislice (server-side: the API sends no CORS headers). */
export async function diningMenu(hall: string, meal: string, date: string): Promise<FoodItem[]> {
  const [y, m, d] = date.split("-");
  const url = `https://techdining.api.nutrislice.com/menu/api/weeks/school/${hall}/menu-type/${meal}/${y}/${m}/${d}/?format=json`;
  const res = await fetch(url, { next: { revalidate: 1800 } });
  if (!res.ok) throw new Error(`Nutrislice ${res.status}`);
  return parseNutrislice((await res.json()) as NutrisliceWeek, date);
}

export function groupBy(items: FoodItem[], key: (i: FoodItem) => string | null | undefined): [string, FoodItem[]][] {
  const groups = new Map<string, FoodItem[]>();
  for (const item of items) {
    const k = key(item) ?? "Other";
    groups.set(k, [...(groups.get(k) ?? []), item]);
  }
  return [...groups.entries()];
}

export interface LoggedFood {
  servings: number;
  kcal: number;
  protein: number;
  carbs: number;
  fat: number;
}

export function totals(logs: LoggedFood[]) {
  const sum = (k: "kcal" | "protein" | "carbs" | "fat") => Math.round(logs.reduce((t, l) => t + Number(l[k]) * Number(l.servings), 0));
  return { kcal: sum("kcal"), protein: sum("protein"), carbs: sum("carbs"), fat: sum("fat") };
}

/** Water is stored as entered, in US fl oz or ml; totals convert for display only. */
export type WaterUnit = "oz" | "ml";
export const ML_PER_OZ = 29.5735;
export const WATER_QUICK: Record<WaterUnit, number[]> = { oz: [8, 16.9, 20, 32], ml: [250, 500, 750, 1000] };

/** fl oz for lb users, ml for kg users. */
export const waterUnitFor = (weightUnit: "lb" | "kg"): WaterUnit => (weightUnit === "kg" ? "ml" : "oz");

/** Daily water goal in `unit`: about 35 ml per kg of body weight, plus half a litre on days you train. */
export function waterGoal(bodyWeightKg: number, trained: boolean, unit: WaterUnit): number {
  const ml = bodyWeightKg * 35 + (trained ? 500 : 0);
  return Math.round(unit === "ml" ? ml : ml / ML_PER_OZ);
}

export function waterTotal(logs: { amount: number; unit: string }[], unit: WaterUnit): number {
  const total = logs.reduce((t, l) => {
    const amount = Number(l.amount);
    if (l.unit === unit) return t + amount;
    return t + (unit === "ml" ? amount * ML_PER_OZ : amount / ML_PER_OZ);
  }, 0);
  return Math.round(total * 10) / 10;
}

export interface FoodRow {
  id: string;
  source: "usda" | "off" | "user";
  name: string;
  brand: string | null;
  serving: string;
  kcal: number;
  protein: number;
  carbs: number;
  fat: number;
}

export function fromRow(r: FoodRow): FoodItem {
  return {
    id: r.id,
    name: r.name,
    brand: r.brand,
    serving: r.serving,
    kcal: Number(r.kcal),
    protein: Number(r.protein),
    carbs: Number(r.carbs),
    fat: Number(r.fat),
  };
}

/** Barcodes are stored without leading zeros so UPC-A, EAN-13 and GTIN-14 forms of one code match. */
export function normalizeBarcode(code: string): string | null {
  const digits = code.replace(/\D/g, "").replace(/^0+/, "");
  return /^[0-9]{6,14}$/.test(digits) ? digits : null;
}

interface OffProduct {
  status?: number;
  product?: {
    product_name?: string;
    brands?: string;
    serving_size?: string;
    serving_quantity?: number | string;
    nutriments?: Record<string, number | string | undefined>;
  };
}

/** Open Food Facts product → per-serving macros (falls back to per 100 g when no serving is given). */
export function parseOpenFoodFacts(json: OffProduct, barcode: string) {
  const p = json.product;
  if (!p?.product_name?.trim()) return null;
  const n = p.nutriments ?? {};
  const grams = Number(p.serving_quantity) > 0 ? Number(p.serving_quantity) : null;
  const value = (key: string) => {
    const serving = Number(n[`${key}_serving`]);
    if (grams && Number.isFinite(serving) && n[`${key}_serving`] !== undefined) return serving;
    const per100 = Number(n[`${key}_100g`]);
    return Number.isFinite(per100) ? (per100 * (grams ?? 100)) / 100 : 0;
  };
  const r1 = (x: number) => Math.round(Math.max(0, x) * 10) / 10;
  return {
    source: "off" as const,
    source_id: barcode,
    barcode,
    name: p.product_name.trim().slice(0, 200),
    brand: p.brands?.split(",")[0]?.trim().slice(0, 120) || null,
    serving: (grams ? p.serving_size?.trim() || `${grams} g` : "100 g").slice(0, 120),
    serving_g: grams,
    kcal: r1(value("energy-kcal")),
    protein: r1(value("proteins")),
    carbs: r1(value("carbohydrates")),
    fat: r1(value("fat")),
  };
}
