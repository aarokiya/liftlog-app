import Link from "next/link";
import { bodyPlan, planStartWeight } from "@/lib/aesthetics";
import { FAST_FOOD, HALLS, RESTAURANTS, SNACK_GROUPS, STAPLES, WATER_QUICK, currentMeal, diningMenu, fromRow, groupBy, localDate, normalizeBarcode, parseOpenFoodFacts, totals, waterGoal, waterTotal, waterUnitFor, brandFoods, uniqueFoods, type FoodItem, type FoodRow } from "@/lib/food";
import { convert } from "@/lib/stats";
import { getProfile } from "@/lib/data";
import { requireUser } from "@/lib/supabase/server";
import { userTimeZone } from "@/lib/time/server";
import { createFood, deleteFood, deleteWater, logFood, logWater } from "./actions";

type Params = { tab?: string; hall?: string; meal?: string; q?: string; brand?: string; barcode?: string; snack?: string };

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
                {item.serving} · {Math.round(item.kcal)} kcal · {item.protein} g protein
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
  const meal = params.meal ?? currentMeal();
  const q = (params.q ?? "").trim().toLowerCase();
  const match = (i: FoodItem) => !q || i.name.toLowerCase().includes(q) || (i.brand ?? "").toLowerCase().includes(q);

  const since = new Date(Date.now() - 36 * 3600 * 1000).toISOString();
  const [{ data: logRows }, { data: metrics }, { data: waterRows }, { data: workoutRows }] = await Promise.all([
    supabase.from("food_logs").select("id, eaten_at, meal, source, place, name, servings, kcal, protein, carbs, fat").is("deleted_at", null).gte("eaten_at", since).order("eaten_at", { ascending: false }),
    supabase.from("body_metrics").select("measured_at, body_weight, unit, body_fat_pct").is("deleted_at", null).order("measured_at", { ascending: false }).limit(200),
    supabase.from("water_logs").select("id, drank_at, amount, unit").is("deleted_at", null).gte("drank_at", since).order("drank_at", { ascending: false }),
    supabase.from("workouts").select("started_at").is("deleted_at", null).gte("started_at", since),
  ]);
  const logs = (logRows ?? []).filter((l) => localDate(new Date(l.eaten_at), tz) === today);
  const sum = totals(logs);
  const water = (waterRows ?? []).filter((l) => localDate(new Date(l.drank_at), tz) === today);
  const waterUnit = waterUnitFor(unit);
  const w = (metrics ?? []).find((m) => m.body_weight !== null);
  const bf = (metrics ?? []).find((m) => m.body_fat_pct !== null)?.body_fat_pct;
  const proteinTarget = profile.sex && w && bf
    ? bodyPlan(convert(Number(w.body_weight), w.unit === "kg" ? "kg" : "lb", unit), unit, Number(bf), undefined, planStartWeight(metrics ?? [], unit) ?? undefined, profile.sex).proteinG
    : null;
  const trainedToday = (workoutRows ?? []).some((r) => localDate(new Date(r.started_at), tz) === today);
  const goalWater = w ? waterGoal(convert(Number(w.body_weight), w.unit === "kg" ? "kg" : "lb", "kg"), trainedToday, waterUnit) : null;
  const waterSoFar = waterTotal(water, waterUnit);
  const waterHit = goalWater !== null && waterSoFar >= goalWater;

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
            ["kcal", sum.kcal, null],
            ["protein (g)", sum.protein, proteinTarget],
            ["carbs (g)", sum.carbs, null],
            ["fat (g)", sum.fat, null],
          ] as const
        ).map(([label, value, target]) => (
          <div key={label}>
            <div className={`text-xl font-semibold tabular-nums ${target ? (value >= target ? "text-green-500" : "text-red-500") : ""}`}>{value}</div>
            <div className="text-xs text-muted">{target ? `${label} / ${target}` : label}</div>
          </div>
        ))}
      </section>

      <div className="flex gap-2">
        {gatech && <Link href={link({ tab: "dining" })} className={chip(tab === "dining")}>Dining hall</Link>}
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
          <div className="flex flex-wrap gap-2">
            {HALLS.map((h) => (
              <Link key={h.id} href={link({ hall: h.id, meal })} className={chip(h.id === hall?.id)}>{h.name}</Link>
            ))}
          </div>
          {hall ? (
            <>
              <div className="flex flex-wrap gap-2">
                {hall.meals.map((m) => (
                  <Link key={m} href={link({ hall: hall.id, meal: m })} className={chip(m === meal)}>{m[0].toUpperCase() + m.slice(1)}</Link>
                ))}
              </div>
              <form className="flex gap-2">
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
          ) : (
            <p className="text-sm text-muted">Pick a dining hall to see today&apos;s menu.</p>
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
          <details>
            <summary className="cursor-pointer text-sm font-medium">Custom food (enter macros)</summary>
            <form action={logFood} className="mt-2 grid grid-cols-2 gap-2 text-sm md:grid-cols-4">
              <input type="hidden" name="source" value="custom" />
              <input type="hidden" name="meal" value={currentMeal()} />
              <input name="name" required placeholder="What did you eat?" className="input col-span-2" />
              <input name="place" placeholder="Where (optional)" className="input col-span-2" />
              <input name="kcal" type="number" step="1" placeholder="Calories" className="input" />
              <input name="protein" type="number" step="0.1" placeholder="Protein g" className="input" />
              <input name="carbs" type="number" step="0.1" placeholder="Carbs g" className="input" />
              <input name="fat" type="number" step="0.1" placeholder="Fat g" className="input" />
              <button className="btn col-span-2 md:col-span-4">Log</button>
            </form>
          </details>
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
          <span className="text-xl font-semibold tabular-nums">
            {waterSoFar} <span className="text-sm font-normal text-muted">{waterUnit} today</span>
            {goalWater !== null && (
              <span className={`ml-3 text-sm font-semibold ${waterHit ? "text-green-500" : "text-red-500"}`}>goal {goalWater}</span>
            )}
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
            <form key={amount} action={logWater}>
              <input type="hidden" name="amount" value={amount} />
              <input type="hidden" name="unit" value={waterUnit} />
              <button className="btn">+{amount} {waterUnit}</button>
            </form>
          ))}
          <form action={logWater} className="flex gap-2">
            <input type="hidden" name="unit" value={waterUnit} />
            <input name="amount" type="number" step="0.1" min="0.1" max="5000" required placeholder={`Other (${waterUnit})`} className="input w-32" />
            <button className="btn">Add</button>
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
