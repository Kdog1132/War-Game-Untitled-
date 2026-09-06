extends Node
## M0 boot: load stub_med, instance WorldMap, show theater HUD.
## KEY_1 = stub_med (hex ~48px). KEY_2 = med_v0 (hex ~14px).

@onready var world_map: Node2D = $WorldMap
@onready var theater_label: Label = $HUD/TheaterLabel
@onready var help_label: Label = $HUD/HelpLabel


func _ready() -> void:
	_load_theater("stub_med")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_load_theater("stub_med")
				get_viewport().set_input_as_handled()
			KEY_2:
				_load_theater("med_v0")
				get_viewport().set_input_as_handled()


func _load_theater(dir_name: String) -> void:
	if not MapService.load_theater(dir_name):
		push_error("Main: failed to load theater '%s'" % dir_name)
		theater_label.text = "Theater: failed to load %s" % dir_name
		return
	MapService.hex_size_px = MapService.suggested_hex_size(dir_name)
	_refresh_hud()
	if world_map.has_method("rebuild"):
		world_map.rebuild()


func _refresh_hud() -> void:
	var name := str(MapService.meta.get("name", MapService.theater_id))
	theater_label.text = "%s  (%s)" % [name, MapService.theater_id]
	help_label.text = "1 stub_med   2 med_v0   WASD / drag pan   wheel zoom   %d cells" % MapService.cells.size()
