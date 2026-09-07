extends Node
## Thin theater JSON loader. Flat JSON → Dictionaries, no .tres.
## Forge Balance.enter_time_sec wins over theater terrain_costs.json.

signal theater_loaded(theater_id: String)

const THEATERS_ROOT := "res://data/theaters"
const THEATER_FILES := [
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

const HEX_SIZE_STUB := 48.0
const HEX_SIZE_MED := 14.0

var theater_id: String = ""
var meta: Dictionary = {}
var cells: Dictionary = {} ## cell_id -> Dictionary
var cells_by_axial: Dictionary = {} ## Vector2i -> cell_id
var adjacency: Array = [] ## [{a, b, kind}]
var adjacency_of: Dictionary = {} ## cell_id -> Array[String]
var ports: Dictionary = {} ## port_id -> Dictionary
var ownership_seed: Dictionary = {}
var shipping_graph: Dictionary = {}
var annexation: Dictionary = {}
var terrain_costs: Dictionary = {}
var regions: Dictionary = {}
var cell_owners: Dictionary = {} ## cell_id -> none|player|enemy
var lanes: Array = [] ## normalized shipping_graph.edges
var hex_size_px: float = HEX_SIZE_STUB
var loaded: bool = false

## Lon/lat paint. Prefer Terra bake under overlays/ when present:
## land_fill.png, ocean.png, meta.json (EPSG:4326 bounds), coastline + admin GeoJSON.
## TODO: swap stub coastline.geojson / territories.geojson once Terra lands those files.
var overlay_features: Array = [] ## [{kind, name, cell_id, rings:[PackedVector2Array]}]
var overlay_rasters: Array = [] ## [{kind, texture, rect}]
var overlay_source: String = "stub" ## "terra" | "stub"
var geo_origin_lon: float = -10.0
var geo_origin_lat: float = 47.5
var geo_px_per_deg: float = 34.0
var use_geo_world: bool = true


func load_theater(dir_name: String) -> bool:
	var base := "%s/%s" % [THEATERS_ROOT, dir_name]
	var raw: Dictionary = {}
	for fname in THEATER_FILES:
		var parsed: Variant = _read_json("%s/%s" % [base, fname])
		if parsed == null:
			push_error("MapService: missing or invalid %s/%s" % [dir_name, fname])
			loaded = false
			return false
		raw[fname] = parsed

	meta = _as_dict(raw["meta.json"])
	theater_id = str(meta.get("theater_id", dir_name))
	terrain_costs = _as_dict(raw["terrain_costs.json"])
	annexation = _as_dict(raw["annexation.json"])
	regions = _as_dict(raw["regions.json"])
	ownership_seed = _as_dict(raw["ownership_seed.json"])
	shipping_graph = _as_dict(raw["shipping_graph.json"])

	_load_cells(raw["cells.json"])
	_normalize_adjacency(raw["adjacency.json"])
	_normalize_ports(raw["ports.json"])
	_normalize_lanes()
	_resolve_ownership()
	_apply_default_hex_size()
	_load_overlays(dir_name)

	loaded = true
	theater_loaded.emit(theater_id)
	return true


func get_cell(cell_id: String) -> Dictionary:
	return cells.get(cell_id, {})


func get_cell_at(axial: Vector2i) -> Dictionary:
	var cid: String = cells_by_axial.get(axial, "")
	if cid.is_empty():
		return {}
	return get_cell(cid)


## Cell ownership. Never name this get_owner — that shadows Node.get_owner.
## Runtime source of truth is OwnershipService when that autoload is present.
func get_cell_owner(cell_id: String) -> String:
	var os := _ownership()
	if os != null and os.has_method("get_cell_owner"):
		return str(os.call("get_cell_owner", cell_id))
	if cell_owners.has(cell_id):
		return str(cell_owners[cell_id])
	var cell: Dictionary = get_cell(cell_id)
	return str(cell.get("default_owner", "none"))


func set_cell_owner(cell_id: String, owner: String) -> void:
	if not cells.has(cell_id):
		return
	var os := _ownership()
	if os != null and os.has_method("set_cell_owner"):
		os.call("set_cell_owner", cell_id, owner)
		return
	cell_owners[cell_id] = owner


func neighbors(cell_id: String) -> Array:
	return adjacency_of.get(cell_id, [])


func get_port(port_id: String) -> Dictionary:
	return ports.get(port_id, {})


func _ownership() -> Node:
	return get_node_or_null("/root/OwnershipService")


func harbor_cell_id(harbor_node_id: String) -> String:
	var nodes: Array = shipping_graph.get("nodes", [])
	for node in nodes:
		if typeof(node) == TYPE_DICTIONARY and str(node.get("harbor_node_id", "")) == harbor_node_id:
			return str(node.get("cell_id", ""))
	for port in ports.values():
		if str(port.get("harbor_node_id", "")) == harbor_node_id:
			return str(port.get("cell_id", ""))
	return ""


func enter_time_for(terrain_tag: String) -> Variant:
	if Balance != null and Balance.loaded and Balance.has_enter_time(terrain_tag):
		return Balance.enter_time_sec(terrain_tag)
	var et: Dictionary = terrain_costs.get("enter_time_sec", {})
	if et.has(terrain_tag):
		return et[terrain_tag]
	return null


func axial_to_world(q: int, r: int) -> Vector2:
	var s := hex_size_px
	var x := s * (1.5 * float(q))
	var y := s * (sqrt(3.0) * (float(r) + float(q) * 0.5))
	return Vector2(x, y)


func world_to_axial(world: Vector2) -> Vector2i:
	var s := maxf(hex_size_px, 0.0001)
	var q := (2.0 / 3.0 * world.x) / s
	var r := ((-1.0 / 3.0) * world.x + (sqrt(3.0) / 3.0) * world.y) / s
	return _axial_round(q, r)


func cell_world_pos(cell_id: String) -> Vector2:
	var cell: Dictionary = get_cell(cell_id)
	if cell.is_empty():
		return Vector2.ZERO
	if use_geo_world:
		var c: Variant = cell.get("centroid", {})
		if typeof(c) == TYPE_DICTIONARY:
			return lonlat_to_world(float(c.get("lon", 0.0)), float(c.get("lat", 0.0)))
	return axial_to_world(int(cell.get("q", 0)), int(cell.get("r", 0)))


func cell_axial(cell_id: String) -> Vector2i:
	var cell: Dictionary = get_cell(cell_id)
	return Vector2i(int(cell.get("q", 0)), int(cell.get("r", 0)))


func lonlat_to_world(lon: float, lat: float) -> Vector2:
	return Vector2((lon - geo_origin_lon) * geo_px_per_deg, (geo_origin_lat - lat) * geo_px_per_deg)


func world_to_lonlat(world: Vector2) -> Vector2:
	var s := maxf(geo_px_per_deg, 0.0001)
	return Vector2(world.x / s + geo_origin_lon, geo_origin_lat - world.y / s)


## Viewport/screen pixels → Node2D draw space after Camera2D pan/zoom.
## Do not treat event.position or raw viewport coords as map coords.
func screen_to_world(screen: Vector2, cam_pos: Vector2, cam_zoom: Vector2, viewport_size: Vector2) -> Vector2:
	var z := Vector2(maxf(cam_zoom.x, 0.0001), maxf(cam_zoom.y, 0.0001))
	var centered := screen - viewport_size * 0.5
	return cam_pos + Vector2(centered.x / z.x, centered.y / z.y)


func cell_id_at_world(world: Vector2) -> String:
	if use_geo_world:
		var territory := territory_id_at_world(world)
		if not territory.is_empty() and cells.has(territory):
			return territory
		return nearest_cell_at_world(world)
	return str(cells_by_axial.get(world_to_axial(world), ""))


func territory_id_at_world(world: Vector2) -> String:
	for feat in overlay_features:
		if str(feat.get("kind", "")) != "territory":
			continue
		if _point_in_feature(world, feat):
			return str(feat.get("cell_id", ""))
	return ""


func nearest_cell_at_world(world: Vector2, max_dist: float = -1.0) -> String:
	var best := ""
	var best_d := INF
	var limit := max_dist
	if limit < 0.0:
		limit = geo_px_per_deg * 2.4
	for cid in cells.keys():
		var d := world.distance_to(cell_world_pos(str(cid)))
		if d < best_d:
			best_d = d
			best = str(cid)
	if best_d > limit:
		return ""
	return best


func territory_feature_for_cell(cell_id: String) -> Dictionary:
	if cell_id.is_empty():
		return {}
	for feat in overlay_features:
		if str(feat.get("kind", "")) == "territory" and str(feat.get("cell_id", "")) == cell_id:
			return feat
	var pos := cell_world_pos(cell_id)
	for feat in overlay_features:
		if str(feat.get("kind", "")) != "territory":
			continue
		if _point_in_feature(pos, feat):
			return feat
	return {}


func overlays_of_kind(kind: String) -> Array:
	var out: Array = []
	for feat in overlay_features:
		if str(feat.get("kind", "")) == kind:
			out.append(feat)
	return out


func _point_in_feature(world: Vector2, feat: Dictionary) -> bool:
	var rings: Array = feat.get("rings", [])
	if rings.is_empty():
		return false
	if not _point_in_ring(world, rings[0]):
		return false
	for i in range(1, rings.size()):
		if _point_in_ring(world, rings[i]):
			return false
	return true


func _point_in_ring(world: Vector2, ring: PackedVector2Array) -> bool:
	var inside := false
	var j := ring.size() - 1
	for i in range(ring.size()):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[j]
		var intersect := ((a.y > world.y) != (b.y > world.y)) and (
			world.x < (b.x - a.x) * (world.y - a.y) / ((b.y - a.y) if absf(b.y - a.y) > 0.000001 else 0.000001) + a.x
		)
		if intersect:
			inside = not inside
		j = i
	return inside


func hex_distance(a_id: String, b_id: String) -> int:
	return hex_distance_axial(cell_axial(a_id), cell_axial(b_id))


func hex_distance_axial(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((absi(dq) + absi(dr) + absi(dq + dr)) / 2)


func map_bounds() -> Rect2:
	var have := false
	var min_p := Vector2.ZERO
	var max_p := Vector2.ZERO
	if use_geo_world:
		for rast in overlay_rasters:
			var rr: Rect2 = rast.get("rect", Rect2())
			if rr.size == Vector2.ZERO:
				continue
			if not have:
				min_p = rr.position
				max_p = rr.position + rr.size
				have = true
			else:
				min_p = Vector2(minf(min_p.x, rr.position.x), minf(min_p.y, rr.position.y))
				max_p = Vector2(maxf(max_p.x, rr.end.x), maxf(max_p.y, rr.end.y))
		for feat in overlay_features:
			for ring in feat.get("rings", []):
				for p in ring:
					if not have:
						min_p = p
						max_p = p
						have = true
					else:
						min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
						max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	if not have:
		for cell in cells.values():
			var cid := str(cell.get("cell_id", ""))
			var p := cell_world_pos(cid) if not cid.is_empty() else axial_to_world(int(cell.get("q", 0)), int(cell.get("r", 0)))
			if not have:
				min_p = p
				max_p = p
				have = true
			else:
				min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
				max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	if not have:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	var pad_s := geo_px_per_deg * 1.2 if use_geo_world else hex_size_px * 2.0
	var pad := Vector2(pad_s, pad_s)
	return Rect2(min_p - pad, (max_p - min_p) + pad * 2.0)


func suggested_hex_size(dir_name: String = theater_id) -> float:
	if dir_name == "stub_med":
		return HEX_SIZE_STUB
	if dir_name == "med_v0":
		return HEX_SIZE_MED
	return HEX_SIZE_STUB


func _apply_default_hex_size() -> void:
	hex_size_px = suggested_hex_size(theater_id)


func _load_overlays(dir_name: String) -> void:
	overlay_features.clear()
	overlay_rasters.clear()
	overlay_source = "stub"
	var folders: PackedStringArray = [
		"%s/%s/overlays" % [THEATERS_ROOT, dir_name],
		"%s/med_v0/overlays" % THEATERS_ROOT,
	]
	for folder in folders:
		if _load_terra_overlays(folder):
			overlay_source = "terra"
			break
	if overlay_source != "terra":
		_load_stub_overlays(folders)
	use_geo_world = not overlay_features.is_empty() or not overlay_rasters.is_empty()
	if not use_geo_world:
		use_geo_world = _cells_have_centroids()


func _load_terra_overlays(folder: String) -> bool:
	var slice := "%s/admin_regions_slice1.geojson" % folder
	var full := "%s/admin_regions.geojson" % folder
	var legacy := "%s/admin.geojson" % folder
	var has_png := FileAccess.file_exists("%s/land_fill.png" % folder) or FileAccess.file_exists("%s/ocean.png" % folder)
	var has_admin := FileAccess.file_exists(slice) or FileAccess.file_exists(full) or FileAccess.file_exists(legacy)
	# meta.json alone is not a Terra pack (stub folder already has it).
	if not has_png and not has_admin:
		return false
	_apply_overlay_meta("%s/meta.json" % folder)
	_load_overlay_png(folder, "ocean.png", "ocean")
	_load_overlay_png(folder, "land_fill.png", "land")
	if FileAccess.file_exists("%s/coastline.geojson" % folder) and has_png:
		_ingest_geojson("%s/coastline.geojson" % folder, "coastline")
	# Spike: slice1 (8) first; full 19-country admin_regions only if slice1 is missing.
	if FileAccess.file_exists(slice):
		_ingest_geojson(slice, "territory")
	elif FileAccess.file_exists(full):
		_ingest_geojson(full, "territory")
	elif FileAccess.file_exists(legacy):
		_ingest_geojson(legacy, "territory")
	if FileAccess.file_exists("%s/admin_borders.geojson" % folder):
		_ingest_geojson("%s/admin_borders.geojson" % folder, "border")
	return not overlay_features.is_empty() or not overlay_rasters.is_empty()


func _load_stub_overlays(folders: PackedStringArray) -> void:
	## TODO: delete stub path after Terra land_fill/ocean/meta/admin land in overlays/.
	var seen := {}
	for folder in folders:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".geojson") and not seen.has(fname):
				if fname.begins_with("admin"):
					fname = dir.get_next()
					continue
				seen[fname] = true
				_ingest_geojson("%s/%s" % [folder, fname], "")
			fname = dir.get_next()
		dir.list_dir_end()


func _overlay_bbox(d: Dictionary) -> Array:
	## EPSG:4326 [west, south, east, north]. Default Terra Med box.
	if d.has("bbox") and typeof(d["bbox"]) == TYPE_ARRAY and (d["bbox"] as Array).size() >= 4:
		var a: Array = d["bbox"]
		return [float(a[0]), float(a[1]), float(a[2]), float(a[3])]
	var b: Dictionary = d
	if typeof(d.get("bounds", null)) == TYPE_DICTIONARY:
		b = d["bounds"]
	return [
		float(b.get("west", b.get("min_lon", b.get("lon_min", -10.0)))),
		float(b.get("south", b.get("min_lat", b.get("lat_min", 28.0)))),
		float(b.get("east", b.get("max_lon", b.get("lon_max", 42.0)))),
		float(b.get("north", b.get("max_lat", b.get("lat_max", 47.0)))),
	]


func _apply_overlay_meta(path: String) -> void:
	var parsed: Variant = _read_json(path)
	var d: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var box := _overlay_bbox(d)
	geo_origin_lon = float(box[0])
	geo_origin_lat = float(box[3])
	var span := maxf(float(box[2]) - float(box[0]), 0.001)
	var tex: Variant = d.get("texture_size", [1024, 374])
	var tex_w := 1024.0
	if typeof(tex) == TYPE_ARRAY and (tex as Array).size() >= 1:
		tex_w = float(tex[0])
	geo_px_per_deg = tex_w / span


func _load_overlay_png(folder: String, fname: String, kind: String) -> void:
	var path := "%s/%s" % [folder, fname]
	if not FileAccess.file_exists(path):
		return
	var img := Image.new()
	if img.load(path) != OK:
		return
	var tex := ImageTexture.create_from_image(img)
	if tex == null:
		return
	var parsed: Variant = _read_json("%s/meta.json" % folder)
	var d: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var box := _overlay_bbox(d)
	var nw := lonlat_to_world(float(box[0]), float(box[3]))
	var se := lonlat_to_world(float(box[2]), float(box[1]))
	overlay_rasters.append({
		"kind": kind,
		"texture": tex,
		"rect": Rect2(nw, se - nw),
	})


func _cells_have_centroids() -> bool:
	for cell in cells.values():
		var c: Variant = cell.get("centroid", {})
		if typeof(c) == TYPE_DICTIONARY and (c.has("lon") or c.has("lat")):
			return true
	return false


func _ingest_geojson(path: String, default_kind: String = "") -> void:
	var parsed: Variant = _read_json(path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var feats: Array = parsed.get("features", [])
	if typeof(feats) != TYPE_ARRAY:
		return
	var fname := path.get_file().to_lower()
	for raw in feats:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var props: Dictionary = raw.get("properties", {})
		if typeof(props) != TYPE_DICTIONARY:
			props = {}
		var geom: Dictionary = raw.get("geometry", {})
		if typeof(geom) != TYPE_DICTIONARY:
			continue
		var rings := _geojson_rings(geom)
		if rings.is_empty():
			continue
		var kind := str(props.get("kind", ""))
		if kind.is_empty():
			kind = default_kind
		if kind.is_empty():
			if fname.contains("admin"):
				kind = "territory"
			elif fname.contains("coast"):
				kind = "coastline"
			else:
				kind = "territory"
		var name := str(props.get("name", props.get("NAME", props.get("NAME_EN", props.get("admin", "")))))
		var cell_id := str(props.get("cell_id", ""))
		if cell_id.is_empty():
			cell_id = _cell_id_for_admin_name(name)
		overlay_features.append({
			"kind": kind,
			"name": name,
			"cell_id": cell_id,
			"rings": rings,
		})


func _cell_id_for_admin_name(name: String) -> String:
	var key := name.strip_edges().to_lower()
	if key.is_empty():
		return ""
	var aliases := {
		"gibraltar": "c_0_0",
		"spain": "c_1_0",
		"andalusia": "c_1_0",
		"andalucia": "c_1_0",
		"italy": "c_2_0",
		"italia": "c_2_0",
		"greece": "c_3_0",
		"hellas": "c_3_0",
		"turkey": "c_4_0",
		"anatolia": "c_4_0",
		"türkiye": "c_4_0",
		"turkiye": "c_4_0",
		"egypt": "c_5_0",
		"suez": "c_5_0",
		"algeria": "c_1_1",
		"morocco": "c_1_1",
		"tunisia": "c_1_1",
		"maghreb": "c_1_1",
		"libya": "c_1_1",
		"syria": "c_4_1",
		"lebanon": "c_4_1",
		"israel": "c_4_1",
		"levant": "c_4_1",
		"palestine": "c_4_1",
		"jordan": "c_4_1",
	}
	if aliases.has(key):
		return str(aliases[key])
	for cid in cells.keys():
		var cell: Dictionary = cells[cid]
		if str(cell.get("name", "")).to_lower() == key:
			return str(cid)
	return ""


func _geojson_rings(geom: Dictionary) -> Array:
	var out: Array = []
	var gtype := str(geom.get("type", ""))
	var coords: Variant = geom.get("coordinates", [])
	if gtype == "LineString" and typeof(coords) == TYPE_ARRAY:
		var line := _lonlat_ring(coords)
		if line.size() >= 2:
			out.append(line)
	elif gtype == "MultiLineString" and typeof(coords) == TYPE_ARRAY:
		for line_coords in coords:
			var line := _lonlat_ring(line_coords)
			if line.size() >= 2:
				out.append(line)
	elif gtype == "Polygon" and typeof(coords) == TYPE_ARRAY:
		for ring in coords:
			var pts := _lonlat_ring(ring)
			if pts.size() >= 3:
				out.append(pts)
	elif gtype == "MultiPolygon" and typeof(coords) == TYPE_ARRAY:
		for poly in coords:
			if typeof(poly) != TYPE_ARRAY:
				continue
			for ring in poly:
				var pts := _lonlat_ring(ring)
				if pts.size() >= 3:
					out.append(pts)
	return out


func _lonlat_ring(ring: Variant) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if typeof(ring) != TYPE_ARRAY:
		return pts
	for pair in ring:
		if typeof(pair) != TYPE_ARRAY or pair.size() < 2:
			continue
		pts.append(lonlat_to_world(float(pair[0]), float(pair[1])))
	# GeoJSON rings repeat the first vertex; Godot triangulation rejects that.
	if pts.size() >= 2 and pts[0].distance_to(pts[pts.size() - 1]) < 0.001:
		pts.remove_at(pts.size() - 1)
	return pts


func _load_cells(parsed: Variant) -> void:
	cells.clear()
	cells_by_axial.clear()
	var items: Array = []
	if typeof(parsed) == TYPE_ARRAY:
		items = parsed
	elif typeof(parsed) == TYPE_DICTIONARY:
		var d: Dictionary = parsed
		if d.has("cells") and typeof(d["cells"]) == TYPE_ARRAY:
			items = d["cells"]
		else:
			for key in d.keys():
				var item: Variant = d[key]
				if typeof(item) == TYPE_DICTIONARY:
					var copy: Dictionary = item.duplicate(true)
					if not copy.has("cell_id"):
						copy["cell_id"] = str(key)
					items.append(copy)
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var cell: Dictionary = (item as Dictionary).duplicate(true)
		var cid := str(cell.get("cell_id", ""))
		if cid.is_empty():
			continue
		var q := int(cell.get("q", 0))
		var r := int(cell.get("r", 0))
		cell["q"] = q
		cell["r"] = r
		cell["terrain_tag"] = str(cell.get("terrain_tag", "plains"))
		cell["is_coast"] = bool(cell.get("is_coast", false))
		cell["harbor_site"] = bool(cell.get("harbor_site", false))
		cell["default_owner"] = _norm_owner(cell.get("default_owner", "none"))
		cell["centroid"] = _norm_centroid(cell.get("centroid", {}))
		cells[cid] = cell
		cells_by_axial[Vector2i(q, r)] = cid


func _normalize_adjacency(parsed: Variant) -> void:
	adjacency.clear()
	adjacency_of.clear()
	var edges: Array = []
	if typeof(parsed) == TYPE_ARRAY:
		edges = parsed
	elif typeof(parsed) == TYPE_DICTIONARY:
		var d: Dictionary = parsed
		if d.has("edges") and typeof(d["edges"]) == TYPE_ARRAY:
			edges = d["edges"]
		else:
			for key in d.keys():
				var val: Variant = d[key]
				if typeof(val) == TYPE_ARRAY:
					for other in val:
						edges.append({"a": str(key), "b": str(other), "kind": "land"})
	for edge in edges:
		var a := ""
		var b := ""
		var kind := "land"
		if typeof(edge) == TYPE_DICTIONARY:
			a = str(edge.get("a", edge.get("from", "")))
			b = str(edge.get("b", edge.get("to", "")))
			kind = str(edge.get("kind", "land"))
		elif typeof(edge) == TYPE_ARRAY and edge.size() >= 2:
			a = str(edge[0])
			b = str(edge[1])
			if edge.size() >= 3:
				kind = str(edge[2])
		if a.is_empty() or b.is_empty() or a == b:
			continue
		adjacency.append({"a": a, "b": b, "kind": kind})
		_add_neighbor(a, b)
		_add_neighbor(b, a)


func _add_neighbor(a: String, b: String) -> void:
	if not adjacency_of.has(a):
		adjacency_of[a] = []
	var list: Array = adjacency_of[a]
	if not list.has(b):
		list.append(b)


func _normalize_ports(parsed: Variant) -> void:
	ports.clear()
	var items: Array = []
	if typeof(parsed) == TYPE_ARRAY:
		items = parsed
	elif typeof(parsed) == TYPE_DICTIONARY:
		var d: Dictionary = parsed
		if d.has("ports") and typeof(d["ports"]) == TYPE_ARRAY:
			items = d["ports"]
		else:
			for key in d.keys():
				var item: Variant = d[key]
				if typeof(item) == TYPE_DICTIONARY:
					var copy: Dictionary = item.duplicate(true)
					if not copy.has("port_id"):
						copy["port_id"] = str(key)
					items.append(copy)
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var port: Dictionary = (item as Dictionary).duplicate(true)
		var pid := str(port.get("port_id", ""))
		if pid.is_empty():
			continue
		# Keep Terra fields as-is (chokepoint, chokepoint_id, etc.). No M0 logic.
		ports[pid] = port


func _normalize_lanes() -> void:
	lanes.clear()
	var edges: Variant = shipping_graph.get("edges", [])
	if typeof(edges) != TYPE_ARRAY:
		return
	for edge in edges:
		if typeof(edge) != TYPE_DICTIONARY:
			continue
		var lane: Dictionary = (edge as Dictionary).duplicate(true)
		lane["lane_id"] = str(lane.get("lane_id", ""))
		lane["a"] = str(lane.get("a", ""))
		lane["b"] = str(lane.get("b", ""))
		if lane.has("weight"):
			lane["weight"] = float(lane["weight"])
		lane["state"] = _norm_lane_state(lane.get("state", "Open"))
		if lane["lane_id"].is_empty() or lane["a"].is_empty() or lane["b"].is_empty():
			continue
		lanes.append(lane)


func _resolve_ownership() -> void:
	cell_owners.clear()
	var seed_owners: Dictionary = ownership_seed.get("cell_owners", {})
	for cid in cells.keys():
		var cell: Dictionary = cells[cid]
		var owner := _norm_owner(cell.get("default_owner", "none"))
		if seed_owners.has(cid):
			owner = _norm_owner(seed_owners[cid])
		cell_owners[cid] = owner
	var os := _ownership()
	if os != null and os.has_method("reset_from_theater"):
		os.call("reset_from_theater")


func _norm_owner(value: Variant) -> String:
	var s := str(value).to_lower()
	if s == "player" or s == "enemy":
		return s
	return "none"


func _norm_lane_state(value: Variant) -> String:
	var s := str(value)
	match s.to_lower():
		"contested":
			return "Contested"
		"blocked":
			return "Blocked"
		_:
			return "Open"


func _norm_centroid(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		return {
			"lon": float(d.get("lon", d.get("x", 0.0))),
			"lat": float(d.get("lat", d.get("y", 0.0))),
		}
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		return {"lon": float(value[0]), "lat": float(value[1])}
	return {"lon": 0.0, "lat": 0.0}


func _as_dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _axial_round(qf: float, rf: float) -> Vector2i:
	var x := qf
	var z := rf
	var y := -x - z
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))
