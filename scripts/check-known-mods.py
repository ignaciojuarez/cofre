#!/usr/bin/env python3
"""Keep plan/known-mods.md's table generated from CofreKit's JSON catalog."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "app/UI/Sources/CofreKit/Resources/known-mods.json"
DOC = ROOT / "plan/known-mods.md"


def where(mod: dict) -> str:
    scope = mod["scope"]
    if scope == "metal":
        value = "Metal"
    elif scope == "anyRenderer":
        value = "Any renderer"
    else:
        value = "26.x on MobileGlues/ANGLE"
    conditions = []
    if mod.get("loaders"):
        conditions.append(", ".join(mod["loaders"]))
    versions = mod.get("gameVersions")
    if versions and versions != ["26.x"]:
        conditions.append(", ".join(versions))
    return value + (" (" + "; ".join(conditions) + ")" if conditions else "")


def evidence(mod: dict) -> str:
    if mod["evidence"] == "expected":
        return "expected"
    ref = mod.get("evidenceRef")
    href = "../" + ref if ref and ref.startswith("plan/") else ref
    return f"device ([evidence]({href}))" if href else "device"


def render(data: dict) -> str:
    rows = [
        "# Known mod compatibility",
        "",
        "This table is generated from [`known-mods.json`](../app/UI/Sources/CofreKit/Resources/known-mods.json).",
        "",
        "| Mod | Where it fails | Why | Evidence |",
        "|---|---|---|---|",
    ]
    for mod in data["mods"]:
        rows.append(f"| {mod['name']} | {where(mod)} | {mod['reason']} | {evidence(mod)} |")
    return "\n".join(rows) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="rewrite the Markdown table")
    args = parser.parse_args()
    output = render(json.loads(DATA.read_text()))
    if args.write:
        DOC.write_text(output)
        return 0
    actual = DOC.read_text() if DOC.exists() else ""
    if actual != output:
        print(f"{DOC} is out of date; run scripts/check-known-mods.py --write")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
