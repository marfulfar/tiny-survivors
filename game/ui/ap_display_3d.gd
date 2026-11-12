class_name APDisplay3D
extends Node3D
## Action-point pips floating above a unit, always facing the camera.
## Filled pips = AP available. set_preview(cost) makes the pips an action would spend blink
## (and shows missing ones in red when the unit can't afford it).

## Overall on-screen size multiplier.
@export var size_scale := 1.6
@export var pip_size := 0.17
@export var spacing := 0.22
@export var filled_color := Color(0.35, 0.85, 1.0)
@export var empty_color := Color(0.1, 0.12, 0.18, 0.9)
@export var missing_color := Color(1.0, 0.3, 0.25)

var _points := 0
var _max := 0
var _preview := 0
var _time := 0.0
var _pips: Array[MeshInstance3D] = []
var _label: Label3D
var _bg: MeshInstance3D

static var _circle: GradientTexture2D


func _ready() -> void:
	_label = Label3D.new()
	_label.text = "AP"
	_label.font_size = 44
	_label.outline_size = 12
	_label.pixel_size = 0.004
	_label.modulate = filled_color
	_label.outline_modulate = Color(0, 0.05, 0.1)
	_label.no_depth_test = true
	_label.render_priority = 4
	_label.outline_render_priority = 3
	add_child(_label)
	_bg = _quad(Vector2.ONE, Color(0.0, 0.0, 0.0, 0.45), 1, false)
	_rebuild()


func set_points(points: int, max_points: int) -> void:
	_points = points
	if max_points != _max:
		_max = max_points
		_rebuild()
	_refresh()


func set_preview(cost: int) -> void:
	_preview = cost
	_refresh()


func _process(delta: float) -> void:
	_time += delta
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_basis = cam.global_basis.orthonormalized().scaled(Vector3.ONE * size_scale)
	if _preview > 0:
		_refresh()


func _rebuild() -> void:
	if _label == null:
		return
	for p in _pips:
		p.queue_free()
	_pips.clear()
	var width := (_max - 1) * spacing
	var label_w := 0.3
	var total := width + pip_size + label_w + 0.12
	var left := -total * 0.5
	_label.position = Vector3(left + 0.06 + label_w * 0.5, 0.0, 0.0)
	for i in _max:
		var pip := _quad(Vector2.ONE * pip_size, filled_color, 2, true)
		pip.position = Vector3(left + 0.06 + label_w + pip_size * 0.5 + i * spacing, 0.0, 0.0)
		_pips.append(pip)
	_bg.scale = Vector3(total + 0.06, 0.28, 1.0)
	_refresh()


func _refresh() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 10.0)
	for i in _pips.size():
		var mat := _pips[i].material_override as StandardMaterial3D
		var c := filled_color if i < _points else empty_color
		var spending := _preview > 0 and i < _points and i >= _points - _preview
		var missing := _preview > _points and i >= _points and i < _preview
		if spending:
			c = filled_color.lerp(Color.WHITE, pulse * 0.8)
			c.a = 0.45 + 0.55 * pulse
		elif missing:
			c = missing_color
			c.a = 0.5 + 0.5 * pulse
		mat.albedo_color = c


func _quad(size: Vector2, color: Color, priority: int, round_pip: bool) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = priority
	m.albedo_color = color
	if round_pip:
		m.albedo_texture = _circle_texture()
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func _circle_texture() -> GradientTexture2D:
	if _circle == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.8, 0.95, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
		_circle = GradientTexture2D.new()
		_circle.width = 64
		_circle.height = 64
		_circle.gradient = g
		_circle.fill = GradientTexture2D.FILL_RADIAL
		_circle.fill_from = Vector2(0.5, 0.5)
		_circle.fill_to = Vector2(1.0, 0.5)
	return _circle
