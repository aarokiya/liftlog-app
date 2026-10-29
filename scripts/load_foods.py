# Load the gen_foods.py TSV into the foods table in 2,000-row upserts via the Management API.
# usage: python3 scripts/load_foods.py foods.tsv.gz [resume_from_row]; env: SUPABASE_ACCESS_TOKEN, SUPABASE_URL
import csv, gzip, json, os, sys, time, urllib.request
from urllib.parse import urlparse
csv.field_size_limit(10**9)
T = os.environ["SUPABASE_ACCESS_TOKEN"].strip()
ref = urlparse(os.environ["SUPABASE_URL"].strip()).netloc.split(".")[0]

def q(sql, tries=5):
    for i in range(tries):
        try:
            r = urllib.request.Request(f"https://api.supabase.com/v1/projects/{ref}/database/query", data=json.dumps({"query": sql}).encode(), method="POST",
                                       headers={"Authorization": "Bearer " + T, "Content-Type": "application/json", "User-Agent": "liftlog-migrate"})
            return json.loads(urllib.request.urlopen(r, timeout=120).read() or "null")
        except Exception as e:
            err = e.read().decode()[:300] if hasattr(e, "read") else str(e)
            print("retry", i, err, flush=True); time.sleep(3 * (i + 1))
    raise SystemExit("failed")

def lit(v):
    return "null" if v == "" else "'" + v.replace("'", "''") + "'"

start = int(sys.argv[2]) if len(sys.argv) > 2 else 0
batch, n = [], 0
def flush():
    q("insert into foods (source, source_id, barcode, name, brand, serving, serving_g, kcal, protein, carbs, fat, rank, created_by) values "
      + ",".join(batch) + " on conflict (source, source_id) where source_id is not null do update set barcode = excluded.barcode, name = excluded.name, "
      "brand = excluded.brand, serving = excluded.serving, serving_g = excluded.serving_g, kcal = excluded.kcal, protein = excluded.protein, "
      "carbs = excluded.carbs, fat = excluded.fat, rank = excluded.rank")
    batch.clear()
for row in csv.reader(gzip.open(sys.argv[1], "rt", encoding="utf-8"), delimiter="\t"):
    n += 1
    if n <= start: continue
    sid, code, name, brand, serving, sg, kcal, p, c, f, rank = row
    batch.append(f"('usda',{lit(sid)},{lit(code)},{lit(name)},{lit(brand)},{lit(serving)},{sg if sg and float(sg) >= 0.1 else 'null'},{kcal},{p},{c},{f},{rank},null)")
    if len(batch) >= 2000:
        flush()
        if n % 50000 == 0: print(n, flush=True)
if batch: flush()
print("done", n, q("select count(*) n, pg_size_pretty(pg_total_relation_size('foods')) size, pg_size_pretty(pg_database_size(current_database())) db from foods"))
