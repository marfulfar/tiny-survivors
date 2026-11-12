class_name BattleMarkers
extends Node3D
## World-space markers: a pulsing gold ring under the selected unit, and a spinning red
## reticle with a bobbing arrow over the current target.

var _time := 0.0
var _ring_unit: Node3D
var _target: Node3D
var _ring: MeshInstance3D
var _reticle: Node3D
var _reticle_ring: MeshInstance3D
var _reticle_arrow: MeshInstance3D


func _ready() -> void:
	_ring = _flat_ring(0.42, 0.52, Color(1.0, 0.85, 0.3, 0.9))
	_ring.visible = false
	add_child(_ring)

	_reticle = Node3D.new()
	_reticle.visible = false
	add_child(_reticle)
	_reticle_ring = _flat_ring(0.55, 0.68, Color(1.0, 0.25, 0.2, 0.9))
	_reticle_ring.position.y = 0.03
	_reticle.add_child(_reticle_ring)
	# four notches on the ring so its rotation reads
	for i in 4:
		var notch := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 0.02, 0.28)
		box.material = _material(Color(1.0, 0.25, 0.2, 0.9))
		notch.mesh = box
		var a := TAU * i / 4.0
		notch.position = Vector3(sin(a), 0.0, cos(a)) * 0.78
		notch.rotation.y = a
		_reticle_ring.add_child(notch)
	_reticle_arrow = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.2
	cone.bottom_radius = 0.0
	cone.height = 0.35
	cone.radial_segments = 12
	cone.material = _material(Color(1.0, 0.25, 0.2, 1.0))
	_reticle_arrow.mesh = cone
	_reticle_arrow.position.y = 2.0
	_reticle.add_child(_reticle_arrow)


func show_ring(unit: Node3D) -> void:
	_ring_unit = unit
	_ring.visible = unit != null


func hide_ring() -> void:
	show_ring(null)


func show_reticle(target: Node3D) -> void:
	_target = target
	_reticle.visible = target != null


func hide_reticle() -> void:
	show_reticle(null)


func reticle_target() -> Node3D:
	return _target if _reticle.visible else null


func _process(delta: float) -> void:
	_time += delta
	if _ring.visible:
		if not is_instance_valid(_ring_unit):
			hide_ring()
		else:
			_ring.global_position = _ring_unit.global_position + Vector3(0.0, 0.03, 0.0)
			_ring.scale = Vector3.ONE * (1.0 + 0.05 * sin(_time * 4.0))
	if _reticle.visible:
		if not is_instance_valid(_target):
			hide_reticle()
		else:
			_reticle.global_position = _target.global_position
			_reticle_ring.rotation.y = _time * 1.5
			_reticle_arrow.position.y = 2.0 + 0.12 * sin(_time * 5.0)


func _flat_ring(inner: float, outer: float, color: Color) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 48
	torus.ring_segments = 8
	torus.material = _material(color)
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.scale = Vector3(1.0, 0.15, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.render_priority = 3
	return m
