# Deploy web/ + shared/ to a Vercel project (production) by file upload.
# env: VERCEL_TOKEN (full-account scope), SUPABASE_URL, SUPABASE_ANON_KEY,
#      VERCEL_PROJECT (default "liftlog"), and any other NEXT_PUBLIC_* settings to set on the project.
import os, json, hashlib, urllib.request, urllib.error, pathlib, time, sys
from urllib.parse import urlparse
T=os.environ["VERCEL_TOKEN"].strip(); API="https://api.vercel.com"
p=urlparse(os.environ["SUPABASE_URL"].strip()); SB=f"{p.scheme}://{p.netloc}"; KEY=os.environ["SUPABASE_ANON_KEY"].strip()
def call(method, path, body=None, headers=None, raw=None):
    h={"Authorization":"Bearer "+T}; h.update(headers or {})
    data=raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    if body is not None: h["Content-Type"]="application/json"
    try:
        with urllib.request.urlopen(urllib.request.Request(API+path, data=data, method=method, headers=h), timeout=120) as r:
            t=r.read(); return r.status, (json.loads(t) if t else {})
    except urllib.error.HTTPError as e:
        t=e.read(); 
        try: return e.code, json.loads(t)
        except Exception: return e.code, {"raw":t[:200].decode(errors="replace")}
NAME=os.environ.get("VERCEL_PROJECT","liftlog").strip()
s,proj=call("GET",f"/v9/projects/{NAME}")
if s==404:
    s,proj=call("POST","/v11/projects",{"name":NAME,"framework":"nextjs","rootDirectory":"web"})
    print("create project",s, proj.get("error"))
s,r=call("PATCH",f"/v9/projects/{NAME}",{"framework":"nextjs","rootDirectory":"web","nodeVersion":"22.x","sourceFilesOutsideRootDirectory":True,"installCommand":"npx --yes pnpm@11.21.0 install --frozen-lockfile","buildCommand":"npx --yes pnpm@11.21.0 run build"}); print("patch project",s,r.get("error"))
pid=proj["id"]
envs=[("NEXT_PUBLIC_SUPABASE_URL",SB,"plain"),("NEXT_PUBLIC_SUPABASE_ANON_KEY",KEY,"encrypted"),("ENABLE_EXPERIMENTAL_COREPACK","1","plain")]
envs+=[(k,v,"plain") for k,v in sorted(os.environ.items()) if k.startswith("NEXT_PUBLIC_") and k not in ("NEXT_PUBLIC_SUPABASE_URL","NEXT_PUBLIC_SUPABASE_ANON_KEY") and v]
for k,v,typ in envs:
    s,r=call("POST",f"/v10/projects/{pid}/env?upsert=true",{"key":k,"value":v,"type":typ,"target":["production","preview","development"]})
    print("env",k,s,r.get("error",{}).get("message") if isinstance(r,dict) else "")
root=pathlib.Path(__file__).resolve().parent.parent
skip={"node_modules",".next","tsconfig.tsbuildinfo",".env.local",".vercel"}
files=[]
for top in ["web","shared"]:
    for f in (root/top).rglob("*"):
        if f.is_file() and not any(part in skip for part in f.relative_to(root).parts):
            files.append(f)
manifest=[]
for f in files:
    data=f.read_bytes(); sha=hashlib.sha1(data).hexdigest()
    s,r=call("POST","/v2/files",headers={"x-vercel-digest":sha,"Content-Type":"application/octet-stream","Content-Length":str(len(data))},raw=data)
    if s not in (200,201): print("upload fail",f,s,r); sys.exit(1)
    manifest.append({"file":str(f.relative_to(root)),"sha":sha,"size":len(data)})
print("uploaded",len(manifest))
s,d=call("POST","/v13/deployments?skipAutoDetectionConfirmation=1",{"name":NAME,"project":pid,"target":"production","files":manifest,
   "projectSettings":{"framework":"nextjs","rootDirectory":"web","nodeVersion":"22.x","sourceFilesOutsideRootDirectory":True,"installCommand":"npx --yes pnpm@11.21.0 install --frozen-lockfile","buildCommand":"npx --yes pnpm@11.21.0 run build"}})
print("deploy",s,d.get("error"),d.get("id"),d.get("url"))
did=d["id"]
while True:
    time.sleep(10); s,d=call("GET",f"/v13/deployments/{did}")
    st=d.get("readyState"); print(st, flush=True)
    if st in ("READY","ERROR","CANCELED"): break
print("aliases:",d.get("alias"))
if st!="READY":
    s,ev=call("GET",f"/v3/deployments/{did}/events?limit=-1&builds=1")
    lines=[e.get("payload",{}).get("text","") for e in (ev if isinstance(ev,list) else [])]
    print("\n".join(lines[-40:]))
