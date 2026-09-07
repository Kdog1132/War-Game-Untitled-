extends SceneTree
## Headless A* + ArmyService hop + get_cell_owner check.
## godot --headless --path . -s res://tools/path_check.gd

const PathfinderScript := preload("res://map/Pathfinder.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ms: Node = root.get_node_or_null("MapService")
	var armies: Node = root.get_node_or_null("ArmyService")
	if ms == null or not bool(ms.call("load_theater", "stub_med")):
		push_error("failed to load stub_med")
		print("PATH_CHECK_FAIL")
		quit(1)
		return
	if str(ms.call("get_cell_owner", "c_0_0")) != "player":
		push_error("get_cell_owner(c_0_0) should be player")
		print("PATH_CHECK_FAIL")
		quit(1)
		return
	if armies == null:
		push_error("ArmyService autoload missing")
		print("PATH_CHECK_FAIL")
		quit(1)
		return
	armies.call("reset_for_theater")
	if str(armies.call("player_cell")) != "c_0_0":
		push_error("player army should spawn on c_0_0")
		print("PATH_CHECK_FAIL")
		quit(1)
		return
	var path: Dictionary = PathfinderScript.find_path("c_0_0", "c_5_0")
	if not bool(path.get("ok", false)) or (path.get("cells", []) as Array).size() < 2:
		push_error("expected A* path Gibraltar → Suez")
		print("PATH_CHECK_FAIL")
		quit(1)
		return
	if not bool(armies.call("order_move", "c_5_0")):
		push_error("ArmyService hop to c_5_0 failed")
		print("PATH_CHECK_FAIL")
		quit(1)
		return
	if str(armies.call("player_cell")) != "c_5_0":
		push_error("army did not hop to c_5_0, at %s" % str(armies.call("player_cell")))
		print("PATH_CHECK_FAIL")
		quit(1)
		return
	var missing: Dictionary = PathfinderScript.find_path("c_0_0", "no_such")
	if bool(missing.get("ok", false)):
		push_error("path to missing cell should fail")
		print("PATH_CHECK_FAIL")
		quit(1)
		return
	print("PATH_CHECK_OK cells=%s cost=%s hopped=c_5_0" % [str(path.get("cells")), str(path.get("cost"))])
	quit(0)
