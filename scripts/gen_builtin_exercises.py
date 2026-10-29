#!/usr/bin/env python3
"""Regenerates ios/LiftLog/Models/BuiltInExercises.swift from supabase/seed.sql."""
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
seed = (root / "supabase/seed.sql").read_text()
row = re.compile(r"\('([0-9a-f-]{36})', null, '((?:[^']|'')*)', '(\w+)', '(\w+)', '(\w+)', '\{([^}]*)\}'\)")
target = root / "ios/LiftLog/Models/BuiltInExercises.swift"
swift = target.read_text()
entries = []
for id_, name, kind, equipment, primary, secondary in row.findall(seed):
    name = name.replace("''", "'").replace('"', '\\"')
    sec = ", ".join(f'"{m}"' for m in secondary.split(",") if m)
    entries.append(
        f'        Seed(id: "{id_}", name: "{name}", kind: "{kind}", equipment: "{equipment}", primary: "{primary}", secondary: [{sec}]),'
    )
start = swift.index("    static let all: [Seed] = [\n") + len("    static let all: [Seed] = [\n")
end = swift.index("    ]\n", start)
target.write_text(swift[:start] + "\n".join(entries) + "\n" + swift[end:])
print(f"{len(entries)} exercises")
