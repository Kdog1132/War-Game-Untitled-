#!/usr/bin/env python3
"""Static checks for Atlas M2–M6 (no Godot binary required)."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []


def err(msg: str) -> None:
    ERRORS.append(msg)


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except Exception as exc:  # noqa: BLE001
        err(f"invalid JSON {path}: {exc}")
        return None


def check_files() -> None:
    for rel in (
        "autoload/OwnershipService.gd",
        "autoload/AnnexService.gd",
        "autoload/EconomyService.gd",
        "autoload/BuildingService.gd",
        "autoload/ShippingService.gd",
        "autoload/SimTick.gd",
        "tools/prove_annex.gd",
        "tools/prove_economy.gd",
        "tools/prove_shipping.gd",
        "data/balance/slice_v1.json",
    ):
        if not (ROOT / rel).is_file():
            err(f"missing {rel}")


def check_no_get_owner() -> None:
    for path in (ROOT / "autoload").glob("*.gd"):
        text = path.read_text()
        if re.search(r"func get_owner\s*\(", text):
            err(f"{path.name} must not define get_owner")


def check_tokens() -> None:
    annex = (ROOT / "tools" / "prove_annex.gd").read_text()
    if "ANNEX_FLIP" not in annex:
        err("prove_annex.gd must print ANNEX_FLIP")
    eco = (ROOT / "tools" / "prove_economy.gd").read_text()
    if "SUPPLY_EARN" not in eco or "SUPPLY_SPEND" not in eco:
        err("prove_economy.gd must print SUPPLY_EARN and SUPPLY_SPEND")
    ship = (ROOT / "tools" / "prove_shipping.gd").read_text()
    if "FERRY_START" not in ship or "FERRY_ARRIVE" not in ship:
        err("prove_shipping.gd must print FERRY_START and FERRY_ARRIVE")
    world = (ROOT / "scenes" / "WorldMap.gd").read_text()
    if "tint_factor" not in world or "get_cell_owner(" not in world:
        err("WorldMap must tint via get_cell_owner and annex meter lerp")
    main = (ROOT / "scenes" / "Main.gd").read_text()
    if "Supply" not in main or "Annex" not in main or "Lanes" not in main:
        err("Main HUD must show Supply, Annex, and Lanes")


def annex_rate(owner: str, strength: float, cfg: dict) -> float:
    if owner == "none":
        return cfg["unclaimed_base_pct"] + min(cfg["unclaimed_str_cap"], cfg["unclaimed_str_scale"] * strength)
    return cfg["enemy_empty_base_pct"] + min(cfg["enemy_empty_str_cap"], cfg["enemy_empty_str_scale"] * strength)


def check_annex_math() -> None:
    data = load_json(ROOT / "data" / "balance" / "slice_v1.json")
    if not isinstance(data, dict):
        return
    cfg = data.get("annex") or {}
    unclaimed = annex_rate("none", 100.0, cfg)
    enemy = annex_rate("enemy", 100.0, cfg)
    if abs(unclaimed - 14.0) > 1e-9:
        err(f"unclaimed rate at str 100 should be 14, got {unclaimed}")
    if abs(enemy - 6.5) > 1e-9:
        err(f"enemy-empty rate at str 100 should be 6.5, got {enemy}")
    t = 0.0
    progress = 0.0
    while t < 20.0 and progress < 100.0:
        progress = min(100.0, progress + unclaimed * 0.25)
        t += 0.25
    if progress < 100.0:
        err("annex sim failed to reach 100")
    if t > 8.0:
        err(f"unclaimed flip at str 100 should be ~7.14s, got {t}")


def check_readme() -> None:
    readme = (ROOT / "README.md").read_text()
    if "Godot 4.2" not in readme:
        err("godot/README.md must mention Godot 4.2")
    if "prove_annex.gd" not in readme or "prove_economy.gd" not in readme or "prove_shipping.gd" not in readme:
        err("godot/README.md must document prove_*.gd run steps")


def main() -> int:
    check_files()
    check_no_get_owner()
    check_tokens()
    check_annex_math()
    check_readme()
    if ERRORS:
        print("FAIL")
        for e in ERRORS:
            print(" -", e)
        return 1
    print("OK: M2–M6 checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
