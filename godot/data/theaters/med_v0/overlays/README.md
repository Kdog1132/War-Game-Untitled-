# med_v0 overlays

**TODO: swap this stub for Terra’s bake** when these files land in this folder:

| Terra file | Role |
| --- | --- |
| `meta.json` | EPSG:4326 bounds (`west/south/east/north` or `min_lon` / `max_lat` …) |
| `ocean.png` | Sea raster, mapped to those bounds |
| `land_fill.png` | Land raster |
| `coastline.geojson` | Coast rings or lines (EPSG:4326) |
| `admin.geojson` | Admin / territory polygons (EPSG:4326) |

`MapService` prefers that Terra set automatically (`overlay_source = "terra"`).

Until then the playable stub is:

- `coastline.geojson` — Europe / Africa / Anatolia land + Med sea box
- `territories.geojson` — eight named territories (Gibraltar → Suez)
- `med_paint.png` — preview only, not used in-game
