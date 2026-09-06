#!/usr/bin/env python3
"""Generate a compact med_v0 theater pack sized to the Terra outline.

989 coastal-band hexes, 17 harbors, 34 shipping lanes. Geography is a
stand-in Mediterranean ribbon (50 km flat-top hexes, EPSG:4326 centroids)
so KEY_2 can load a large theater. Not the locked coastline mesh.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

HEX_KM = 50.0
ORIGIN_LON = 16.0
ORIGIN_LAT = 38.0
TARGET_CELLS = 989
SQRT3 = math.sqrt(3.0)

# Country / island boxes (wider than the sea so we can pick a 989 coastal ribbon).
LAND_BOXES = [
    (-9.8, 35.8, 3.5, 44.0),   # Iberia
    (-2.0, 42.0, 7.8, 45.2),   # S. France
    (6.4, 37.5, 18.7, 46.2),   # Italy
    (12.2, 36.5, 15.8, 38.4),  # Sicily
    (8.0, 38.7, 10.0, 41.4),   # Sardinia
    (8.4, 41.2, 9.8, 43.1),    # Corsica
    (2.1, 38.5, 4.5, 40.2),    # Balearics
    (13.3, 35.0, 29.4, 45.4),  # Balkans / Greece
    (23.3, 34.7, 26.6, 35.8),  # Crete
    (32.1, 34.4, 34.8, 35.8),  # Cyprus
    (26.0, 36.0, 42.1, 42.4),  # Anatolia
    (33.8, 31.2, 36.7, 37.0),  # Levant
    (24.5, 29.6, 34.5, 31.8),  # Egypt
    (9.3, 30.0, 25.2, 33.2),   # Libya
    (7.4, 32.8, 11.7, 37.5),   # Tunisia
    (-2.4, 34.6, 8.9, 37.3),   # Algeria coast
    (-10.1, 34.6, -0.8, 36.3), # Morocco / Tangier
    (14.1, 35.75, 14.65, 36.15),  # Malta
]

# Approximate Mediterranean sea sample points — rank hexes by nearness.
MED_SEA = [
    (-5.0, 36.1), (-3.0, 36.4), (0.0, 36.6), (3.0, 37.2), (5.5, 41.5),
    (6.5, 43.0), (8.5, 43.5), (9.5, 40.0), (10.5, 38.5), (12.0, 38.0),
    (13.5, 36.5), (14.5, 35.9), (15.0, 40.5), (16.5, 42.0), (18.0, 41.0),
    (19.0, 38.5), (20.0, 36.5), (22.0, 35.8), (24.0, 35.5), (26.0, 36.0),
    (28.0, 35.5), (30.0, 32.5), (32.0, 32.0), (33.5, 33.5), (34.5, 34.5),
    (18.0, 33.5), (14.0, 33.0), (11.0, 34.0), (8.0, 36.5), (5.0, 37.0),
]

HARBORS = [
    ("p_gibraltar", "h_gibraltar", "Gibraltar", -5.35, 36.14, True),
    ("p_tangier", "h_tangier", "Tangier", -5.81, 35.76, False),
    ("p_barcelona", "h_barcelona", "Barcelona", 2.17, 41.38, False),
    ("p_marseille", "h_marseille", "Marseille", 5.37, 43.30, False),
    ("p_genoa", "h_genoa", "Genoa", 8.95, 44.41, False),
    ("p_naples", "h_naples", "Naples", 14.27, 40.85, False),
    ("p_palermo", "h_palermo", "Palermo", 13.36, 38.12, False),
    ("p_valletta", "h_valletta", "Valletta", 14.51, 35.90, False),
    ("p_tunis", "h_tunis", "Tunis", 10.18, 36.81, False),
    ("p_algiers", "h_algiers", "Algiers", 3.06, 36.75, False),
    ("p_tripoli", "h_tripoli", "Tripoli", 13.19, 32.89, False),
    ("p_athens", "h_athens", "Athens", 23.72, 37.94, False),
    ("p_istanbul", "h_istanbul", "Istanbul", 29.00, 41.01, False),
    ("p_izmir", "h_izmir", "Izmir", 27.14, 38.42, False),
    ("p_alexandria", "h_alexandria", "Alexandria", 29.92, 31.20, False),
    ("p_suez", "h_suez", "Suez", 32.35, 29.97, True),
    ("p_haifa", "h_haifa", "Haifa", 35.00, 32.82, False),
]

LANES = [
    ("l_gibraltar_tangier", "h_gibraltar", "h_tangier"),
    ("l_gibraltar_algiers", "h_gibraltar", "h_algiers"),
    ("l_gibraltar_barcelona", "h_gibraltar", "h_barcelona"),
    ("l_tangier_algiers", "h_tangier", "h_algiers"),
    ("l_tangier_barcelona", "h_tangier", "h_barcelona"),
    ("l_barcelona_marseille", "h_barcelona", "h_marseille"),
    ("l_barcelona_algiers", "h_barcelona", "h_algiers"),
    ("l_marseille_genoa", "h_marseille", "h_genoa"),
    ("l_marseille_algiers", "h_marseille", "h_algiers"),
    ("l_genoa_naples", "h_genoa", "h_naples"),
    ("l_genoa_tunis", "h_genoa", "h_tunis"),
    ("l_genoa_athens", "h_genoa", "h_athens"),
    ("l_naples_palermo", "h_naples", "h_palermo"),
    ("l_naples_tunis", "h_naples", "h_tunis"),
    ("l_naples_athens", "h_naples", "h_athens"),
    ("l_palermo_tunis", "h_palermo", "h_tunis"),
    ("l_palermo_valletta", "h_palermo", "h_valletta"),
    ("l_palermo_athens", "h_palermo", "h_athens"),
    ("l_valletta_tripoli", "h_valletta", "h_tripoli"),
    ("l_valletta_athens", "h_valletta", "h_athens"),
    ("l_valletta_alexandria", "h_valletta", "h_alexandria"),
    ("l_tunis_algiers", "h_tunis", "h_algiers"),
    ("l_tunis_tripoli", "h_tunis", "h_tripoli"),
    ("l_tripoli_alexandria", "h_tripoli", "h_alexandria"),
    ("l_alexandria_suez", "h_alexandria", "h_suez"),
    ("l_alexandria_haifa", "h_alexandria", "h_haifa"),
    ("l_suez_haifa", "h_suez", "h_haifa"),
    ("l_athens_istanbul", "h_athens", "h_istanbul"),
    ("l_athens_izmir", "h_athens", "h_izmir"),
    ("l_athens_alexandria", "h_athens", "h_alexandria"),
    ("l_athens_haifa", "h_athens", "h_haifa"),
    ("l_istanbul_izmir", "h_istanbul", "h_izmir"),
    ("l_izmir_haifa", "h_izmir", "h_haifa"),
    ("l_istanbul_haifa", "h_istanbul", "h_haifa"),
]

AXIAL_DIRS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]


def lonlat_to_km(lon: float, lat: float) -> tuple[float, float]:
    x = (lon - ORIGIN_LON) * 111.32 * math.cos(math.radians(ORIGIN_LAT))
    y = (lat - ORIGIN_LAT) * 110.57
    return x, y


def km_to_lonlat(x: float, y: float) -> tuple[float, float]:
    lon = x / (111.32 * math.cos(math.radians(ORIGIN_LAT))) + ORIGIN_LON
    lat = y / 110.57 + ORIGIN_LAT
    return lon, lat


def axial_to_km(q: int, r: int) -> tuple[float, float]:
    x = HEX_KM * (1.5 * q)
    y = HEX_KM * (SQRT3 * (r + q * 0.5))
    return x, y


def axial_round(qf: float, rf: float) -> tuple[int, int]:
    x, z = qf, rf
    y = -x - z
    rx, ry, rz = round(x), round(y), round(z)
    dx, dy, dz = abs(rx - x), abs(ry - y), abs(rz - z)
    if dx > dy and dx > dz:
        rx = -ry - rz
    elif dy > dz:
        ry = -rx - rz
    else:
        rz = -rx - ry
    return int(rx), int(rz)


def lonlat_to_axial(lon: float, lat: float) -> tuple[int, int]:
    x, y = lonlat_to_km(lon, lat)
    q = (2.0 / 3.0 * x) / HEX_KM
    r = ((-1.0 / 3.0) * x + (SQRT3 / 3.0) * y) / HEX_KM
    return axial_round(q, r)


def in_box(lon: float, lat: float, box: tuple[float, float, float, float]) -> bool:
    west, south, east, north = box
    return west <= lon <= east and south <= lat <= north


def coarse_land(lon: float, lat: float) -> bool:
    if not (29.4 <= lat <= 46.4 and -10.3 <= lon <= 42.3):
        return False
    return any(in_box(lon, lat, b) for b in LAND_BOXES)


def dist_to_sea(lon: float, lat: float) -> float:
    return min(math.hypot(lon - x, lat - y) for x, y in MED_SEA)


def terrain_for(lon: float, lat: float) -> str:
    if lat >= 44.0 and 5.5 <= lon <= 16.0:
        return "mountain"
    if 27.0 <= lon <= 42.0 and 37.5 <= lat <= 41.5 and lat >= 38.2:
        return "mountain"
    if lon >= 24.0 and lat <= 32.8:
        return "desert"
    if lon <= 12.0 and lat <= 36.6:
        return "desert"
    if 32.5 <= lon <= 37.0 and lat <= 36.2:
        return "desert"
    if (abs(lon - 12.5) < 0.7 and abs(lat - 41.9) < 0.5) or (
        abs(lon - 14.3) < 0.4 and abs(lat - 40.8) < 0.4
    ):
        return "urban"
    if abs(lon - 23.7) < 0.5 and abs(lat - 38.0) < 0.4:
        return "urban"
    if abs(lon - 29.0) < 0.5 and abs(lat - 41.0) < 0.4:
        return "urban"
    if abs(lon - 31.2) < 0.6 and abs(lat - 30.1) < 0.5:
        return "urban"
    if lat >= 43.4:
        return "forest"
    if 19.5 <= lon <= 24.5 and 36.5 <= lat <= 40.5:
        return "hill"
    if lon <= -4.0 and lat <= 38.0:
        return "hill"
    if 8.5 <= lon <= 16.0 and 37.8 <= lat <= 39.5:
        return "hill"
    return "plains"


def default_owner(lon: float, lat: float) -> str:
    if lon <= 0.8 or (lon <= 4.5 and lat <= 36.8):
        return "player"
    if lon >= 28.5:
        return "enemy"
    return "none"


def dist2(a: tuple[float, float], b: tuple[float, float]) -> float:
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2


def generate_cells() -> list[dict]:
    candidates: list[tuple[float, int, int, float, float]] = []
    for q in range(-46, 47):
        for r in range(-36, 32):
            x, y = axial_to_km(q, r)
            lon, lat = km_to_lonlat(x, y)
            if not coarse_land(lon, lat):
                continue
            candidates.append((dist_to_sea(lon, lat), q, r, lon, lat))
    # Grow a one-hex coastal/inland ring so we can reach the Terra 989 count.
    have = {(q, r) for _s, q, r, _lon, _lat in candidates}
    extras: list[tuple[float, int, int, float, float]] = []
    for _s, q, r, _lon, _lat in candidates:
        for dq, dr in AXIAL_DIRS:
            nq, nr = q + dq, r + dr
            if (nq, nr) in have:
                continue
            x, y = axial_to_km(nq, nr)
            lon, lat = km_to_lonlat(x, y)
            if not (29.2 <= lat <= 46.6 and -10.5 <= lon <= 42.5):
                continue
            have.add((nq, nr))
            extras.append((dist_to_sea(lon, lat) + 0.35, nq, nr, lon, lat))
    candidates.extend(extras)
    candidates.sort()
    by_qr = {(q, r): (score, q, r, lon, lat) for score, q, r, lon, lat in candidates}
    forced: list[tuple[float, int, int, float, float]] = []
    for _pid, _hid, _name, lon, lat, _choke in HARBORS:
        q, r = lonlat_to_axial(lon, lat)
        if (q, r) in by_qr:
            forced.append(by_qr[(q, r)])
        else:
            x, y = axial_to_km(q, r)
            flon, flat = km_to_lonlat(x, y)
            forced.append((0.0, q, r, flon, flat))
    rest = [c for c in candidates if (c[1], c[2]) not in {(x[1], x[2]) for x in forced}]
    picked = forced + rest
    # de-dupe axial
    seen_qr = set()
    unique = []
    for item in picked:
        key = (item[1], item[2])
        if key in seen_qr:
            continue
        seen_qr.add(key)
        unique.append(item)
    picked = unique[:TARGET_CELLS]
    cells = []
    for _score, q, r, lon, lat in picked:
        cells.append(
            {
                "cell_id": f"c_{q}_{r}",
                "q": q,
                "r": r,
                "terrain_tag": terrain_for(lon, lat),
                "is_coast": False,
                "harbor_site": False,
                "default_owner": default_owner(lon, lat),
                "centroid": {"lon": round(lon, 4), "lat": round(lat, 4)},
            }
        )
    by_axial = {(c["q"], c["r"]): c for c in cells}
    for cell in cells:
        q, r = cell["q"], cell["r"]
        coast = False
        for dq, dr in AXIAL_DIRS:
            if (q + dq, r + dr) not in by_axial:
                coast = True
                break
        cell["is_coast"] = coast
    return cells


def assign_harbors(cells: list[dict]) -> list[dict]:
    remaining = list(cells)
    ports = []
    used = set()
    for port_id, harbor_id, name, lon, lat, choke in HARBORS:
        best = min(remaining, key=lambda c: dist2((c["centroid"]["lon"], c["centroid"]["lat"]), (lon, lat)))
        remaining.remove(best)
        used.add(best["cell_id"])
        best["harbor_site"] = True
        best["is_coast"] = True
        ports.append(
            {
                "port_id": port_id,
                "cell_id": best["cell_id"],
                "harbor_node_id": harbor_id,
                "name": name,
                "chokepoint": choke,
            }
        )
    return ports


def adjacency(cells: list[dict]) -> list[dict]:
    by_axial = {(c["q"], c["r"]): c["cell_id"] for c in cells}
    edges = []
    seen = set()
    for cell in cells:
        q, r = cell["q"], cell["r"]
        a = cell["cell_id"]
        for dq, dr in AXIAL_DIRS:
            b = by_axial.get((q + dq, r + dr))
            if not b:
                continue
            key = tuple(sorted((a, b)))
            if key in seen:
                continue
            seen.add(key)
            edges.append({"a": a, "b": b, "kind": "land"})
    return edges


def write_json(path: Path, data) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n")


def main() -> None:
    out = Path(__file__).resolve().parents[1] / "data" / "theaters" / "med_v0"
    out.mkdir(parents=True, exist_ok=True)
    cells = generate_cells()
    if len(cells) != TARGET_CELLS:
        raise SystemExit(f"expected {TARGET_CELLS} cells, got {len(cells)}")
    ports = assign_harbors(cells)
    edges = adjacency(cells)
    cell_owners = {c["cell_id"]: c["default_owner"] for c in cells if c["default_owner"] != "none"}
    write_json(
        out / "meta.json",
        {
            "theater_id": "med_v0",
            "name": "Mediterranean v0",
            "hex_km": 50,
            "crs": "EPSG:4326",
            "cell_count": len(cells),
            "harbor_count": len(ports),
            "lane_count": len(LANES),
            "note": (
                "M0 stand-in sized to the Terra pack (989 / 17 / 34). "
                "Coastline is a generated ribbon, not the locked mesh."
            ),
        },
    )
    write_json(out / "cells.json", cells)
    write_json(out / "adjacency.json", {"edges": edges})
    write_json(out / "ports.json", {"ports": ports})
    write_json(
        out / "ownership_seed.json",
        {
            "factions": [
                {"id": "player", "name": "Player", "color": "#2E6BFF"},
                {"id": "enemy", "name": "Enemy", "color": "#E23B3B"},
                {"id": "none", "name": "Neutral", "color": "#9E9E9E"},
            ],
            "cell_owners": cell_owners,
        },
    )
    write_json(
        out / "shipping_graph.json",
        {
            "nodes": [
                {
                    "harbor_node_id": p["harbor_node_id"],
                    "port_id": p["port_id"],
                    "cell_id": p["cell_id"],
                }
                for p in ports
            ],
            "edges": [
                {"lane_id": lid, "a": a, "b": b, "weight": 1.0, "state": "Open"}
                for lid, a, b in LANES
            ],
        },
    )
    write_json(out / "annexation.json", {"progress": {}})
    write_json(out / "regions.json", {"regions": []})
    write_json(
        out / "terrain_costs.json",
        {
            "note": "Design may retune",
            "enter_time_sec": {
                "plains": 2,
                "urban": 2,
                "forest": 3,
                "desert": 3,
                "hill": 4,
                "swamp": 5,
                "mountain": 6,
                "water": None,
            },
        },
    )
    print(f"wrote {len(cells)} cells, {len(ports)} ports, {len(LANES)} lanes, {len(edges)} edges -> {out}")


if __name__ == "__main__":
    main()
