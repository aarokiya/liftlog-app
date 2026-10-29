"""Build the shared foods databank seed from USDA FoodData Central CSV bundles.

Usage: python3 scripts/gen_foods.py <sr_legacy dir> <survey (FNDDS) dir> <branded dir> <out.tsv.gz>

Downloads (public domain): https://fdc.nal.usda.gov/download-datasets/
  SR Legacy 2018-04, Survey (FNDDS) 2024-10-31, Branded 2025-12-18.
Output columns: source_id, barcode, name, brand, serving, serving_g, kcal, protein, carbs, fat, rank.
Generic foods (SR Legacy, FNDDS) get rank 0 so they sort above branded products.
"""
import csv
import gzip
import os
import re
import string
import sys

csv.field_size_limit(10**9)
sr_dir, fndds_dir, branded_dir, out_path = sys.argv[1:5]
PREFER = ["NLEA", "medium", "large", "container", "slice", "bun", "piece", "cookie", "tbsp", "cup", "oz"]


def rows(d, name):
    with open(os.path.join(d, name), newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def rank(desc):
    d = desc.lower()
    if "not specified" in d or "chopped" in d or "mashed" in d:
        return len(PREFER) + 1
    return next((i for i, k in enumerate(PREFER) if k.lower() in d), len(PREFER))


def tidy(text, limit):
    text = re.sub(r"\s+", " ", (text or "").strip())
    if text.isupper():
        text = string.capwords(text.lower())
    return text[:limit]


def macros(n, factor):
    return [round(n.get(k, 0) * factor, 1) for k in ("kcal", "protein", "carbs", "fat")]


out = gzip.open(out_path, "wt", encoding="utf-8", newline="")
w = csv.writer(out, delimiter="\t", lineterminator="\n")
count = {"sr": 0, "fndds": 0, "branded": 0}


def generic(d, prefix, ids_by_key, portion_label):
    foods = {r["fdc_id"]: r["description"] for r in rows(d, "food.csv")}
    n100 = {}
    for r in rows(d, "food_nutrient.csv"):
        key = ids_by_key.get(r["nutrient_id"])
        if key and r["fdc_id"] in foods and r["amount"]:
            n100.setdefault(r["fdc_id"], {})[key] = float(r["amount"])
    port = {}
    for r in rows(d, "food_portion.csv"):
        g = float(r["gram_weight"] or 0)
        label = portion_label(r)
        if r["fdc_id"] in foods and g > 0 and label:
            cand = (rank(label), g, label)
            if r["fdc_id"] not in port or cand[0] < port[r["fdc_id"]][0]:
                port[r["fdc_id"]] = cand
    for fid, desc in foods.items():
        n = n100.get(fid)
        if not n or "kcal" not in n:
            continue
        _, grams, label = port.get(fid, (0, 100.0, "100 g"))
        label = f"{label} ({grams:g} g)" if label != "100 g" else label
        w.writerow([f"{prefix}-{fid}", "", tidy(desc, 200), "", label[:120], round(grams, 1), *macros(n, grams / 100), 0])
        count[prefix] += 1


generic(sr_dir, "sr", {"1008": "kcal", "1003": "protein", "1005": "carbs", "1004": "fat"},
        lambda r: " ".join(x for x in [r["amount"].rstrip("0").rstrip(".") if r["amount"] else "", r["modifier"]] if x).strip())
generic(fndds_dir, "fndds", {"208": "kcal", "203": "protein", "205": "carbs", "204": "fat"},
        lambda r: r["portion_description"].strip())

# Branded: newest US record per barcode, nutrients are per 100 g/ml.
UNITS = {"g": "g", "grm": "g", "gm": "g", "ml": "ml", "mlt": "ml"}
latest = {}
for r in rows(branded_dir, "branded_food.csv"):
    code = r["gtin_upc"].strip().lstrip("0")
    unit = UNITS.get(r["serving_size_unit"].strip().lower())
    if r["discontinued_date"] or r["market_country"] not in ("United States", "US") or not unit or not re.fullmatch(r"[0-9]{6,14}", code):
        continue
    if code not in latest or r["available_date"] > latest[code]["available_date"]:
        latest[code] = {k: r[k] for k in ("fdc_id", "brand_name", "brand_owner", "serving_size", "household_serving_fulltext", "available_date")} | {"unit": unit}
by_fdc = {v["fdc_id"]: code for code, v in latest.items()}
names = {r["fdc_id"]: r["description"] for r in rows(branded_dir, "food.csv") if r["fdc_id"] in by_fdc}
KEYS = {"1008": "kcal", "2047": "kcal_alt", "2048": "kcal_alt", "1003": "protein", "1005": "carbs", "1004": "fat"}
n100 = {}
for r in rows(branded_dir, "food_nutrient.csv"):
    key = KEYS.get(r["nutrient_id"])
    if key and r["fdc_id"] in by_fdc and r["amount"]:
        n100.setdefault(r["fdc_id"], {})[key] = float(r["amount"])
for fid, code in by_fdc.items():
    v, n = latest[code], n100.get(fid, {})
    if "kcal" not in n and "kcal_alt" in n:
        n["kcal"] = n["kcal_alt"]
    name = tidy(names.get(fid), 200)
    if "kcal" not in n or not name or n["kcal"] > 950:
        continue
    size = float(v["serving_size"] or 0)
    if not 0 < size <= 2000:
        size = 100.0
    house = tidy(v["household_serving_fulltext"], 80)
    if house and house.lower() in ("none", "n/a", "na"):  # USDA writes "None" for a missing household serving
        house = ""
    if house and re.search(r"\d\s*(g|ml|grm|mlt)\b", house.lower()):
        serving = house
    else:
        serving = f"{house} ({size:g} {v['unit']})" if house else f"{size:g} {v['unit']}"
    brand = tidy(v["brand_name"] or v["brand_owner"], 120)
    vals = macros(n, size / 100)
    if max(vals) >= 9999:
        continue
    w.writerow([f"fdc-{fid}", code, name, brand, serving[:120], size if v["unit"] == "g" and size >= 0.1 else "", *vals, 1])
    count["branded"] += 1
out.close()
print(count)
