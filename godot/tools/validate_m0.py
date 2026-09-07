#!/usr/bin/env python3
"""Headless checks for the Atlas M0 Godot scaffold (no Godot binary required)."""

from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEATERS = ROOT / "data" / "theaters"
REQUIRED = [
    "meta.json",
    "cells.json",
    "adjacency.json",
    "ports.json",
    "ownership_seed.json",
    "shipping_graph.json",
    "annexation.json",
    "terrain_costs.json",
    "regions.json",
]
ERRORS: list[str] = []


def err(msg: str) -> None:
    ERRORS.append(msg)


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except Exception as exc:  # noqa: BLE001
        err(f"invalid JSON {path}: {exc}")
        return None


def check_no_lanes_json() -> None:
    for found in THEATERS.rglob("lanes.json"):
        err(f"lanes.json is forbidden: {found}")


def check_gdscript_api() -> None:
    ms = (ROOT / "autoload" / "MapService.gd").read_text()
    if "func get_cell_owner(" not in ms:
        err("MapService must define get_cell_owner")
    if re.search(r"func get_owner\s*\(", ms):
        err("MapService must not define get_owner (clashes with Node.get_owner; use get_cell_owner)")
    own = ROOT / "autoload" / "OwnershipService.gd"
    if own.is_file():
        ot = own.read_text()
        if "func get_cell_owner(" not in ot or "func set_cell_owner(" not in ot:
            err("OwnershipService must define get_cell_owner / set_cell_owner")
        if re.search(r"func get_owner\s*\(", ot):
            err("OwnershipService must not define get_owner")
    world = (ROOT / "scenes" / "WorldMap.gd").read_text()
    if "get_owner(" in world:
        err("WorldMap.gd must call get_cell_owner, not get_owner")
    if "get_cell_owner(" not in world:
        err("WorldMap.gd must use MapService.get_cell_owner")
    main = (ROOT / "scenes" / "Main.gd").read_text()
    if 'load_theater("stub_med")' not in main:
        err("Main.gd must default-load stub_med")
    if "KEY_1" not in main or "KEY_2" not in main:
        err("Main.gd must switch theaters on KEY_1 / KEY_2")


def check_project() -> None:
    pg = (ROOT / "project.godot").read_text()
    if 'run/main_scene="res://scenes/Main.tscn"' not in pg:
        err("project.godot main scene must be scenes/Main.tscn")
    if "MapService=" not in pg or "Balance=" not in pg:
        err("project.godot must autoload MapService and Balance")
    if "SimTick=" not in pg:
        err("project.godot should autoload optional SimTick stub")
    for al in ("OwnershipService=", "EconomyService=", "BuildingService=", "AnnexService=", "ShippingService="):
        if al not in pg:
            err(f"project.godot must autoload {al.rstrip('=')}")
    for rel in (
        "scenes/Main.tscn",
        "scenes/WorldMap.tscn",
        "scenes/Main.gd",
        "scenes/WorldMap.gd",
        "autoload/MapService.gd",
        "autoload/Balance.gd",
        "data/balance/slice_v1.json",
    ):
        if not (ROOT / rel).is_file():
            err(f"missing {rel}")


def cells_list(raw) -> list:
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict) and isinstance(raw.get("cells"), list):
        return raw["cells"]
    return []


def check_theater(name: str, expect_cells: int | None = None, expect_ports: int | None = None, expect_lanes: int | None = None) -> None:
    folder = THEATERS / name
    if not folder.is_dir():
        err(f"missing theater {name}")
        return
    raw = {}
    for fname in REQUIRED:
        path = folder / fname
        if not path.is_file():
            err(f"{name}: missing {fname}")
            continue
        raw[fname] = load_json(path)
    cells = cells_list(raw.get("cells.json") or [])
    ids = [c.get("cell_id") for c in cells if isinstance(c, dict)]
    if len(ids) != len(set(ids)):
        err(f"{name}: duplicate cell_id")
    if expect_cells is not None and len(cells) != expect_cells:
        err(f"{name}: expected {expect_cells} cells, got {len(cells)}")
    for cell in cells:
        for key in ("cell_id", "q", "r", "terrain_tag", "is_coast", "harbor_site", "default_owner", "centroid"):
            if key not in cell:
                err(f"{name}: cell missing {key}")
                break
        owner = str(cell.get("default_owner", ""))
        if owner not in ("none", "player", "enemy"):
            err(f"{name}: bad default_owner {owner}")
    ports_raw = raw.get("ports.json") or {}
    ports = ports_raw.get("ports", ports_raw) if isinstance(ports_raw, dict) else ports_raw
    if isinstance(ports, dict):
        ports = list(ports.values())
    if expect_ports is not None and len(ports) != expect_ports:
        err(f"{name}: expected {expect_ports} ports, got {len(ports)}")
    if name == "stub_med":
        by_id = {p.get("port_id"): p for p in ports if isinstance(p, dict)}
        for pid, cid in (("p_gibraltar", "gibraltar"), ("p_suez", "suez")):
            port = by_id.get(pid) or {}
            if port.get("chokepoint") is not True:
                err(f"stub_med {pid} must have chokepoint:true")
            if port.get("chokepoint_id") != cid:
                err(f"stub_med {pid} chokepoint_id must be {cid}")
    sg = raw.get("shipping_graph.json") or {}
    edges = sg.get("edges", []) if isinstance(sg, dict) else []
    if expect_lanes is not None and len(edges) != expect_lanes:
        err(f"{name}: expected {expect_lanes} lanes, got {len(edges)}")
    for edge in edges:
        for key in ("lane_id", "a", "b"):
            if key not in edge:
                err(f"{name}: lane missing {key}")
        state = edge.get("state", "Open")
        if state not in ("Open", "Contested", "Blocked"):
            err(f"{name}: bad lane state {state}")
    seed = raw.get("ownership_seed.json") or {}
    if "factions" not in seed or "cell_owners" not in seed:
        err(f"{name}: ownership_seed needs factions + cell_owners")
    meta = raw.get("meta.json") or {}
    if meta.get("theater_id") != name:
        err(f"{name}: meta.theater_id should be {name}")
    if meta.get("crs") != "EPSG:4326":
        err(f"{name}: meta.crs should be EPSG:4326")


def check_balance() -> None:
    data = load_json(ROOT / "data" / "balance" / "slice_v1.json")
    if not isinstance(data, dict):
        return
    if data.get("tick_sec") != 1.0:
        err("slice_v1 tick_sec must be 1.0")
    et = data.get("enter_time_sec", {})
    expect = {
        "plains": 2,
        "urban": 2,
        "forest": 3,
        "desert": 3,
        "hill": 4,
        "swamp": 5,
        "mountain": 6,
    }
    for k, v in expect.items():
        if et.get(k) != v:
            err(f"slice_v1 enter_time_sec.{k} expected {v}, got {et.get(k)}")
    if et.get("water") is not None:
        err("slice_v1 water enter time must be null")
    mm = data.get("mobility_mult", {})
    if mm.get("Road") != 0.6 or mm.get("Rail") != 0.4:
        err("slice_v1 mobility_mult Road/Rail must be 0.6/0.4")
    sea = data.get("sea_transit_sec", {})
    if sea.get("Open") != 8 or sea.get("Contested") != 12 or sea.get("Blocked") is not None:
        err("slice_v1 sea_transit_sec Open/Contested/Blocked must be 8/12/null")
    st = data.get("supply_trade", {})
    if st.get("Contested") != 1 or st.get("Open") != 3:
        err("slice_v1 supply_trade Contested/Open must be +1/+3")
    supply = data.get("supply") or {}
    if supply.get("per_land") != 1 or supply.get("per_factory") != 8:
        err("slice_v1 supply must be 1/land + 8/factory")
    annex = data.get("annex") or {}
    if annex.get("unclaimed_base_pct") != 12 or annex.get("enemy_empty_base_pct") != 5:
        err("slice_v1 annex unclaimed/enemy-empty bases must be 12/5")
    if annex.get("vacate_decay_pct") != 25 or annex.get("flip_at") != 100:
        err("slice_v1 annex vacate/flip must be 25/100")
    if (data.get("win") or {}).get("land_control") != 0.7:
        err("slice_v1 win.land_control must be 0.7")
    buildings = data.get("buildings") or {}
    expect_b = {
        "Harbor": (200, 20),
        "Factory": (150, 15),
        "Road": (40, 5),
        "Bunker": (50, 5),
    }
    for b, (cost, ticks) in expect_b.items():
        rec = buildings.get(b) or {}
        if rec.get("cost") != cost or rec.get("build_ticks") != ticks:
            err(f"slice_v1 {b} must be {cost}/{ticks}, got {rec}")
    for b in ("Harbor", "Factory", "Road", "Rail", "Bunker", "AA", "SAM"):
        if b not in buildings:
            err(f"slice_v1 missing building {b}")
    lc = data.get("lane_control") or {}
    if not lc.get("contest_if_one_end_enemy") or not lc.get("block_if_both_ends_enemy"):
        err("slice_v1 lane_control must contest one enemy end and block both")


def check_hex_math() -> None:
    s = 48.0
    q, r = 2, 1
    x = s * (1.5 * q)
    y = s * (math.sqrt(3.0) * (r + q * 0.5))
    qf = (2.0 / 3.0 * x) / s
    rf = ((-1.0 / 3.0) * x + (math.sqrt(3.0) / 3.0) * y) / s
    if abs(qf - q) > 1e-6 or abs(rf - r) > 1e-6:
        err(f"axial round-trip failed: {(qf, rf)} vs {(q, r)}")


def main() -> int:
    check_project()
    check_gdscript_api()
    check_no_lanes_json()
    check_balance()
    check_hex_math()
    check_theater("stub_med", expect_cells=8, expect_ports=2, expect_lanes=1)
    check_theater("med_v0", expect_cells=989, expect_ports=17, expect_lanes=34)
    stub_cells = cells_list(load_json(THEATERS / "stub_med" / "cells.json") or [])
    ids = {c["cell_id"] for c in stub_cells}
    for cid in ("c_0_0", "c_1_0", "c_2_0", "c_3_0", "c_4_0", "c_5_0", "c_1_1"):
        if cid not in ids:
            err(f"stub_med missing {cid}")
    if ERRORS:
        print("FAIL")
        for e in ERRORS:
            print(" -", e)
        return 1
    print("OK: M0 scaffold checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
