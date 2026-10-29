"""Build shared/food/fast-food.json from the USDA SR Legacy CSV bundle ("Fast Foods" category).

Usage: python3 scripts/gen_fast_food.py <path to FoodData_Central_sr_legacy_food_csv_2018-04>
Download: https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip
"""
import csv, json, os, sys

src = sys.argv[1]
rd = lambda n: csv.DictReader(open(os.path.join(src, n), encoding="utf-8"))
cats = {r["id"]: r["description"] for r in rd("food_category.csv")}
foods = {r["fdc_id"]: r["description"] for r in rd("food.csv") if cats.get(r["food_category_id"]) == "Fast Foods"}
want = {"1008": "kcal", "1003": "protein", "1005": "carbs", "1004": "fat"}
per100 = {}
for r in rd("food_nutrient.csv"):
    if r["fdc_id"] in foods and r["nutrient_id"] in want:
        per100.setdefault(r["fdc_id"], {})[want[r["nutrient_id"]]] = float(r["amount"])
portions = {}
for r in rd("food_portion.csv"):
    if r["fdc_id"] in foods and r["fdc_id"] not in portions and float(r["gram_weight"] or 0) > 0:
        label = " ".join(x for x in [r["amount"].rstrip("0").rstrip(".") if r["amount"] else "", r["modifier"]] if x).strip()
        portions[r["fdc_id"]] = (float(r["gram_weight"]), label or "serving")

CHAINS = {"McDONALD'S": "McDonald's", "KFC": "KFC", "BURGER KING": "Burger King", "POPEYES": "Popeyes", "WENDY'S": "Wendy's",
          "WEND'YS": "Wendy's", "SUBWAY": "Subway", "TACO BELL": "Taco Bell", "PIZZA HUT": "Pizza Hut", "CHICK-FIL-A": "Chick-fil-A",
          "DOMINO'S": "Domino's", "LITTLE CAESARS": "Little Caesars", "PAPA JOHN'S": "Papa John's", "ARBY'S": "Arby's",
          "DIGIORNO": "DiGiorno", "CARRABBA'S": "Carrabba's", "OLIVE GARDEN": "Olive Garden", "APPLEBEE'S": "Applebee's"}

def split_name(desc):
    """(brand, display name): 'McDONALD'S, Big Mac' -> ("McDonald's", "Big Mac"); generic items get brand "Generic"."""
    for raw, nice in CHAINS.items():
        if desc.upper().startswith(raw.upper()):
            return nice, desc[len(raw):].lstrip(" ,") or desc
    rest = desc
    for prefix in ("Fast foods, ", "Fast Foods, ", "Fast food, ", "Fast Food, "):
        if rest.startswith(prefix):
            rest = rest[len(prefix):]
    return "Generic", rest[:1].upper() + rest[1:]

items = []
for fid, desc in foods.items():
    n = per100.get(fid, {})
    if "kcal" not in n or desc.lower().startswith("school lunch"):
        continue
    brand, name = split_name(desc)
    grams, label = portions.get(fid, (100.0, "100 g"))
    f = grams / 100
    items.append({
        "id": f"fdc-{fid}",
        "name": name,
        "brand": brand,
        "serving": label,
        "grams": round(grams, 1),
        "kcal": round(n["kcal"] * f),
        "protein": round(n.get("protein", 0) * f, 1),
        "carbs": round(n.get("carbs", 0) * f, 1),
        "fat": round(n.get("fat", 0) * f, 1),
    })
items.sort(key=lambda i: (i["brand"] == "Generic", i["brand"], i["name"]))
json.dump({"source": "USDA FoodData Central, SR Legacy (2018-04), Fast Foods category", "items": items},
          open("shared/food/fast-food.json", "w"), indent=1)
print(len(items))

# Dining-hall staples (always out regardless of the day's menu), keyed by SR Legacy fdc_id.
STAPLES = {
    "Cereal": {"173884": "Cheerios", "172990": "Frosted Flakes", "174646": "Cinnamon Toast cereal", "171650": "Raisin Bran",
               "174648": "Corn Flakes", "171646": "Granola", "173904": "Oatmeal (dry oats)"},
    "Bakery": {"174987": "Butter croissant", "175049": "Plain bagel", "172765": "Blueberry muffin", "174990": "Cake doughnut",
               "172754": "Cheese danish", "167940": "Cinnamon roll", "172716": "Chocolate chip cookie", "175038": "Waffle"},
    "Breakfast & sides": {"170870": "2% milk", "171269": "Skim milk", "170894": "Greek yogurt (plain, nonfat)",
                          "173424": "Hard-boiled egg", "172688": "Whole-wheat bread", "172470": "Peanut butter"},
    "Fruit": {"173944": "Banana", "171688": "Apple", "169097": "Orange"},
    "Dessert": {"167572": "Vanilla soft serve (light)"},
}
allfoods = {r["fdc_id"]: r["description"] for r in rd("food.csv")}
ids = {i for v in STAPLES.values() for i in v}
n100, port = {}, {}
for r in rd("food_nutrient.csv"):
    if r["fdc_id"] in ids and r["nutrient_id"] in want:
        n100.setdefault(r["fdc_id"], {})[want[r["nutrient_id"]]] = float(r["amount"])
# Prefer a natural single serving ("1 medium", "1 slice", "1 NLEA serving") over "1 cup, mashed".
PREFER = ["NLEA", "medium", "large", "container", "slice", "bun", "donut", "cookie", "waffle", "tbsp", "cup"]
def rank(mod):
    return next((i for i, k in enumerate(PREFER) if k.lower() in mod.lower() and "chopped" not in mod and "mashed" not in mod), len(PREFER))
for r in rd("food_portion.csv"):
    if r["fdc_id"] in ids and float(r["gram_weight"] or 0) > 0:
        label = " ".join(x for x in [r["amount"].rstrip("0").rstrip(".") if r["amount"] else "", r["modifier"]] if x).strip()
        cand = (rank(r["modifier"]), float(r["gram_weight"]), label or "serving")
        if r["fdc_id"] not in port or cand[0] < port[r["fdc_id"]][0]:
            port[r["fdc_id"]] = cand
port = {k: (g, l) for k, (_, g, l) in port.items()}
staples = []
for station, fids in STAPLES.items():
    for fid, label_name in fids.items():
        n = n100[fid]
        grams, label = port.get(fid, (100.0, "100 g"))
        f = grams / 100
        staples.append({
            "id": f"fdc-{fid}", "name": label_name, "usda": allfoods[fid], "station": station, "serving": label, "grams": round(grams, 1),
            "kcal": round(n["kcal"] * f), "protein": round(n.get("protein", 0) * f, 1),
            "carbs": round(n.get("carbs", 0) * f, 1), "fat": round(n.get("fat", 0) * f, 1),
        })
json.dump({"source": "USDA FoodData Central, SR Legacy (2018-04); generic values, not GT Dining's recipes", "items": staples},
          open("shared/food/dining-staples.json", "w"), indent=1)
print(len(staples))
