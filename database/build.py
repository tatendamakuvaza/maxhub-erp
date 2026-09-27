"""
Build database/maxhub_erp.sql from the module files in database/modules/.

Why: the modules are easier to read and edit, but beginners (and pgAdmin's
Query Tool) want ONE file to run.  Run this after editing any module:

    python database/build.py            # full build (schema + demo data)
    python database/build.py --schema   # schema only (no demo data) -> maxhub_erp_schema.sql
"""
from __future__ import annotations

import sys
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULES = HERE / "modules"


def build(schema_only: bool = False) -> Path:
    files = sorted(p for p in MODULES.glob("*.sql"))
    if schema_only:
        files = [p for p in files if not p.name[:2].isdigit() or int(p.name[:2]) < 30 or p.name.startswith("99")]
    out = HERE / ("maxhub_erp_schema.sql" if schema_only else "maxhub_erp.sql")
    parts = [
        "-- =====================================================================================\n"
        f"-- GENERATED FILE - built by database/build.py on {date.today():%d %b %Y} from database/modules/*.sql\n"
        "-- Edit the module files, then run:  python database/build.py\n"
        "-- =====================================================================================\n"
    ]
    for f in files:
        parts.append(f"\n-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  {f.name}  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n")
        parts.append(f.read_text(encoding="utf-8"))
    out.write_text("".join(parts), encoding="utf-8", newline="\n")
    print(f"Built {out.name}: {len(files)} modules, {sum(len(p.splitlines()) for p in parts):,} lines")
    return out


if __name__ == "__main__":
    build(schema_only="--schema" in sys.argv)
