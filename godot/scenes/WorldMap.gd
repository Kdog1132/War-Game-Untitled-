extends Node2D
## Painted Med map. LMB picks a territory via get_local_mouse_position() (Camera2D).

const PathfinderScript := preload("res://map/Pathfinder.gd")

signal status_changed(text: String)

const LAND := Color("#c9a66b")
const SEA := Color("#1a5f8a")
const SEA_DEEP := Color("#12486c")
const COAST := Color("#2a2118")
const OWNER_FILL := {
	"player": Color(0.20, 0.48, 0.92, 0.50),
	"enemy": Color(0.88, 0.22, 0.22, 0.50),
	"none": Color(0.55, 0.52, 0.42, 0.22),
}
const LANE_COLOR := Color(0.35, 0.75, 0.95, 0.85)
const ARMY_COL := Color("#2E6BFF")
const SELECT_COL := Color("#F5E6A8")
const PATH_COL := Color(0.98, 0.92, 0.45, 0.55)
const PREVIEW_COL := Color(1.0, 1.0, 1.0, 0.42)
const HOVER_COL := Color(1.0, 1.0, 1.0, 0.55)

@onready var camera: Camera2D = $Camera2D

var _dragging: bool = false
var _hover_cell: String = ""
var _picked_cell: String = ""
var _preview_path: Array = []
var _pulse: float = 0.0


func _ready() -> void:
	if camera:
		camera.make_current()
	_watch(ArmyService)
	_watch(OwnershipService)
	_watch(AnnexService)
	_watch(ShippingService)
	_watch(BuildingService)
	rebuild()


func _watch(node: Node) -> void:
	if node != null and node.has_signal("changed") and not node.changed.is_connected(_on_army_changed):
		node.changed.connect(_on_army_changed)


func rebuild() -> void:
	ArmyService.reset_for_theater()
	_preview_path.clear()
	_hover_cell = ""
	_picked_cell = ""
	queue_redraw()
	center_on_cells()
	_emit_status()


func recenter() -> void:
	center_on_cells()


func center_on_cells() -> void:
	if camera == null or not MapService.loaded:
		return
	var bounds := MapService.map_bounds()
	camera.position = bounds.get_center()
	var vp := get_viewport_rect().size
	var z := minf(vp.x / maxf(bounds.size.x, 1.0), vp.y / maxf(bounds.size.y, 1.0)) * 0.88
	z = clampf(z, 0.12, 2.2)
	camera.zoom = Vector2(z, z)


func _on_army_changed() -> void:
	queue_redraw()
	_emit_status()


func _process(delta: float) -> void:
	if camera == null:
		return
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if pan != Vector2.ZERO:
		var speed := 520.0 / maxf(camera.zoom.x, 0.05)
		camera.position += pan.normalized() * speed * delta
	ArmyService.process_hops(delta)
	_pulse += delta
	if not _picked_cell.is_empty() or ArmyService.is_selected():
		queue_redraw()
	_update_hover()


func _input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			ArmyService.deselect()
			_picked_cell = ""
			_preview_path.clear()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by(1.12)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by(1.0 / 1.12)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			if mb.pressed:
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			ArmyService.deselect()
			_picked_cell = ""
			_preview_path.clear()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Click-select a territory. No brush. Pan is WASD / middle-drag.
			_click_world()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		camera.position -= mm.relative / camera.zoom
		get_viewport().set_input_as_handled()


func _zoom_by(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, 0.08, 4.0)
	camera.zoom = Vector2(z, z)


func world_mouse() -> Vector2:
	## Local mouse on this Node2D. Camera2D is a child; Godot applies the
	## canvas transform so this stays in map space after pan/zoom.
	return get_local_mouse_position()


func picked_cell() -> String:
	if not _picked_cell.is_empty():
		return _picked_cell
	return ArmyService.player_cell()


func _click_world() -> void:
	var cid := _cell_under_mouse()
	if cid.is_empty() and _near_army():
		cid = ArmyService.player_cell()
	if cid.is_empty():
		return
	_picked_cell = cid
	var result := ArmyService.try_click(cid)
	if result == "no_path":
		_emit_status("No path")
	queue_redraw()
	_emit_status()


func _update_hover() -> void:
	if not MapService.loaded:
		return
	var cid := _cell_under_mouse()
	if cid == _hover_cell:
		return
	_hover_cell = cid
	_preview_path.clear()
	if ArmyService.is_selected() and not cid.is_empty() and cid != ArmyService.player_cell():
		var found: Dictionary = PathfinderScript.find_path(ArmyService.player_cell(), cid)
		if bool(found.get("ok", false)):
			_preview_path = found.get("cells", [])
	queue_redraw()


func _cell_under_mouse() -> String:
	return MapService.cell_id_at_world(world_mouse())


func _near_army() -> bool:
	var reach := maxf(MapService.geo_px_per_deg * 0.55, MapService.hex_size_px * 0.55)
	return (world_mouse() - ArmyService.world_pos()).length() <= reach


func _draw() -> void:
	if not MapService.loaded:
		return
	var bounds := MapService.map_bounds().grow(MapService.geo_px_per_deg * 8.0)
	draw_rect(bounds, SEA_DEEP)
	_draw_painted_map()
	_draw_ghost_trail(_preview_path, PREVIEW_COL)
	_draw_ghost_trail(ArmyService.last_path(), PATH_COL)
	_draw_lanes()
	for aid in ArmyService.armies.keys():
		var rec: Dictionary = ArmyService.armies[aid]
		_draw_army(ArmyService.world_pos(str(aid)), bool(rec.get("selected", false)))


func _draw_painted_map() -> void:
	for feat in MapService.overlays_of_kind("sea"):
		_fill_feature(feat, SEA)
	for feat in MapService.overlays_of_kind("land"):
		_fill_feature(feat, LAND)
		_stroke_feature(feat, Color("#d8c4a0"), 1.8)
	for feat in MapService.overlays_of_kind("territory"):
		_draw_territory(feat)
	for feat in MapService.overlays_of_kind("land"):
		_stroke_feature(feat, COAST, 1.5)


func _draw_territory(feat: Dictionary) -> void:
	var cid := str(feat.get("cell_id", ""))
	if cid.is_empty() or not MapService.cells.has(cid):
		cid = MapService.nearest_cell_at_world(_feature_centroid(feat))
	var owner := MapService.get_cell_owner(cid) if not cid.is_empty() else "none"
	var fill: Color = OWNER_FILL.get(owner, OWNER_FILL["none"])
	var claim := AnnexService.claiming_faction(cid)
	var blend := AnnexService.tint_factor(cid)
	if blend > 0.0 and claim != "" and OWNER_FILL.has(claim):
		fill = fill.lerp(OWNER_FILL[claim], blend)
	var selected := cid == _picked_cell or (cid == ArmyService.player_cell() and ArmyService.is_selected())
	var hovered := cid == _hover_cell and not selected
	var pulse := 0.5 + 0.5 * sin(_pulse * 3.2)
	if hovered:
		fill = fill.lightened(0.16)
	if selected:
		fill = fill.lerp(SELECT_COL, 0.14 + 0.12 * pulse)
	_fill_feature(feat, fill)
	if selected:
		var line := SELECT_COL
		line.a = 0.40 + 0.50 * pulse
		_stroke_feature(feat, line, 2.0 + 1.6 * pulse)
	elif hovered:
		_stroke_feature(feat, HOVER_COL, 1.8)
	var center := _feature_centroid(feat)
	if center == Vector2.ZERO:
		center = MapService.cell_world_pos(cid)
	_draw_label(center, str(feat.get("name", cid)))
	if selected:
		_draw_annex_meter(center, cid)
	_draw_buildings(center, cid)


func _fill_feature(feat: Dictionary, col: Color) -> void:
	var rings: Array = feat.get("rings", [])
	if rings.is_empty():
		return
	draw_colored_polygon(rings[0], col)


func _stroke_feature(feat: Dictionary, col: Color, width: float) -> void:
	var rings: Array = feat.get("rings", [])
	if rings.is_empty():
		return
	var ring: PackedVector2Array = rings[0]
	if ring.size() < 2:
		return
	var closed := ring.duplicate()
	if closed[0] != closed[closed.size() - 1]:
		closed.append(closed[0])
	draw_polyline(closed, col, width, true)


func _feature_centroid(feat: Dictionary) -> Vector2:
	var rings: Array = feat.get("rings", [])
	if rings.is_empty():
		return Vector2.ZERO
	var ring: PackedVector2Array = rings[0]
	if ring.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for p in ring:
		acc += p
	return acc / float(ring.size())


func _draw_label(center: Vector2, text: String) -> void:
	if text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var size := 11
	if font:
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		draw_string(font, center + Vector2(-sz.x * 0.5, -8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.08, 0.07, 0.05, 0.9))


func _draw_ghost_trail(cells: Array, col: Color) -> void:
	if cells.size() < 2:
		return
	for i in range(cells.size() - 1):
		var a := MapService.cell_world_pos(str(cells[i]))
		var b := MapService.cell_world_pos(str(cells[i + 1]))
		var faded := col
		faded.a = col.a * 0.55
		draw_line(a, b, faded, 2.2)
		var steps := 5
		for s in range(1, steps + 1):
			var t := float(s) / float(steps)
			var ghost := col
			ghost.a = col.a * (0.25 + 0.55 * t)
			draw_circle(a.lerp(b, t), 2.6, ghost)


func _draw_lanes() -> void:
	for lane in MapService.lanes:
		var a_id := MapService.harbor_cell_id(str(lane.get("a", "")))
		var b_id := MapService.harbor_cell_id(str(lane.get("b", "")))
		if a_id.is_empty() or b_id.is_empty():
			continue
		var a := MapService.cell_world_pos(a_id)
		var b := MapService.cell_world_pos(b_id)
		var col := LANE_COLOR
		match str(lane.get("state", "Open")):
			"Open":
				col = Color(0.25, 0.82, 0.45, 0.9)
			"Contested":
				col = Color(0.95, 0.75, 0.2, 0.9)
			"Blocked":
				col = Color(0.7, 0.15, 0.15, 0.75)
		draw_line(a, b, col, maxf(1.5, MapService.geo_px_per_deg * 0.08))


func _draw_annex_meter(center: Vector2, cell_id: String) -> void:
	var progress := AnnexService.meter(cell_id)
	if progress <= 0.0:
		return
	var w := MapService.geo_px_per_deg * 1.1
	var h := 5.0
	var origin := center + Vector2(-w * 0.5, MapService.geo_px_per_deg * 0.45)
	draw_rect(Rect2(origin, Vector2(w, h)), Color(0.08, 0.08, 0.1, 0.75))
	draw_rect(Rect2(origin, Vector2(w * clampf(progress / 100.0, 0.0, 1.0), h)), Color(0.95, 0.85, 0.25, 0.95))


func _draw_buildings(center: Vector2, cell_id: String) -> void:
	var kinds := BuildingService.kinds_on(cell_id)
	if kinds.is_empty():
		return
	var i := 0
	for kind in kinds:
		var p := center + Vector2(MapService.geo_px_per_deg * 0.45, -6.0 + float(i) * 7.0)
		match str(kind):
			"Factory":
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color("#cfd8dc"))
			"Road":
				draw_line(p + Vector2(-6, 0), p + Vector2(6, 0), Color("#6d4c41"), 2.0)
			"Bunker":
				draw_colored_polygon(PackedVector2Array([
					p + Vector2(0, -5), p + Vector2(5, 4), p + Vector2(-5, 4)
				]), Color("#546e7a"))
			"Harbor":
				draw_circle(p, 3.5, Color("#81d4fa"))
			_:
				draw_circle(p, 2.5, Color("#eeeeee"))
		i += 1


func _draw_army(pos: Vector2, selected: bool) -> void:
	var s := maxf(MapService.geo_px_per_deg * 0.28, 8.0)
	var pts := PackedVector2Array([
		pos + Vector2(0, -s),
		pos + Vector2(s * 0.7, s * 0.55),
		pos + Vector2(0, s * 0.15),
		pos + Vector2(-s * 0.7, s * 0.55),
	])
	draw_colored_polygon(pts, ARMY_COL)
	var ring := SELECT_COL if selected else Color(0.05, 0.08, 0.16, 0.9)
	draw_polyline(pts + PackedVector2Array([pts[0]]), ring, 3.2 if selected else 1.6)
	if selected:
		var pulse := 0.5 + 0.5 * sin(_pulse * 3.2)
		var glow := SELECT_COL
		glow.a = 0.35 + 0.45 * pulse
		draw_arc(pos, s * (1.35 + 0.25 * pulse), 0.0, TAU, 28, glow, 2.2)


func _emit_status(extra: String = "") -> void:
	var bits: PackedStringArray = []
	if extra != "":
		bits.append(extra)
	var cell := ArmyService.player_cell()
	if cell.is_empty():
		bits.append("no army")
	elif ArmyService.is_selected():
		bits.append("army selected on %s — LMB a territory to move" % cell)
	else:
		bits.append("LMB a territory to pick, or the army on %s" % cell)
	if not _picked_cell.is_empty():
		var picked_name := str(MapService.get_cell(_picked_cell).get("name", _picked_cell))
		bits.append("picked %s" % picked_name)
	status_changed.emit("   ".join(bits))
