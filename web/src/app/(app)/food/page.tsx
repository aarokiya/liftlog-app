import Link from "next/link";
import { baseTargets, bodyPlan, dailyTargets, formulaMaintenance, learnedMaintenance, planStartWeight } from "@/lib/aesthetics";
import { CAMPUS, CAMPUS_AREAS, FAST_FOOD, HALLS, RESTAURANTS, SNACK_GROUPS, STAPLES, WATER_QUICK, currentMeal, diningMenu, fromRow, groupBy, localDate, normalizeBarcode, parseOpenFoodFacts, totals, waterGoal, waterTotal, waterUnitFor, brandFoods, uniqueFoods, placeMenu, type FoodItem, type FoodRow } from "@/lib/food";
import { convert, dayNumber } from "@/lib/stats";
import { getProfile } from "@/lib/data";
import { requireUser } from "@/lib/supabase/server";
import { userTimeZone } from "@/lib/time/server";
import { createFood, deleteFood, deleteWater, logFood, logWater, removeWater } from "./actions";

type Params = { tab?: string; hall?: string; meal?: string; q?: string; brand?: string; barcode?: string; snack?: string; area?: string; place?: string; water?: string };

function FoodRows({ items, source, place, meal }: { items: FoodItem[]; source: string; place?: string; meal: string }) {
  return (
    <ul className="divide-y divide-border">
      {items.map((item) => (
        <li key={item.id}>
          <form action={logFood} className="flex flex-wrap items-center gap-2 py-2 text-sm">
            <input type="hidden" name="name" value={item.name} />
            <input type="hidden" name="serving" value={item.serving} />
            <input type="hidden" name="source" value={source} />
            <input type="hidden" name="place" value={place ?? item.brand ?? ""} />
            <input type="hidden" name="meal" value={meal} />
            {(["kcal", "protein", "carbs", "fat"] as const).map((k) => (
              <input key={k} type="hidden" name={k} value={item[k]} />
            ))}
            <div className="min-w-0 flex-1">
              <div className="truncate">{item.name}</div>
              <div className="text-xs text-muted">
                {item.serving} · {item.estimated ? "≈ " : ""}
                {Math.round(item.kcal)} kcal · {item.protein} g protein
              </div>
            </div>
            <input name="servings" type="number" step="0.5" min="0.5" defaultValue={1} className="input w-16" aria-label="Servings" />
            <button className="btn">Log</button>
          </form>
        </li>
      ))}
    </ul>
  );
}

/** Log a food by its macros; `place` prefills "Where". */
function CustomFoodForm({ place, open }: { place?: string; open?: boolean }) {
  return (
    <details open={open}>
      <summary className="cursor-pointer text-sm font-medium">Custom food (enter macros)</summary>
      <form action={logFood} className="mt-2 grid grid-cols-2 gap-2 text-sm md:grid-cols-4">
        <input type="hidden" name="source" value="custom" />
        <input type="hidden" name="meal" value={currentMeal()} />
        <input name="name" required placeholder="What did you eat?" className="input col-span-2" />
        <input name="place" defaultValue={place} placeholder="Where (optional)" className="input col-span-2" />
        <input name="kcal" type="number" step="1" placeholder="Calories" className="input" />
        <input name="protein" type="number" step="0.1" placeholder="Protein g" className="input" />
        <input name="carbs" type="number" step="0.1" placeholder="Carbs g" className="input" />
        <input name="fat" type="number" step="0.1" placeholder="Fat g" className="input" />
        <button className="btn col-span-2 md:col-span-4">Log</button>
      </form>
    </details>
  );
}

const AREA_NOTES: Record<string, string> = {
  "Food trucks": "Trucks rotate on Tech Green; dining.gatech.edu has today's schedule.",
  "Community Market": "Pop-up vendors on Tech Walkway.",
  "Near campus": "Off campus, nearest first.",
};

/** Each menu brand and the place it's logged under: the first one serving it, on campus before nearby. */
const PLACE_BY_MENU = new Map<string, (typeof CAMPUS)[number]>();
for (const p of CAMPUS) if (p.menu && !PLACE_BY_MENU.has(p.menu)) PLACE_BY_MENU.set(p.menu, p);
const CAMPUS_ITEMS = [...PLACE_BY_MENU.keys()].sort().flatMap(placeMenu);

export default async function FoodPage({ searchParams }: { searchParams: Promise<Params> }) {
  const params = await searchParams;
  const { supabase, user } = await requireUser();
  const profile = await getProfile(supabase, user.id);
  const unit = profile.default_unit;
  const tz = await userTimeZone();
  const today = localDate(new Date(), tz);
  const gatech = profile.campus === "gatech";
  const tab = params.tab === "outside" || params.tab === "search" ? params.tab : gatech ? "dining" : "outside";
  const hall = HALLS.find((h) => h.id === params.hall);
  const place = tab === "dining" && !hall ? CAMPUS.find((p) => !p.hall && p.name === params.place && (!params.area || p.area === params.area)) : undefined;
  const placeItems = place?.menu ? placeMenu(place.menu) : [];
  const placeMatch = (p: (typeof CAMPUS)[number]) => q.split(/\s+/).every((w) => `${p.name} ${p.kind ?? ""}`.toLowerCase().includes(w));
  const meal = params.meal ?? currentMeal();
  const q = (params.q ?? "").trim().toLowerCase();
  // Every word of the search appears in the name or brand, in any order.
  const match = (i: FoodItem) => q.split(/\s+/).every((w) => `${i.brand ?? ""} ${i.name}`.toLowerCase().includes(w));

  const since = new Date(Date.now() - 36 * 3600 * 1000).toISOString();
  // 34 local days of intake (plus a day of slack for the time zone) for learned maintenance and carryover.
  const intakeSince = new Date(Date.now() - 35 * 86_400_000).toISOString();
  const [{ data: logRows }, { data: metrics }, { data: waterRows }, { data: workoutRows }, { data: intakeRows }] = await Promise.all([
    supabase.from("food_logs").select("id, eaten_at, meal, source, place, name, servings, kcal, protein, carbs, fat").is("deleted_at", null).gte("eaten_at", since).order("eaten_at", { ascending: false }),
    supabase.from("body_metrics").select("measured_at, body_weight, unit, body_fat_pct").is("deleted_at", null).order("measured_at", { ascending: false }).limit(200),
    supabase.from("water_logs").select("id, drank_at, amount, unit").is("deleted_at", null).gte("drank_at", since).order("drank_at", { ascending: false }),
    supabase.from("workouts").select("started_at").is("deleted_at", null).gte("started_at", since),
    // Newest first, so if the row cap ever bites it drops the oldest days rather than the recent carryover.
    supabase.from("food_logs").select("eaten_at, servings, kcal, fat").is("deleted_at", null).gte("eaten_at", intakeSince).order("eaten_at", { ascending: false }),
  ]);
  const logs = (logRows ?? []).filter((l) => localDate(new Date(l.eaten_at), tz) === today);
  const sum = totals(logs);
  const water = (waterRows ?? []).filter((l) => localDate(new Date(l.drank_at), tz) === today);
  const waterUnit = waterUnitFor(unit);
  const w = (metrics ?? []).find((m) => m.body_weight !== null);
  const bf = (metrics ?? []).find((m) => m.body_fat_pct !== null)?.body_fat_pct;
  const sex = profile.sex;
  const bodyWeight = w ? convert(Number(w.body_weight), w.unit === "kg" ? "kg" : "lb", unit) : null;
  const plan = sex && bodyWeight !== null && bf ? bodyPlan(bodyWeight, unit, Number(bf), undefined, planStartWeight(metrics ?? [], unit) ?? undefined, sex) : null;

  // Daily targets: maintenance from the formula, learned from logs and weigh-ins once there are enough, then the plan's
  // deficit or surplus, adjusted for the last 3 days. Only food logged in LiftLog counts: Apple Health stays on the phone.
  const todayNum = dayNumber(today);
  const intake: Record<number, { kcal: number; fat: number }> = {};
  for (const l of [...(intakeRows ?? [])].reverse()) {
    const d = dayNumber(localDate(new Date(l.eaten_at), tz));
    if (d < todayNum - 33) continue;
    intake[d] ??= { kcal: 0, fat: 0 };
    intake[d].kcal += Number(l.kcal) * Number(l.servings);
    intake[d].fat += Number(l.fat) * Number(l.servings);
  }
  // Every weigh-in in kg on its local day, oldest first (as on iOS).
  const weights = [...(metrics ?? [])]
    .reverse()
    .filter((m) => m.body_weight !== null)
    .map((m) => ({ day: dayNumber(localDate(new Date(m.measured_at), tz)), kg: convert(Number(m.body_weight), m.unit === "kg" ? "kg" : "lb", "kg") }));
  const formula = plan ? formulaMaintenance(convert(plan.leanMass, unit, "kg")) : null;
  const maintenance = formula !== null ? learnedMaintenance(formula, Object.fromEntries(Object.entries(intake).map(([d, i]) => [d, i.kcal])), weights, todayNum) : null;
  const targets =
    plan && sex && bodyWeight !== null && maintenance !== null
      ? dailyTargets(baseTargets(plan, bodyWeight, unit, maintenance, sex), intake, todayNum - 33, todayNum)[todayNum]
      : null;
  const needs = [!sex && "your sex", !w && "a body weight", !bf && "a body-fat %"].filter((s) => s !== false);
  const missing = needs.length > 1 ? `${needs.slice(0, -1).join(", ")} and ${needs.at(-1)}` : needs[0];
  // Protein is a minimum. Calories, carbs and fat are on target within 10% and over past that; under is fine mid-day.
  const tone = (value: number, target: number | null, atLeast: boolean) =>
    target === null ? "" : atLeast ? (value >= target ? "text-green-500" : "text-red-500") : value > target * 1.1 ? "text-red-500" : value >= target * 0.9 ? "text-green-500" : "";
  const trainedToday = (workoutRows ?? []).some((r) => localDate(new Date(r.started_at), tz) === today);
  const goalWater = w ? waterGoal(convert(Number(w.body_weight), w.unit === "kg" ? "kg" : "lb", "kg"), trainedToday, waterUnit) : null;
  const waterSoFar = waterTotal(water, waterUnit);
  const waterHit = goalWater !== null && waterSoFar >= goalWater;
  // The water buttons take water away instead (for water logged by mistake).
  const removingWater = params.water === "remove";

  let menu: FoodItem[] = [];
  let menuError = false;
  if (hall) {
    try {
      menu = await diningMenu(hall.id, meal, localDate());
    } catch {
      menuError = true;
    }
  }
  let results: FoodItem[] = [];
  let barcodeMissing = false;
  if (tab === "search") {
    const code = params.barcode ? normalizeBarcode(params.barcode) : null;
    if (code) {
      const { data } = await supabase.from("foods").select("id, source, name, brand, serving, kcal, protein, carbs, fat").eq("barcode", code).limit(5);
      results = uniqueFoods(((data ?? []) as FoodRow[]).map(fromRow));
      if (!results.length) {
        const res = await fetch(`https://world.openfoodfacts.org/api/v2/product/${code}.json?fields=product_name,brands,serving_size,serving_quantity,nutriments`, {
          headers: { "User-Agent": "LiftLog/1.0 (https://github.com/aarokiya/liftlog-app)" },
        }).catch(() => null);
        const off = res?.ok ? parseOpenFoodFacts(await res.json(), code) : null;
        if (off) {
          // Saved as this user's own food (visible only to them), so the next scan is local.
          const { data: saved } = await supabase.from("foods").insert({ ...off, source: "user", source_id: null, created_by: user.id }).select("id, source, name, brand, serving, kcal, protein, carbs, fat").single();
          results = saved ? [fromRow(saved as FoodRow)] : [];
        }
      }
      barcodeMissing = !results.length;
    } else if (q) {
      const { data } = await supabase.rpc("search_foods", { q, max_rows: 60 });
      results = uniqueFoods(((data ?? []) as FoodRow[]).map(fromRow));
    }
  }
  const restaurantHits = tab === "outside" ? FAST_FOOD.filter((f) => match(f) && (!params.brand || f.brand === params.brand)) : [];
  // Outside food: a snack brand, or a search that also covers packaged foods in the databank.
  const snack = SNACK_GROUPS.flatMap((g) => g.brands).find((b) => b.name === params.snack);
  let packaged: FoodItem[] = [];
  if (tab === "outside" && (snack || q)) {
    const { data } = await supabase.rpc("search_foods", { q: snack?.q ?? q, max_rows: 60 });
    const rows = uniqueFoods(((data ?? []) as FoodRow[]).map(fromRow));
    packaged = snack ? brandFoods(rows, snack) : rows;
  }
  const link = (p: Params) => `/food?${new URLSearchParams(Object.entries(p).filter(([, v]) => v) as [string, string][])}`;
  const chip = (active: boolean) => `rounded-full border border-border px-3 py-1 text-sm ${active ? "bg-accent-soft font-medium text-accent" : "text-muted"}`;

  return (
    <div className="grid gap-4">
      <h1 className="text-2xl font-semibold">Food</h1>
      <section className="card grid grid-cols-4 gap-3 text-center">
        {(
          [
            ["kcal", sum.kcal, targets?.kcal ?? null, false],
            ["protein (g)", sum.protein, targets?.protein ?? null, true],
            ["carbs (g)", sum.carbs, targets?.carbs ?? null, false],
            ["fat (g)", sum.fat, targets?.fat ?? null, false],
          ] as const
        ).map(([label, value, target, atLeast]) => (
          <div key={label}>
            <div className={`text-xl font-semibold tabular-nums ${tone(value, target, atLeast)}`}>{value}</div>
            <div className="text-xs text-muted">{target !== null ? `${label} / ${target}` : label}</div>
          </div>
        ))}
        <p className="col-span-4 text-xs text-muted">
          {targets && maintenance !== null ? (
            <>
              Maintenance ≈ {maintenance} kcal ({maintenance !== formula ? "learned from your logs" : "estimated"}). Targets adjust for the last 3 days of food
              logged in LiftLog (the phone also counts Apple Health).
            </>
          ) : (
            <>
              <Link href="/settings" className="text-accent">Add {missing}</Link> to get daily calorie and macro targets.
            </>
          )}
        </p>
      </section>

      <div className="flex gap-2">
        {gatech && <Link href={link({ tab: "dining" })} className={chip(tab === "dining")}>Georgia Tech</Link>}
        <Link href={link({ tab: "outside" })} className={chip(tab === "outside")}>Outside food</Link>
        <Link href={link({ tab: "search" })} className={chip(tab === "search")}>Search all foods</Link>
      </div>

      {tab === "search" && (
        <section className="card grid grid-cols-1 gap-3">
          <form className="flex gap-2">
            <input type="hidden" name="tab" value="search" />
            <input name="q" defaultValue={params.q} placeholder="Search 450k foods (e.g. chobani greek)" className="input flex-1" />
            <button className="btn">Search</button>
          </form>
          <form className="flex gap-2">
            <input type="hidden" name="tab" value="search" />
            <input name="barcode" defaultValue={params.barcode} inputMode="numeric" placeholder="Barcode number (UPC/EAN)" className="input flex-1" />
            <button className="btn">Look up</button>
          </form>
          {barcodeMissing && <p className="text-sm text-muted">No product found for that barcode. Add it below and it&apos;ll be found next time.</p>}
          {!barcodeMissing && (q || params.barcode) && results.length === 0 && <p className="text-sm text-muted">No matches. Add it below.</p>}
          {results.length > 0 && (
            <FoodRows items={results.map((r) => ({ ...r, name: r.brand ? `${r.name} · ${r.brand}` : r.name }))} source="outside" meal={currentMeal()} />
          )}
          <details open={barcodeMissing}>
            <summary className="cursor-pointer text-sm font-medium">Create a food (saved to your account)</summary>
            <form action={createFood} className="mt-2 grid grid-cols-2 gap-2 text-sm md:grid-cols-4">
              <input type="hidden" name="meal" value={currentMeal()} />
              <input name="name" required placeholder="Name" className="input col-span-2" />
              <input name="brand" placeholder="Brand (optional)" className="input col-span-2" />
              <input name="serving" placeholder="Serving (e.g. 1 bar, 40 g)" className="input col-span-2" />
              <input name="barcode" defaultValue={params.barcode} inputMode="numeric" placeholder="Barcode (optional)" className="input col-span-2" />
              <input name="kcal" type="number" step="1" min="0" required placeholder="Calories" className="input" />
              <input name="protein" type="number" step="0.1" min="0" placeholder="Protein g" className="input" />
              <input name="carbs" type="number" step="0.1" min="0" placeholder="Carbs g" className="input" />
              <input name="fat" type="number" step="0.1" min="0" placeholder="Fat g" className="input" />
              <button className="btn col-span-2 md:col-span-4">Create and log</button>
            </form>
          </details>
        </section>
      )}

      {tab === "search" ? null : tab === "dining" ? (
        <section className="card grid grid-cols-1 gap-3">
          {hall || place ? (
            <Link href={link({ tab: "dining" })} className="text-sm text-accent">
              ← All Georgia Tech places
            </Link>
          ) : (
            <form className="flex gap-2">
              <input type="hidden" name="tab" value="dining" />
              <input name="q" defaultValue={params.q} placeholder="Search places and menus" className="input flex-1" />
              <button className="btn">Search</button>
            </form>
          )}
          {hall ? (
            <>
              <h2 className="font-semibold">{hall.name}</h2>
              <div className="flex flex-wrap gap-2">
                {hall.meals.map((m) => (
                  <Link key={m} href={link({ tab: "dining", hall: hall.id, meal: m })} className={chip(m === meal)}>{m[0].toUpperCase() + m.slice(1)}</Link>
                ))}
              </div>
              <form className="flex gap-2">
                <input type="hidden" name="tab" value="dining" />
                <input type="hidden" name="hall" value={hall.id} />
                <input type="hidden" name="meal" value={meal} />
                <input name="q" defaultValue={params.q} placeholder="Search the menu" className="input flex-1" />
                <button className="btn">Search</button>
              </form>
              {menuError && <p className="text-sm text-muted">Couldn&apos;t load the menu. Staples are below.</p>}
              {!menuError && menu.length === 0 && <p className="text-sm text-muted">No menu posted for this meal today.</p>}
              {groupBy(menu.filter(match), (i) => i.station).map(([station, items]) => (
                <div key={station}>
                  <h3 className="text-sm font-semibold">{station}</h3>
                  <FoodRows items={items} source="dining" place={hall.name} meal={meal === "overnight" ? "snack" : meal} />
                </div>
              ))}
              {groupBy(STAPLES.filter(match), (i) => i.station).map(([station, items]) => (
                <div key={station}>
                  <h3 className="text-sm font-semibold">Always available · {station}</h3>
                  <FoodRows items={items} source="dining" place={hall.name} meal={meal === "overnight" ? "snack" : meal} />
                </div>
              ))}
            </>
          ) : place ? (
            <>
              <div>
                <h2 className="font-semibold">{place.name}</h2>
                <p className="text-xs text-muted">{[place.kind, place.area, place.detail].filter(Boolean).join(" · ")}</p>
              </div>
              {placeItems.length > 0 ? (
                groupBy(placeItems, (i) => i.station ?? "Menu").map(([station, items]) => (
                  <div key={station}>
                    <h3 className="text-sm font-semibold">{station}</h3>
                    <FoodRows items={items} source={place.area === "Near campus" ? "outside" : "dining"} place={place.name} meal={currentMeal()} />
                  </div>
                ))
              ) : (
                <>
                  <p className="text-sm text-muted">
                    {place.note ?? `${place.name} doesn't publish a menu with nutrition. Log it as a custom food, or find a similar dish in Search all foods.`}
                  </p>
                  <CustomFoodForm place={place.name} open />
                </>
              )}
              {placeItems.some((i) => i.estimated) && (
                <p className="text-xs text-muted">≈ {place.name} doesn&apos;t publish nutrition, so these are estimated from USDA ingredients and typical portions.</p>
              )}
            </>
          ) : q ? (
            <>
              {CAMPUS.some(placeMatch) && (
                <div className="flex flex-wrap gap-2">
                  {CAMPUS.filter(placeMatch).map((p) => (
                    <Link key={`${p.area}|${p.name}`} href={p.hall ? link({ tab: "dining", hall: p.hall, meal }) : link({ tab: "dining", area: p.area, place: p.name })} className={chip(false)}>
                      {p.name}
                    </Link>
                  ))}
                </div>
              )}
              {(["On campus", "Near campus"] as const).map((where) => {
                const items = CAMPUS_ITEMS.filter((i) => match(i) && (PLACE_BY_MENU.get(i.brand ?? "")?.area === "Near campus") === (where === "Near campus"));
                return (
                  items.length > 0 && (
                    <div key={where}>
                      <h3 className="text-sm font-semibold">
                        {where}
                        {items.length > 100 ? ` · first 100 of ${items.length}, refine the search` : ""}
                      </h3>
                      <FoodRows
                        items={items.slice(0, 100).map((i) => ({ ...i, name: `${i.name} · ${PLACE_BY_MENU.get(i.brand ?? "")?.name ?? i.brand}`, brand: PLACE_BY_MENU.get(i.brand ?? "")?.name ?? i.brand }))}
                        source={where === "Near campus" ? "outside" : "dining"}
                        meal={currentMeal()}
                      />
                    </div>
                  )
                );
              })}
              {!CAMPUS_ITEMS.some(match) && <p className="text-sm text-muted">No menu items match.</p>}
            </>
          ) : (
            CAMPUS_AREAS.map((area) => (
              <div key={area} className="grid gap-2">
                <h3 className="text-sm font-semibold">{area}</h3>
                <div className="flex flex-wrap gap-2">
                  {CAMPUS.filter((p) => p.area === area).map((p) => (
                    <Link
                      key={p.name}
                      href={p.hall ? link({ tab: "dining", hall: p.hall, meal }) : link({ tab: "dining", area: p.area, place: p.name })}
                      title={[p.kind, p.detail].filter(Boolean).join(" · ")}
                      className={chip(false)}
                    >
                      {p.name}
                    </Link>
                  ))}
                </div>
                {AREA_NOTES[area] && <p className="text-xs text-muted">{AREA_NOTES[area]}</p>}
              </div>
            ))
          )}
        </section>
      ) : (
        <section className="card grid grid-cols-1 gap-3">
          <form className="flex gap-2">
            <input type="hidden" name="tab" value="outside" />
            <input name="q" defaultValue={params.q} placeholder="Search restaurants and snacks" className="input flex-1" />
            <button className="btn">Search</button>
          </form>
          {q && !params.brand && !snack ? (
            <>
              <h3 className="text-sm font-semibold">
                Restaurants{restaurantHits.length > 100 ? ` · first 100 of ${restaurantHits.length}, refine the search` : ""}
              </h3>
              {restaurantHits.length === 0 && <p className="text-sm text-muted">No restaurant items match.</p>}
              <FoodRows items={restaurantHits.slice(0, 100).map((f) => ({ ...f, name: f.brand ? `${f.name} · ${f.brand}` : f.name }))} source="outside" meal={currentMeal()} />
              {packaged.length > 0 && (
                <>
                  <h3 className="text-sm font-semibold">Snacks, drinks &amp; packaged foods</h3>
                  <FoodRows items={packaged.map((r) => ({ ...r, name: r.brand ? `${r.name} · ${r.brand}` : r.name }))} source="outside" meal={currentMeal()} />
                </>
              )}
            </>
          ) : (
            <>
              <h3 className="text-sm font-semibold">Restaurants</h3>
              <div className="flex flex-wrap gap-2">
                {RESTAURANTS.map((b) => (
                  <Link key={b} href={link({ tab: "outside", brand: b })} className={chip(b === params.brand)}>{b}</Link>
                ))}
              </div>
              {params.brand && <FoodRows items={restaurantHits.slice(0, 200)} source="outside" meal={currentMeal()} />}
              {SNACK_GROUPS.map((g) => (
                <div key={g.name} className="grid gap-2">
                  <h3 className="text-sm font-semibold">{g.name}</h3>
                  <div className="flex flex-wrap gap-2">
                    {g.brands.map((b) => (
                      <Link key={b.name} href={link({ tab: "outside", snack: b.name })} className={chip(b.name === snack?.name)}>{b.name}</Link>
                    ))}
                  </div>
                </div>
              ))}
              {snack && (
                <div>
                  <h3 className="text-sm font-semibold">{snack.name}</h3>
                  {packaged.length === 0 && <p className="text-sm text-muted">Nothing found; try Search all foods.</p>}
                  <FoodRows items={packaged} source="outside" place={snack.name} meal={currentMeal()} />
                </div>
              )}
            </>
          )}
          <CustomFoodForm />
        </section>
      )}

      <section className="card">
        <h2 className="mb-2 font-semibold">Logged today</h2>
        {logs.length === 0 ? (
          <p className="text-sm text-muted">Nothing logged yet today.</p>
        ) : (
          <ul className="divide-y divide-border text-sm">
            {logs.map((l) => (
              <li key={l.id} className="flex items-center gap-2 py-2">
                <div className="min-w-0 flex-1">
                  <div className="truncate">{l.name}</div>
                  <div className="text-xs text-muted">
                    {l.place ?? l.source} · {l.meal} · {Number(l.servings)}×
                  </div>
                </div>
                <span className="tabular-nums">{Math.round(Number(l.kcal) * Number(l.servings))} kcal · {Math.round(Number(l.protein) * Number(l.servings))} g P</span>
                <form action={deleteFood}>
                  <input type="hidden" name="id" value={l.id} />
                  <button className="text-xs text-muted hover:text-foreground" aria-label={`Delete ${l.name}`}>✕</button>
                </form>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="card grid grid-cols-1 gap-2">
        <div className="flex items-baseline justify-between">
          <h2 className="font-semibold">Water</h2>
          <span className="flex items-baseline gap-3 text-xl font-semibold tabular-nums">
            <span>
              {waterSoFar} <span className="text-sm font-normal text-muted">{waterUnit} today</span>
            </span>
            {goalWater !== null && <span className={`text-sm font-semibold ${waterHit ? "text-green-500" : "text-red-500"}`}>goal {goalWater}</span>}
            <Link
              href={link({ ...params, water: removingWater ? undefined : "remove" })}
              aria-label={removingWater ? "Back to adding water" : "Remove water"}
              title={removingWater ? "Back to adding water" : "Remove water"}
              className={`grid size-7 place-items-center self-center rounded-full border text-base ${removingWater ? "border-accent text-accent" : "border-red-500 text-red-500"}`}
            >
              {removingWater ? "+" : "−"}
            </Link>
          </span>
        </div>
        {goalWater !== null ? (
          <div className="h-1.5 overflow-hidden rounded-full bg-border">
            <div className={`h-full ${waterHit ? "bg-green-500" : "bg-red-500"}`} style={{ width: `${Math.min(100, (waterSoFar / goalWater) * 100)}%` }} />
          </div>
        ) : (
          <p className="text-xs text-muted">
            <Link href="/settings" className="text-accent">Log your body weight</Link> to get a daily goal.
          </p>
        )}
        <div className="flex flex-wrap gap-2">
          {WATER_QUICK[waterUnit].map((amount) => (
            <form key={amount} action={removingWater ? removeWater : logWater}>
              <input type="hidden" name="amount" value={amount} />
              <input type="hidden" name="unit" value={waterUnit} />
              <button className={`btn ${removingWater ? "text-red-500" : ""}`} disabled={removingWater && water.length === 0}>
                {removingWater ? "−" : "+"}
                {amount} {waterUnit}
              </button>
            </form>
          ))}
          <form action={removingWater ? removeWater : logWater} className="flex gap-2">
            <input type="hidden" name="unit" value={waterUnit} />
            <input name="amount" type="number" step="0.1" min="0.1" max="5000" required placeholder={`Other (${waterUnit})`} className="input w-32" />
            <button className={`btn ${removingWater ? "text-red-500" : ""}`}>{removingWater ? "Remove" : "Add"}</button>
          </form>
        </div>
        {water.length > 0 && (
          <ul className="flex flex-wrap gap-2 text-xs text-muted">
            {water.map((l) => (
              <li key={l.id} className="flex items-center gap-1 rounded-full border border-border px-2 py-0.5">
                {new Date(l.drank_at).toLocaleTimeString("en-US", { timeZone: tz, hour: "numeric", minute: "2-digit" })} · {Number(l.amount)} {l.unit}
                <form action={deleteWater}>
                  <input type="hidden" name="id" value={l.id} />
                  <button className="hover:text-foreground" aria-label={`Delete ${Number(l.amount)} ${l.unit} of water`}>✕</button>
                </form>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
