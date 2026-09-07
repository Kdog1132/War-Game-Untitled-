# Atlas M0–M6 — Stub Mediterranean

Godot 4.2+ hex theater for Atlas (Godot Core). Loads JSON theaters through a thin `MapService` (no `.tres`), draws terrain + ownership, pans/zooms with a `Camera2D`, pathfinds one army, and runs M2–M6 ownership / annex / economy / shipping.

This folder is the Godot project. Import **this** folder (`godot/project.godot`) — not the repo root.

## Open and run (Godot 4.2+)

1. Install [Godot 4.2 or newer](https://godotengine.org/download) (4.2+; Forward Plus). Developed against 4.2.2.
2. Project Manager → **Import** → select the `godot/` folder (the one that contains `project.godot`).
3. Press **F5**. Main scene is `res://scenes/Main.tscn`.

It boots on `stub_med` with colored hexes, ownership tints, a shipping lane, HUD (supply / selection / annex / lanes), and a working camera.

Headless checks (from this `godot/` folder):

```bash
python3 tools/validate_m0.py
python3 tools/validate_m2.py
godot --headless --path . -s res://tools/boot_check.gd
godot --headless --path . -s res://tools/path_check.gd
godot --headless --path . -s res://tools/prove_annex.gd      # prints ANNEX_FLIP
godot --headless --path . -s res://tools/prove_economy.gd    # prints SUPPLY_EARN / SUPPLY_SPEND
godot --headless --path . -s res://tools/prove_shipping.gd   # prints FERRY_START / FERRY_ARRIVE
```

## Controls

| Input | Action |
| --- | --- |
| **WASD** or arrow keys | Pan |
| Left-click | Select the army, or (if selected) A* move to that hex. Harbor → harbor starts a ferry. |
| Left-drag or middle-drag | Pan |
| Right-click or **Esc** | Deselect army |
| Mouse wheel | Zoom |
| **1** | Load `stub_med` (hex size ~48 px) |
| **2** | Load `med_v0` (hex size ~14 px) |
| **H** | Start Harbor (200 supply / 20 ticks) on the hover or army cell |
| **F** | Start Factory (150 / 15) |
| **R** | Start Road (40 / 5, mobility 0.6) |
| **B** | Place Bunker stub (50 / 5) |

HUD shows theater + **P/N/E** counts, **Supply** (+land / factory / trade), selection, **annex meter**, and **lane states** (Open green / Contested gold / Blocked red).

## Systems

| Slice | Autoload | What it does |
| --- | --- | --- |
| M0 | `MapService`, `Balance` | JSON theaters, hex camera, Forge `slice_v1` |
| M1 | `ArmyService`, `Pathfinder` | A* + click-to-hop army on `c_0_0` |
| M2 | `OwnershipService` | Runtime owners from `ownership_seed`; `get_cell_owner` / `set_cell_owner`; P/N/E counts; WorldMap tint |
| M3 | `AnnexService` | Forge annex %/s; flip at 100; tint lerps with the meter |
| M4 | `EconomyService`, `BuildingService` | Supply 1/land + 8/factory + trade; Harbor 200/20; Factory 150/15 |
| M5 | `ShippingService` | Forge lane control → Open / Contested / Blocked; Harbor→Harbor ferry |
| M6 | HUD + Road/Bunker | Road 40/5 mobility 0.6 in pathfinder; Bunker placeable stub; HUD polish |

`SimTick` runs income → builds → movement → combat (stub) → annex → lanes → win.

Ownership stays on **`get_cell_owner`** — never `get_owner` (clashes with `Node.get_owner`).

## Annex rates (Forge)

- Unclaimed: `+(12 + min(8, 0.02 * strength)) %/s`
- Enemy empty: `+(5 + min(5, 0.015 * strength)) %/s`
- Enemy present: pause
- Vacate: `-25 %/s`
- Flip at 100; WorldMap tint lerps toward the claiming faction

## Economy + buildings

- Income each 1s tick: **1** per owned land cell, **8** per completed Factory, plus lane **trade** (`Open +3`, `Contested +1`, `Blocked 0`) if you own a harbor on the lane
- Harbor 200/20 · Factory 150/15 · Road 40/5 · Bunker 50/5 stub

## Shipping

Forge lane control on stub_med: Gibraltar is player, Suez is enemy → lane `l_1` is **Contested** (gold). Ferry from a harbor hex to the other harbor; transit is 8s Open / 12s Contested / blocked if Blocked.

## Theaters

| Folder | What it is |
| --- | --- |
| `data/theaters/stub_med/` | Exact 8-cell Gibraltar → Suez stub (c_0_0…c_5_0 + c_1_1 + Levant c_4_1). Two harbors (`chokepoint:true`, `chokepoint_id` gibraltar\|suez), one lane `l_1`. |
| `data/theaters/med_v0/` | Larger Mediterranean ribbon sized to the Terra pack: **989 cells / 17 harbors / 34 lanes**. Generated stand-in so KEY_2 works in-repo. |

Theater files (all required):

`meta.json`, `cells.json`, `adjacency.json`, `ports.json`, `ownership_seed.json`, `shipping_graph.json`, `annexation.json`, `terrain_costs.json`, `regions.json`

Shipping stays in `shipping_graph.json` only — **do not add `lanes.json`**.

## Balance

`res://data/balance/slice_v1.json` — Forge slice_v1 numbers (tick 1.0, enter times, Road 0.6 mobility, sea transit, supply 1/land + 8/factory + trade, annex rates, Harbor/Factory/Road/Bunker, 0.7 land win, lane-control rules).

## Out of scope

No multiplayer. Combat is still a stub in `SimTick`. `med_v0` is a generated stand-in, not the locked coastline mesh.
