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
