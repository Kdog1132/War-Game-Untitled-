extends SceneTree
## Headless theater load check. Run:
## godot --headless --path . -s res://tools/boot_check.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ms: Node = root.get_node_or_null("MapService")
	if ms == null:
		push_error("MapService autoload missing")
		print("BOOT_CHECK_FAIL")
		quit(1)
		return
	var ok := true
	ok = _check(ms, "stub_med", 8, "c_0_0", "player") and ok
	ok = _check(ms, "med_v0", 989, "", "") and ok
	if ok:
		print("BOOT_CHECK_OK")
		quit(0)
	else:
		print("BOOT_CHECK_FAIL")
		quit(1)


func _check(ms: Node, dir_name: String, cell_count: int, sample_id: String, sample_owner: String) -> bool:
	if not bool(ms.call("load_theater", dir_name)):
		push_error("failed load %s" % dir_name)
		return false
	var cells: Dictionary = ms.get("cells")
	if cells.size() != cell_count:
		push_error("%s cell count %d != %d" % [dir_name, cells.size(), cell_count])
		return false
	if not sample_id.is_empty() and str(ms.call("get_cell_owner", sample_id)) != sample_owner:
		push_error("%s get_cell_owner(%s) mismatch" % [dir_name, sample_id])
		return false
	var lanes: Array = ms.get("lanes")
	if lanes.is_empty():
		push_error("%s has no lanes" % dir_name)
		return false
	if dir_name == "stub_med":
		var ports: Dictionary = ms.get("ports")
		for pair in [["p_gibraltar", "gibraltar"], ["p_suez", "suez"]]:
			var port: Dictionary = ports.get(str(pair[0]), {})
			if not bool(port.get("chokepoint", false)) or str(port.get("chokepoint_id", "")) != str(pair[1]):
				push_error("stub_med %s missing chokepoint/chokepoint_id" % str(pair[0]))
				return false
	print("loaded %s cells=%d lanes=%d hex=%.1f" % [
		str(ms.get("theater_id")),
		cells.size(),
		lanes.size(),
		float(ms.get("hex_size_px")),
	])
	return true
