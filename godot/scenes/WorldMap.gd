extends Node2D
## Visible hex theater: terrain fill + ownership tint, shipping lanes, Camera2D.
## M1: one selectable Army, A* click-to-move, path preview.

const PathfinderScript := preload("res://map/Pathfinder.gd")
const ArmyScript := preload("res://units/Army.gd")

signal status_changed(text: String)

const TERRAIN_COLORS := {
	"plains": Color("#9ccc65"),
	"urban": Color("#90a4ae"),
	"forest": Color("#2e7d32"),
	"hill": Color("#8d6e63"),
	"desert": Color("#ffd54f"),
	"swamp": Color("#00695c"),
	"mountain": Color("#5d4037"),
	"water": Color("#1565c0"),
}

const OWNER_TINT := {
	"player": Color(0.18, 0.42, 1.0, 0.38),
	"enemy": Color(0.89, 0.23, 0.23, 0.38),
	"none": Color(0.45, 0.45, 0.48, 0.22),
}

const LANE_COLOR := Color(0.35, 0.75, 0.95, 0.85)
const OUTLINE := Color(0.08, 0.09, 0.11, 0.55)
const ARMY_COL := Color("#2E6BFF")
const SELECT_COL := Color("#F5E6A8")
const PATH_COL := Color(0.98, 0.92, 0.45, 0.95)
const PREVIEW_COL := Color(1.0, 1.0, 1.0, 0.55)
const CLICK_PX := 8.0

@onready var camera: Camera2D = $Camera2D

var army = ArmyScript.new()
var _dragging: bool = false
var _drag_moved: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _hover_cell: String = ""
var _preview_path: Array = []


func _ready() -> void:
	if camera:
		camera.make_current()
	rebuild()


func rebuild() -> void:
	army.place(_first_player_cell())
	army.selected = false
	_preview_path.clear()
	_hover_cell = ""
	queue_redraw()
	recenter()
	_emit_status()


func recenter() -> void:
	if camera == null or not MapService.loaded:
		return
	var bounds := MapService.map_bounds()
	camera.position = bounds.get_center()
	var vp := get_viewport_rect().size
	var z := minf(vp.x / maxf(bounds.size.x, 1.0), vp.y / maxf(bounds.size.y, 1.0)) * 0.88
	z = clampf(z, 0.12, 2.2)
	camera.zoom = Vector2(z, z)


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
	if army.moving:
		army.tick(delta)
		queue_redraw()
		_emit_status()
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			army.selected = false
			_preview_path.clear()
			queue_redraw()
			_emit_status()
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
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			army.selected = false
			_preview_path.clear()
			queue_redraw()
			_emit_status()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			_drag_moved = true
			_press_pos = mb.position
			if mb.pressed:
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_moved = false
				_press_pos = mb.position
			else:
				var was_drag := _drag_moved
				_dragging = false
				if not was_drag:
					_click_world()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if not _drag_moved and (mm.position - _press_pos).length() < CLICK_PX:
			return
		_drag_moved = true
		camera.position -= mm.relative / camera.zoom
		get_viewport().set_input_as_handled()


func _zoom_by(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, 0.08, 4.0)
	camera.zoom = Vector2(z, z)


func _click_world() -> void:
	var cid := _cell_under_mouse()
	if cid.is_empty():
		return
	if cid == army.cell_id or _near_army():
		army.selected = true
		queue_redraw()
		_emit_status()
		return
	if not army.selected:
		return
	var result := PathfinderScript.find_path(army.cell_id, cid)
	if army.order_path(result):
		queue_redraw()
		_emit_status()
	else:
		_emit_status("No path")


func _update_hover() -> void:
	if not MapService.loaded:
		return
	var cid := _cell_under_mouse()
	if cid == _hover_cell:
		return
	_hover_cell = cid
	_preview_path.clear()
	if army.selected and not cid.is_empty() and cid != army.cell_id:
		var result := PathfinderScript.find_path(army.cell_id, cid)
		if bool(result.get("ok", false)):
			_preview_path = result.get("cells", [])
	queue_redraw()


func _cell_under_mouse() -> String:
	return MapService.cell_id_at_world(get_local_mouse_position())


func _near_army() -> bool:
	var d := get_local_mouse_position() - army.world_pos()
	return d.length() <= MapService.hex_size_px * 0.55


func _draw() -> void:
	if not MapService.loaded:
		return
	var bounds := MapService.map_bounds().grow(MapService.hex_size_px * 24.0)
	draw_rect(bounds, Color("#1565c0"))
	for cell in MapService.cells.values():
		_draw_hex(cell)
	_draw_path(_preview_path, PREVIEW_COL, 2.0)
	_draw_path(army.last_path if army.moving else [], PATH_COL, 3.0)
	_draw_lanes()
	if not army.cell_id.is_empty():
		_draw_army(army.world_pos(), army.selected)


func _draw_hex(cell: Dictionary) -> void:
	var q := int(cell.get("q", 0))
	var r := int(cell.get("r", 0))
	var center := MapService.axial_to_world(q, r)
	var pts := _hex_corners(center, MapService.hex_size_px * 0.96)
	var tag := str(cell.get("terrain_tag", "plains"))
	var fill: Color = TERRAIN_COLORS.get(tag, TERRAIN_COLORS["plains"])
	draw_colored_polygon(pts, fill)
	var owner := MapService.get_cell_owner(str(cell.get("cell_id", "")))
	var tint: Color = OWNER_TINT.get(owner, OWNER_TINT["none"])
	draw_colored_polygon(pts, tint)
	var outline_pts := pts.duplicate()
	outline_pts.append(pts[0])
	var line_col := OUTLINE
	var width := 1.2
	if str(cell.get("cell_id", "")) == army.cell_id and army.selected:
		line_col = SELECT_COL
		width = 2.4
	elif str(cell.get("cell_id", "")) == _hover_cell:
		line_col = Color(1, 1, 1, 0.45)
		width = 1.8
	draw_polyline(outline_pts, line_col, width)
	if bool(cell.get("harbor_site", false)):
		draw_circle(center, MapService.hex_size_px * 0.16, Color("#1565c0"))
		draw_arc(center, MapService.hex_size_px * 0.22, 0.0, TAU, 14, Color("#e3f2fd"), 1.5)


func _draw_path(cells: Array, col: Color, width: float) -> void:
	if cells.size() < 2:
		return
	for i in range(cells.size() - 1):
		var a := MapService.cell_world_pos(str(cells[i]))
		var b := MapService.cell_world_pos(str(cells[i + 1]))
		draw_line(a, b, col, maxf(width, MapService.hex_size_px * 0.08))
		draw_circle(b, MapService.hex_size_px * 0.1, col)


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
			"Contested":
				col = Color(0.95, 0.75, 0.2, 0.9)
			"Blocked":
				col = Color(0.7, 0.15, 0.15, 0.75)
		draw_line(a, b, col, maxf(1.5, MapService.hex_size_px * 0.12))


func _draw_army(pos: Vector2, selected: bool) -> void:
	var s := MapService.hex_size_px * 0.28
	var pts := PackedVector2Array([
		pos + Vector2(0, -s),
		pos + Vector2(s * 0.7, s * 0.55),
		pos + Vector2(0, s * 0.15),
		pos + Vector2(-s * 0.7, s * 0.55),
	])
	draw_colored_polygon(pts, ARMY_COL)
	var ring := SELECT_COL if selected else Color(0.05, 0.08, 0.16, 0.8)
	draw_polyline(pts + PackedVector2Array([pts[0]]), ring, 1.6 if selected else 1.4)


func _hex_corners(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i))
		pts.append(center + Vector2(cos(angle), sin(angle)) * size)
	return pts


func _first_player_cell() -> String:
	for cid in MapService.cells.keys():
		if MapService.get_cell_owner(str(cid)) == "player":
			return str(cid)
	return ""


func _emit_status(extra: String = "") -> void:
	var bits: PackedStringArray = []
	if extra != "":
		bits.append(extra)
	if army.cell_id.is_empty():
		bits.append("no army")
	elif army.moving:
		bits.append("moving %s → %s" % [army.from_cell, army.to_cell])
	elif army.selected:
		bits.append("army selected on %s — click a hex to move" % army.cell_id)
	else:
		bits.append("click army to select")
	status_changed.emit("   ".join(bits))
