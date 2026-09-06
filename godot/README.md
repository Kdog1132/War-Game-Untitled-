# Atlas M0 / M1 — Stub Mediterranean

Godot 4.2+ hex theater scaffold for Atlas (Godot Core). Loads JSON theaters through a thin `MapService` (no `.tres`), draws terrain + ownership, pans/zooms with a `Camera2D`, and (M1) pathfinds one army with Forge enter times.

This folder is the M0 project. The repo root still holds the earlier v0.1 square-grid prototype — import **this** folder (`godot/project.godot`) for the hex map.

## Open in Godot 4.2+

1. Install [Godot 4.2 or newer](https://godotengine.org/download) (4.2+; Forward Plus).
2. Project Manager → **Import** → select the `godot/` folder (the one that contains `project.godot`).
3. Press **F5**. Main scene is `res://scenes/Main.tscn`.

It should boot on `stub_med` with colored hexes, a theater name label, and a working camera. No missing references if the theater JSON under `data/theaters/` is intact.

## Controls

| Input | Action |
| --- | --- |
| **WASD** or arrow keys | Pan |
| Left-click | Select the army, or (if selected) A* move to that hex |
| Left-drag or middle-drag | Pan |
| Right-click or **Esc** | Deselect army |
| Mouse wheel | Zoom |
| **1** | Load `stub_med` (hex size ~48 px) |
| **2** | Load `med_v0` (hex size ~14 px) |

HUD shows the theater name / id, army status, and cell count. Switching theaters recenters the camera, redraws the map, and respawns the army on a player-owned cell (`get_cell_owner`).

## M1 — Pathfinder + ArmyService

- `map/Pathfinder.gd` — A* over `MapService` adjacency. Step cost is `enter_time_sec * mobility_mult`. `water` / null is skipped.
- `autoload/ArmyService.gd` — one player army on `c_0_0` (stub_med). LMB select, LMB a hex to A* + hop.
- `WorldMap` draws the path and army markers.
- Ports use the Terra schema: `harbor_node_id`, `chokepoint`, `chokepoint_id` (`gibraltar`|`suez`).
- MapService ownership stays on **`get_cell_owner`** — never `get_owner` (clashes with `Node.get_owner`).

## Theaters

| Folder | What it is |
| --- | --- |
| `data/theaters/stub_med/` | Exact 8-cell Gibraltar → Suez stub (c_0_0…c_5_0 + c_1_1 + Levant c_4_1). Two harbors (`chokepoint:true`, `chokepoint_id` gibraltar\|suez), one Open lane `l_1`. |
| `data/theaters/med_v0/` | Larger Mediterranean ribbon sized to the Terra pack: **989 cells / 17 harbors / 34 lanes**. Generated stand-in (50 km hex, EPSG:4326 centroids) so KEY_2 works in-repo. Not the locked coastline mesh. |

Swap path when a locked mesh lands: keep loading `stub_med` by default, then point KEY_2 / `MapService.load_theater("med_v0")` at the replacement files in `data/theaters/med_v0/`. Shipping stays in `shipping_graph.json` only — **do not add `lanes.json`**.

Theater files (all required):

`meta.json`, `cells.json`, `adjacency.json`, `ports.json`, `ownership_seed.json`, `shipping_graph.json`, `annexation.json`, `terrain_costs.json`, `regions.json`

## MapService

Autoload. Flat JSON → Dictionaries.

- `load_theater(dir_name)` reads `res://data/theaters/<dir>/`
- Cells keyed by `cell_id` and `Vector2i(q, r)`
- Ownership: `get_cell_owner(cell_id)` (seed `cell_owners` wins, else `default_owner`)
- `axial_to_world` / `world_to_axial` — flat-top hex
- Lanes normalized from `shipping_graph.edges` (`lane_id`, `a`, `b`, optional `weight`, `state` Open\|Contested\|Blocked)
- Forge `Balance.enter_time_sec` overrides `terrain_costs.json`
- Signal: `theater_loaded`

## Balance

`res://data/balance/slice_v1.json` — locked Forge slice_v1 numbers (tick 1.0, enter times, Road/Rail mobility, sea transit, supply/trade, buildings, 0.7 land win, lane-control rules).

## Out of scope (M0)

No multiplayer. `autoload/SimTick.gd` is an autoload stub with TODOs for the atlas-sim tick order (income → builds → movement → combat → annex → lanes → win).
