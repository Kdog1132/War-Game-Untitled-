extends SceneTree
## Headless A* + get_cell_owner check.
## godot --headless --path . -s res://tools/path_check.gd

const PathfinderScript := preload("res://map/Pathfinder.gd")
const ArmyScript := preload("res://units/Army.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ms: Node = root.get_node_or_null("MapService")
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
	var path: Dictionary = PathfinderScript.find_path("c_0_0", "c_5_0")
	if not bool(path.get("ok", false)) or (path.get("cells", []) as Array).size() < 2:
		push_error("expected A* path Gibraltar → Suez")
		print("PATH_CHECK_FAIL")
		quit(1)
		return
	var army = ArmyScript.new()
	army.place("c_0_0")
	if not army.order_path(path):
		push_error("army rejected path")
		print("PATH_CHECK_FAIL")
		quit(1)
		return
	var guard := 0
	while army.moving and guard < 200:
		army.tick(1.0)
		guard += 1
	if army.cell_id != "c_5_0":
		push_error("army did not arrive at c_5_0, at %s" % army.cell_id)
		print("PATH_CHECK_FAIL")
		quit(1)
		return
	var water: Dictionary = PathfinderScript.find_path("c_0_0", "no_such")
	if bool(water.get("ok", false)):
		push_error("path to missing cell should fail")
		print("PATH_CHECK_FAIL")
		quit(1)
		return
	print("PATH_CHECK_OK cells=%s cost=%s ticks=%d" % [str(path.get("cells")), str(path.get("cost")), guard])
	quit(0)
