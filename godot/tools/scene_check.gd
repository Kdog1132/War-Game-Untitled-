extends SceneTree
## Instance Main/WorldMap so _draw and overlay pick run once.
## godot --headless --path . -s res://tools/scene_check.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ms: Node = root.get_node_or_null("MapService")
	var packed := load("res://scenes/Main.tscn")
	if packed == null or ms == null:
		push_error("Main.tscn or MapService missing")
		print("SCENE_CHECK_FAIL")
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	var world: Node = main.get_node_or_null("WorldMap")
	if world == null:
		push_error("WorldMap missing")
		print("SCENE_CHECK_FAIL")
		quit(1)
		return
	if not bool(ms.get("use_geo_world")) or int(ms.get("overlay_features").size()) < 4:
		push_error("overlays not loaded on Main boot")
		print("SCENE_CHECK_FAIL")
		quit(1)
		return
	var gib: Vector2 = ms.call("cell_world_pos", "c_0_0")
	if str(ms.call("cell_id_at_world", gib)) != "c_0_0":
		push_error("boot pick missed Gibraltar")
		print("SCENE_CHECK_FAIL")
		quit(1)
		return
	world.queue_redraw()
	print("SCENE_CHECK_OK overlays=%d geo=%s" % [
		int(ms.get("overlay_features").size()),
		str(ms.get("use_geo_world")),
	])
	quit(0)
