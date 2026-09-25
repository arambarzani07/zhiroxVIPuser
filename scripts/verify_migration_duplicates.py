#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"

groups: dict[str, list[Path]] = {}
for path in sorted(MIGRATIONS.glob("*.sql")):
    text = path.read_text(encoding="utf-8", errors="ignore").strip()
    if not text:
        continue
    if "Historical migration marker." in text:
        continue
    normalized = "\n".join(line.rstrip() for line in text.splitlines()).strip()
    digest = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
    groups.setdefault(digest, []).append(path)

duplicates = [paths for paths in groups.values() if len(paths) > 1]
if duplicates:
    print("Duplicate executable migrations found:")
    for paths in duplicates:
        print("  - " + ", ".join(str(p.relative_to(ROOT)) for p in paths))
    raise SystemExit(1)

print("migration duplicate contract verified")
