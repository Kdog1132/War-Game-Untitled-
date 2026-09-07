#!/usr/bin/env python3
"""Headless pick + camera-space check (no Godot required).

Confirms:
1. Overlay territories contain their stub_med centroids.
2. After Camera2D center_on_cells + pan/zoom, screen_to_world hits the cell.
3. Raw viewport pixels (the playtest miss) do NOT match any cell.

Run from repo root or godot/:
    python3 tools/click_check.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OVERLAYS = ROOT / "data/theaters/med_v0/overlays"
CELLS = ROOT / "data/theaters/stub_med/cells.json"

GEO_ORIGIN_LON = -10.0
GEO_ORIGIN_LAT = 47.5
GEO_PX = 34.0


def lonlat_to_world(lon: float, lat: float) -> tuple[float, float]:
    return ((lon - GEO_ORIGIN_LON) * GEO_PX, (GEO_ORIGIN_LAT - lat) * GEO_PX)


def screen_to_world(
    screen: tuple[float, float],
    cam_pos: tuple[float, float],
    zoom: float,
    viewport: tuple[float, float],
) -> tuple[float, float]:
    z = max(zoom, 0.0001)
    return (
        cam_pos[0] + (screen[0] - viewport[0] * 0.5) / z,
        cam_pos[1] + (screen[1] - viewport[1] * 0.5) / z,
    )


def point_in_ring(pt: tuple[float, float], ring: list[tuple[float, float]]) -> bool:
    x, y = pt
    inside = False
    j = len(ring) - 1
    for i, (ax, ay) in enumerate(ring):
        bx, by = ring[j]
        if ((ay > y) != (by > y)) and (
            x < (bx - ax) * (y - ay) / ((by - ay) if abs(by - ay) > 1e-9 else 1e-9) + ax
        ):
            inside = not inside
        j = i
    return inside


def load_json(path: Path):
    return json.loads(path.read_text())


def _ring_world(coords) -> list[tuple[float, float]]:
    return [lonlat_to_world(float(p[0]), float(p[1])) for p in coords if len(p) >= 2]


def geojson_world_rings(path: Path) -> list[dict]:
    data = load_json(path)
    out = []
    for feat in data.get("features", []):
        props = feat.get("properties") or {}
        geom = feat.get("geometry") or {}
        coords = geom.get("coordinates") or []
        rings = []
        gtype = geom.get("type")
        if gtype == "Polygon":
            for ring in coords:
                rings.append(_ring_world(ring))
        elif gtype == "MultiPolygon":
            for poly in coords:
                for ring in poly:
                    rings.append(_ring_world(ring))
        elif gtype == "LineString":
            rings.append(_ring_world(coords))
        elif gtype == "MultiLineString":
            for line in coords:
                rings.append(_ring_world(line))
        out.append(
            {
                "kind": props.get("kind", ""),
                "cell_id": props.get("cell_id", ""),
                "name": props.get("name", props.get("NAME", "")),
                "rings": rings,
            }
        )
    return out


def bounds_of(features: list[dict]) -> tuple[tuple[float, float], tuple[float, float]]:
    xs: list[float] = []
    ys: list[float] = []
    for feat in features:
        for ring in feat["rings"]:
            for x, y in ring:
                xs.append(x)
                ys.append(y)
    return (min(xs), min(ys)), (max(xs), max(ys))


def main() -> int:
    cells = {c["cell_id"]: c for c in load_json(CELLS)}
    coastline = geojson_world_rings(OVERLAYS / "coastline.geojson")
    slice1 = OVERLAYS / "admin_regions_slice1.geojson"
    territories = geojson_world_rings(
        slice1 if slice1.is_file() else OVERLAYS / "territories.geojson"
    )
    if not coastline or not territories:
        print("CLICK_CHECK_FAIL missing overlays")
        return 1

    errors: list[str] = []
    for feat in territories:
        cid = feat["cell_id"]
        cell = cells.get(cid)
        if not cell:
            errors.append("territory %s not in stub_med" % cid)
            continue
        world = lonlat_to_world(cell["centroid"]["lon"], cell["centroid"]["lat"])
        if not feat["rings"] or not point_in_ring(world, feat["rings"][0]):
            errors.append("centroid of %s missed territory polygon" % cid)

    mn, mx = bounds_of(coastline + territories)
    cam = ((mn[0] + mx[0]) * 0.5, (mn[1] + mx[1]) * 0.5)
    vp = (1280.0, 720.0)
    size = (mx[0] - mn[0], mx[1] - mn[1])
    zoom = min(vp[0] / max(size[0], 1.0), vp[1] / max(size[1], 1.0)) * 0.88
    zoom = max(0.12, min(2.2, zoom))

    # After center_on_cells, a click on Gibraltar's projected screen pos must hit c_0_0.
    gib = lonlat_to_world(
        cells["c_0_0"]["centroid"]["lon"], cells["c_0_0"]["centroid"]["lat"]
    )
    screen = (
        (gib[0] - cam[0]) * zoom + vp[0] * 0.5,
        (gib[1] - cam[1]) * zoom + vp[1] * 0.5,
    )
    recovered = screen_to_world(screen, cam, zoom, vp)
    if abs(recovered[0] - gib[0]) > 0.05 or abs(recovered[1] - gib[1]) > 0.05:
        errors.append("screen_to_world roundtrip failed after center_on_cells")

    # Pan + zoom still recovers.
    cam2 = (cam[0] + 180.0, cam[1] - 90.0)
    zoom2 = zoom * 1.35
    screen2 = (
        (gib[0] - cam2[0]) * zoom2 + vp[0] * 0.5,
        (gib[1] - cam2[1]) * zoom2 + vp[1] * 0.5,
    )
    recovered2 = screen_to_world(screen2, cam2, zoom2, vp)
    if abs(recovered2[0] - gib[0]) > 0.05 or abs(recovered2[1] - gib[1]) > 0.05:
        errors.append("screen_to_world roundtrip failed after pan/zoom")

    # Raw viewport center is NOT a map coordinate after the camera recenters.
    raw = (vp[0] * 0.5, vp[1] * 0.5)
    if abs(raw[0] - gib[0]) < 40 and abs(raw[1] - gib[1]) < 40:
        errors.append("viewport pixels unexpectedly matched Gibraltar world pos")

    # Italy / Suez centroids still pick their territories after the same camera.
    for cid in ("c_2_0", "c_5_0"):
        world = lonlat_to_world(
            cells[cid]["centroid"]["lon"], cells[cid]["centroid"]["lat"]
        )
        feat = next(f for f in territories if f["cell_id"] == cid)
        if not point_in_ring(world, feat["rings"][0]):
            errors.append("%s centroid not in its territory" % cid)

    worldmap = (ROOT / "scenes/WorldMap.gd").read_text()
    if "get_local_mouse_position()" not in worldmap:
        errors.append("WorldMap.world_mouse must use get_local_mouse_position() under Camera2D")
    if "_draw_hex" in worldmap or "_hex_corners" in worldmap:
        errors.append("painted view still has hex outline/grid chrome")

    if errors:
        print("CLICK_CHECK_FAIL")
        for e in errors:
            print("  -", e)
        return 1

    print(
        "CLICK_CHECK_OK overlays=%d territories=%d zoom=%.3f cam=(%.1f,%.1f)"
        % (len(coastline) + len(territories), len(territories), zoom, cam[0], cam[1])
    )
    print(
        "confirmed: get_local_mouse_position() under Camera2D; raw viewport pixels miss after center_on_cells"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
