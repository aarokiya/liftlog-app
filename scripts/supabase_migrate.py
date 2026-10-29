# Apply supabase/migrations/*.sql (and seed.sql once) via the Supabase Management API.
# env: SUPABASE_ACCESS_TOKEN (personal access token), SUPABASE_URL
import os, json, urllib.request, urllib.error, pathlib
from urllib.parse import urlparse
T=os.environ["SUPABASE_ACCESS_TOKEN"].strip()
ref=urlparse(os.environ["SUPABASE_URL"].strip()).netloc.split(".")[0]
def q(sql):
    r=urllib.request.Request(f"https://api.supabase.com/v1/projects/{ref}/database/query", data=json.dumps({"query":sql}).encode(), method="POST",
        headers={"Authorization":"Bearer "+T,"Content-Type":"application/json","User-Agent":"liftlog-migrate"})
    try:
        with urllib.request.urlopen(r, timeout=120) as resp: return resp.status, json.loads(resp.read() or b"null")
    except urllib.error.HTTPError as e: return e.code, e.read()[:500].decode()
print("ping", q("select count(*) as tables from information_schema.tables where table_schema='public'"))
q("create schema if not exists supabase_migrations; create table if not exists supabase_migrations.schema_migrations (version text primary key, statements text[], name text);")
s,applied=q("select version from supabase_migrations.schema_migrations")
done={r["version"] for r in applied} if s in (200,201) else set()
root=pathlib.Path(__file__).resolve().parent.parent/"supabase"
for f in sorted((root/"migrations").glob("*.sql")):
    v,name=f.stem.split("_",1)
    if v in done: print("skip",f.name); continue
    s,r=q(f.read_text()); print("migrate",f.name,s, r if s not in (200,201) else "")
    if s not in (200,201): raise SystemExit(1)
    q(f"insert into supabase_migrations.schema_migrations(version,name) values ('{v}','{name}')")
# seed.sql inserts with "on conflict do nothing", so it's safe to run every time (migrations may add a few built-ins first).
s,r=q((root/"seed.sql").read_text()); print("seed",s, r if s not in (200,201) else "")
print(q("select count(*) as n from exercises where user_id is null"))
print(q("select table_name from information_schema.tables where table_schema='public' order by 1"))
