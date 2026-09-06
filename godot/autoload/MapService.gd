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


func get_cell_owner(cell_id: String) -> String:
	if cell_owners.has(cell_id):
		return str(cell_owners[cell_id])
	var cell: Dictionary = get_cell(cell_id)
	return str(cell.get("default_owner", "none"))


func set_cell_owner(cell_id: String, owner: String) -> void:
	if cells.has(cell_id):
		cell_owners[cell_id] = owner


func neighbors(cell_id: String) -> Array:
	return adjacency_of.get(cell_id, [])


func get_port(port_id: String) -> Dictionary:
	return ports.get(port_id, {})


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
	return axial_to_world(int(cell.get("q", 0)), int(cell.get("r", 0)))


func map_bounds() -> Rect2:
	var have := false
	var min_p := Vector2.ZERO
	var max_p := Vector2.ZERO
	for cell in cells.values():
		var p := axial_to_world(int(cell.get("q", 0)), int(cell.get("r", 0)))
		if not have:
			min_p = p
			max_p = p
			have = true
		else:
			min_p = min_p.min(p)
			max_p = max_p.max(p)
	if not have:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	var pad := Vector2(hex_size_px * 2.0, hex_size_px * 2.0)
	return Rect2(min_p - pad, (max_p - min_p) + pad * 2.0)


func suggested_hex_size(dir_name: String = theater_id) -> float:
	if dir_name == "stub_med":
		return HEX_SIZE_STUB
	if dir_name == "med_v0":
		return HEX_SIZE_MED
	return HEX_SIZE_STUB


func _apply_default_hex_size() -> void:
	hex_size_px = suggested_hex_size(theater_id)


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
