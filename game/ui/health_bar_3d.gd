class_name HealthBar3D
extends Node3D
## Small world-space health bar that always faces the camera.
## Call set_ratio(0..1). A pale "recent damage" strip drains after the red fill.

@export var width := 0.7
@export var height := 0.09
@export var fill_color := Color(0.9, 0.12, 0.12)
@export var trail_color := Color(1.0, 0.85, 0.75)
@export var background_color := Color(0.08, 0.05, 0.05, 0.85)

var _ratio := 1.0
var _trail_ratio := 1.0
var _trail_delay := 0.0
var _fill: MeshInstance3D
var _trail: MeshInstance3D


func _ready() -> void:
	var border := 0.025
	_make_quad(Vector2(width + border, height + border), background_color, 0)
	_trail = _make_quad(Vector2(width, height), trail_color, 1)
	_fill = _make_quad(Vector2(width, height), fill_color, 2)
	_apply(_fill, _ratio)
	_apply(_trail, _trail_ratio)


func set_ratio(ratio: float, animate := true) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	if animate:
		_trail_delay = 0.35
	else:
		_trail_ratio = _ratio
	if _fill:
		_apply(_fill, _ratio)
		_apply(_trail, _trail_ratio)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_basis = cam.global_basis.orthonormalized() * Basis.from_scale(global_basis.get_scale())
	if _trail_ratio > _ratio:
		_trail_delay -= delta
		if _trail_delay <= 0.0:
			_trail_ratio = move_toward(_trail_ratio, _ratio, delta * 1.5)
			_apply(_trail, _trail_ratio)


## Scales a bar horizontally while keeping it anchored to the left edge.
func _apply(bar: MeshInstance3D, ratio: float) -> void:
	bar.visible = ratio > 0.001
	bar.scale.x = maxf(ratio, 0.001)
	bar.position.x = -width * 0.5 * (1.0 - ratio)


func _make_quad(size: Vector2, color: Color, priority: int) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = priority
	mat.albedo_color = color
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
