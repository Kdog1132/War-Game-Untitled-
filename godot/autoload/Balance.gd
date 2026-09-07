extends Node
## Thin loader for Forge slice_v1 balance numbers.
## Enter times here OVERRIDE theater terrain_costs.json on conflict.

const DEFAULT_PATH := "res://data/balance/slice_v1.json"

var data: Dictionary = {}
var loaded: bool = false


func _ready() -> void:
	load_balance(DEFAULT_PATH)


func load_balance(path: String = DEFAULT_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Balance: cannot open %s" % path)
		loaded = false
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Balance: expected Dictionary in %s" % path)
		loaded = false
		return false
	data = parsed
	loaded = true
	return true


func enter_time_sec(terrain_tag: String) -> Variant:
	var et: Dictionary = data.get("enter_time_sec", {})
	if not et.has(terrain_tag):
		return null
	return et[terrain_tag]


func has_enter_time(terrain_tag: String) -> bool:
	var et: Dictionary = data.get("enter_time_sec", {})
	return et.has(terrain_tag)


func mobility_mult(kind: String = "none") -> float:
	var mm: Dictionary = data.get("mobility_mult", {})
	if mm.has(kind):
		return float(mm[kind])
	var lower := kind.to_lower()
	for key in mm.keys():
		if str(key).to_lower() == lower:
			return float(mm[key])
	return float(mm.get(kind, 1.0))


func tick_sec() -> float:
	return float(data.get("tick_sec", 1.0))


func annex_cfg() -> Dictionary:
	return data.get("annex", {})


func supply_cfg() -> Dictionary:
	return data.get("supply", {})


func supply_per_land() -> float:
	return float(supply_cfg().get("per_land", 1))


func supply_per_factory() -> float:
	return float(supply_cfg().get("per_factory", 8))


func supply_trade(state: String) -> float:
	var st: Dictionary = data.get("supply_trade", {})
	if st.has(state):
		return float(st[state])
	return 0.0


func sea_transit_sec(state: String) -> Variant:
	var sea: Dictionary = data.get("sea_transit_sec", {})
	if not sea.has(state):
		return null
	return sea[state]


func building_def(kind: String) -> Dictionary:
	var buildings: Dictionary = data.get("buildings", {})
	return buildings.get(kind, {})


func building_cost(kind: String) -> int:
	return int(building_def(kind).get("cost", 0))


func building_ticks(kind: String) -> int:
	return int(building_def(kind).get("build_ticks", 1))


func lane_control() -> Dictionary:
	return data.get("lane_control", {})


func win_land_control() -> float:
	var w: Dictionary = data.get("win", {})
	return float(w.get("land_control", 0.7))
