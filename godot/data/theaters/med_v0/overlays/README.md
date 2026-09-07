# med_v0 overlays — minimal spike

| File | Use |
|------|-----|
| ocean.png / land_fill.png | Backdrop |
| coastline.geojson | Coast Line2D |
| admin_regions_slice1.geojson | **Slice 1** — 8 clickable territories |
| admin_regions.geojson | 19-country set |
| admin_borders.geojson | Border strokes |
| meta.json | bbox EPSG:4326 `[-10,28,42,47]` + sizes |

No hex chrome. No DEM.

**Loader:** `MapService` prefers Terra (`meta.json` + rasters + `admin_regions_slice1.geojson`). Full `admin_regions.geojson` (19) is paint-only fallback. Until the pack lands, stub `coastline.geojson` + `territories.geojson` stay playable.
