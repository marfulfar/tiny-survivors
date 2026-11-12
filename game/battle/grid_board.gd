class_name GridBoard
extends Node3D
## Square tactics grid on the ground (XZ plane). Cell (x, y) is centred on world
## (x, 0, y) * cell_size. Handles walkability (physics probe per cell), reachability
## (8-directional, diagonals cost 1, no cutting corners past obstacles) and the overlays:
## highlighted tiles, grid lines, hover tile and the path arrow.

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

@export var cell_size := 1.0
## Playable cells run from -half_extent to +half_extent on both axes.
@export var half_extent := 19
@export var move_tile_color := Color(0.35, 0.7, 1.0, 0.3)
@export var range_tile_color := Color(1.0, 0.45, 0.25, 0.13)
@export var line_color := Color(1.0, 1.0, 1.0, 0.45)
@export var path_color := Color(1.0, 0.82, 0.2, 1.0)
@export var hover_color := Color(1.0, 1.0, 1.0, 0.45)
@export var invalid_color := Color(1.0, 0.25, 0.2, 0.5)

var _blocked := {}
var _tiles: MultiMeshInstance3D
var _lines: MeshInstance3D
var _arrow: MeshInstance3D
var _hover: MeshInstance3D
var _hover_mat: StandardMaterial3D
var _steps_label: Label3D


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var tile := PlaneMesh.new()
	tile.size = Vector2.ONE * cell_size * 0.92
	tile.material = _overlay_material(0)
	mm.mesh = tile
	_tiles = MultiMeshInstance3D.new()
	_tiles.multimesh = mm
	_tiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tiles)

	_lines = _immediate(1)
	_arrow = _immediate(3)

	_hover = MeshInstance3D.new()
	var hover_mesh := PlaneMesh.new()
	hover_mesh.size = Vector2.ONE * cell_size * 0.96
	_hover_mat = _overlay_material(2)
	_hover_mat.vertex_color_use_as_albedo = false
	hover_mesh.material = _hover_mat
	_hover.mesh = hover_mesh
	_hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover.visible = false
	add_child(_hover)

	_steps_label = Label3D.new()
	_steps_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_steps_label.no_depth_test = true
	_steps_label.render_priority = 5
	_steps_label.outline_render_priority = 4
	_steps_label.font_size = 64
	_steps_label.outline_size = 16
	_steps_label.pixel_size = 0.008
	_steps_label.modulate = path_color
	_steps_label.outline_modulate = Color(0.15, 0.1, 0.0)
	_steps_label.visible = false
	add_child(_steps_label)


# ---------------------------------------------------------------- coordinates

func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / cell_size), roundi(p.z / cell_size))


func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x * cell_size, 0.0, c.y * cell_size)


func in_bounds(c: Vector2i) -> bool:
	return absi(c.x) <= half_extent and absi(c.y) <= half_extent


## Squares between two cells, counting diagonal steps as 1 (Chebyshev distance).
static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# ---------------------------------------------------------------- walkability & paths

## Re-probes every cell for physics bodies (rocks, crystals, enemies...). `exclude` = RIDs to
## ignore, e.g. the unit that is about to move.
func refresh_blocked(exclude: Array[RID]) -> void:
	_blocked.clear()
	var space := get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = Vector3(cell_size * 0.7, 0.8, cell_size * 0.7)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.exclude = exclude
	q.collide_with_areas = false
	for x in range(-half_extent, half_extent + 1):
		for y in range(-half_extent, half_extent + 1):
			var c := Vector2i(x, y)
			q.transform = Transform3D(Basis(), cell_to_world(c) + Vector3(0.0, 0.5, 0.0))
			if not space.intersect_shape(q, 1).is_empty():
				_blocked[c] = true


func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not _blocked.has(c)


## Breadth-first search. Returns {cell: previous cell} for every cell reachable within
## max_steps (the start maps to itself). Orthogonal steps are tried first for straighter paths.
func reachable_from(start: Vector2i, max_steps: int) -> Dictionary:
	var came := {start: start}
	var dist := {start: 0}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		if dist[c] >= max_steps:
			continue
		for d in DIRS:
			var n := c + d
			if came.has(n) or not is_walkable(n):
				continue
			if d.x != 0 and d.y != 0:
				if not is_walkable(c + Vector2i(d.x, 0)) or not is_walkable(c + Vector2i(0, d.y)):
					continue # no squeezing diagonally past an obstacle
			came[n] = c
			dist[n] = dist[c] + 1
			frontier.append(n)
	return came


## Cells from the search start to `target` (inclusive), or [] if unreachable.
func path_to(came: Dictionary, target: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not came.has(target):
		return path
	var c := target
	while true:
		path.push_front(c)
		var prev: Vector2i = came[c]
		if prev == c:
			break
		c = prev
	return path


func cells_within(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			var c := Vector2i(x, y)
			if in_bounds(c):
				out.append(c)
	return out


# ---------------------------------------------------------------- overlays

func show_tiles(cells: Array, color: Color) -> void:
	_tiles.multimesh.instance_count = 0
	add_tiles(cells, color)


## Like show_tiles but keeps the tiles already shown (e.g. a blast area over a range).
func add_tiles(cells: Array, color: Color, height := 0.02) -> void:
	var mm := _tiles.multimesh
	var old: Array = []
	for i in mm.instance_count:
		old.append([mm.get_instance_transform(i), mm.get_instance_color(i)])
	mm.instance_count = old.size() + cells.size()
	for i in old.size():
		mm.set_instance_transform(i, old[i][0])
		mm.set_instance_color(i, old[i][1])
	for i in cells.size():
		mm.set_instance_transform(old.size() + i, Transform3D(Basis(), cell_to_world(cells[i]) + Vector3(0.0, height, 0.0)))
		mm.set_instance_color(old.size() + i, color)


## Grid lines over a square of cells around `center`.
func show_grid_lines(center: Vector2i, radius: int) -> void:
	var im := _lines.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var lo_x := (center.x - radius - 0.5) * cell_size
	var hi_x := (center.x + radius + 0.5) * cell_size
	var lo_z := (center.y - radius - 0.5) * cell_size
	var hi_z := (center.y + radius + 0.5) * cell_size
	var h := 0.025
	for i in range(-radius, radius + 2):
		var x := (center.x + i - 0.5) * cell_size
		var z := (center.y + i - 0.5) * cell_size
		im.surface_set_color(line_color)
		im.surface_add_vertex(Vector3(x, h, lo_z))
		im.surface_add_vertex(Vector3(x, h, hi_z))
		im.surface_add_vertex(Vector3(lo_x, h, z))
		im.surface_add_vertex(Vector3(hi_x, h, z))
	im.surface_end()


func set_hover(c: Vector2i, valid: bool) -> void:
	_hover.visible = in_bounds(c)
	_hover.position = cell_to_world(c) + Vector3(0.0, 0.03, 0.0)
	_hover_mat.albedo_color = hover_color if valid else invalid_color


## Draws an arrow along the path (cells from start to destination) with the step count.
func show_path(cells: Array[Vector2i]) -> void:
	var im := _arrow.mesh as ImmediateMesh
	im.clear_surfaces()
	if cells.size() < 2:
		_steps_label.visible = false
		return
	var pts: Array[Vector3] = []
	for c in cells:
		pts.append(cell_to_world(c) + Vector3(0.0, 0.05, 0.0))
	var tip := pts[-1]
	var end_dir := (pts[-1] - pts[-2]).normalized()
	pts[-1] = tip - end_dir * 0.36 * cell_size
	var w := 0.08 * cell_size

	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(path_color)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		if d.length() < 0.001:
			continue
		var side := d.normalized().cross(Vector3.UP) * w
		_tri(im, a + side, b + side, b - side)
		_tri(im, a + side, b - side, a - side)
	for i in range(1, pts.size() - 1):
		_disc(im, pts[i], w)
	_disc(im, pts[0], w * 1.9)
	var head_side := end_dir.cross(Vector3.UP) * 0.24 * cell_size
	_tri(im, pts[-1] + head_side, tip, pts[-1] - head_side)
	im.surface_end()

	_steps_label.text = str(cells.size() - 1)
	_steps_label.position = tip + Vector3(0.0, 0.55, 0.0)
	_steps_label.visible = true


func clear_overlays() -> void:
	_tiles.multimesh.instance_count = 0
	(_lines.mesh as ImmediateMesh).clear_surfaces()
	(_arrow.mesh as ImmediateMesh).clear_surfaces()
	_hover.visible = false
	_steps_label.visible = false


# ---------------------------------------------------------------- helpers

func _immediate(priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.material_override = _overlay_material(priority)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _overlay_material(priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = priority
	return m


func _tri(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3) -> void:
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_add_vertex(c)


func _disc(im: ImmediateMesh, center: Vector3, r: float) -> void:
	var n := 10
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		_tri(im, center, center + Vector3(cos(a0), 0.0, sin(a0)) * r, center + Vector3(cos(a1), 0.0, sin(a1)) * r)
