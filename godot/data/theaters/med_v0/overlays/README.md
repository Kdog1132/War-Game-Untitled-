# med_v0 overlays — Terra bake + Slice 1 paint

| File | Use |
|------|-----|
| ocean.png / land_fill.png | Terra backdrop, 1024×374, EPSG:4326 bbox `[-10, 28, 42, 47]` |
| coastline.geojson | Terra coast Line2D (71 features) |
| admin_regions_slice1.geojson | **Slice 1 paint** — 8 clickable territories (preferred) |
| territories.geojson | Same 8-region set (loader fallback) |
| admin_regions.geojson | 19-country set — **not in this bake** (pack CRC failed after borders) |
| admin_borders.geojson | Border strokes — **not in this bake** |
| meta.json | bbox EPSG:4326 + texture sizes |

`MapService` prefers `admin_regions_slice1` (8) over the 19-country admin file. No hex chrome. No DEM.

Terra `admin_regions*.geojson` / `admin_borders.geojson` did not survive the 20-part pack inflate (gzip CRC). Paint keeps the in-repo 8-region polygons so click/annex still works on the Terra rasters + coastline.
