extends Area3D
## A fireball that flies in a straight line. It explodes on the first body it touches
## (anything except whoever cast it) or fizzles out after max_distance.
## Bodies with a take_hit(position) method get notified when hit.

@export var speed := 14.0
@export var max_distance := 30.0
@export var light_energy := 3.0
@export var damage := 1
## Recolours the fireball (model, light, sparks, puff). Alpha 0 keeps the default orange.
@export var tint := Color(0, 0, 0, 0)
## Size multiplier for the explosion puff (area attacks use a bigger one).
@export var blast_scale := 1.0

## Emitted when the fireball bursts, with the burst position.
signal exploded(at: Vector3)

var direction := Vector3.FORWARD
var caster: Node
## Pre-rolled attack: when set, its defender gets receive_attack() instead of raw damage.
var payload: AttackResult

var _travelled := 0.0
var _done := false
var _time := 0.0
var _grow := 0.2
var _trail: GPUParticles3D
var _target_point: Variant = null

@onready var model: Node3D = $Model
@onready var light: OmniLight3D = $Light

static var _spark_material: StandardMaterial3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if tint.a > 0.0:
		_apply_tint()
	_trail = _make_particles(40, 0.45, false, 0.12, Vector2(0.2, 0.7))
	_trail.emitting = true


## Place the fireball at `from`, point it along `dir` and remember who cast it.
## flatten = true keeps it level; false lets it fly at an aimed angle.
func launch(from: Vector3, dir: Vector3, who: Node, flatten := true) -> void:
	caster = who
	direction = (Vector3(dir.x, 0.0, dir.z) if flatten else dir).normalized()
	global_position = from
	# use_model_front = true: the model's +Z (its nose) faces the travel direction.
	global_basis = Basis.looking_at(direction, Vector3.UP, true)


## Ground-targeted shot: flies to `point` passing through anything on the way (the caller
## checked line of sight) and bursts there, emitting exploded.
func launch_at_point(from: Vector3, point: Vector3, who: Node) -> void:
	launch(from, point - from, who, false)
	max_distance = from.distance_to(point)
	_target_point = point
	set_deferred("monitoring", false)


func _physics_process(delta: float) -> void:
	if _done:
		return
	var step := speed * delta
	global_position += direction * step
	_travelled += step
	if _travelled >= max_distance:
		if _target_point != null:
			global_position = _target_point
			_explode()
		else:
			_fizzle()


func _process(delta: float) -> void:
	_time += delta
	if _done:
		return
	_grow = move_toward(_grow, 1.0, delta * 8.0)
	model.scale = Vector3.ONE * _grow * (1.0 + 0.08 * sin(_time * 35.0))
	model.rotate_object_local(Vector3.BACK, delta * 10.0)
	light.light_energy = light_energy * (0.85 + 0.15 * sin(_time * 23.0))


func _on_body_entered(body: Node3D) -> void:
	if _done or body == caster:
		return
	if payload and body == payload.defender:
		(body as Unit).receive_attack(payload, global_position)
	elif body.has_method("take_hit"):
		body.take_hit(global_position, damage)
	_explode()


func _explode() -> void:
	_done = true
	exploded.emit(global_position)
	set_deferred("monitoring", false)
	model.visible = false
	_trail.emitting = false

	var burst := _make_particles(int(70 * blast_scale), 0.7, true, 0.15 * blast_scale, Vector2(2.5, 6.0) * sqrt(blast_scale))
	burst.emitting = true

	# Quick expanding puff of flame
	var puff := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(tint, 0.85) if tint.a > 0.0 else Color(1.0, 0.55, 0.1, 0.85)
	sphere.material = mat
	puff.mesh = sphere
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(puff)

	var t := create_tween().set_parallel()
	t.tween_property(puff, "scale", Vector3.ONE * 4.0 * blast_scale, 0.35 + 0.1 * blast_scale).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	light.light_energy = light_energy * 4.0
	light.omni_range *= 2.0
	t.tween_property(light, "light_energy", 0.0, 0.6)

	await get_tree().create_timer(1.0).timeout
	queue_free()


func _fizzle() -> void:
	_done = true
	set_deferred("monitoring", false)
	_trail.emitting = false
	var t := create_tween().set_parallel()
	t.tween_property(model, "scale", Vector3.ZERO, 0.25)
	t.tween_property(light, "light_energy", 0.0, 0.25)
	await get_tree().create_timer(0.6).timeout
	queue_free()


func _make_particles(amount: int, lifetime: float, one_shot: bool, radius: float, velocity: Vector2) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.spread = 180.0
	pm.initial_velocity_min = velocity.x
	pm.initial_velocity_max = velocity.y
	pm.damping_min = 3.0
	pm.damping_max = 6.0
	pm.gravity = Vector3(0.0, 1.5, 0.0) # embers rise
	pm.scale_min = 0.6
	pm.scale_max = 1.3

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	if tint.a > 0.0:
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(tint, 0.9), Color(tint.darkened(0.6), 0.0)])
	else:
		grad.colors = PackedColorArray([Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.45, 0.05, 0.9), Color(0.6, 0.08, 0.02, 0.0)])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	quad.material = _get_spark_material()
	p.draw_pass_1 = quad

	add_child(p)
	return p


static func _get_spark_material() -> StandardMaterial3D:
	if _spark_material == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX # additive washes out against bright snow
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		m.albedo_texture = tex
		_spark_material = m
	return _spark_material


## Recolours the imported model's materials (per-instance copies) and the light.
func _apply_tint() -> void:
	light.light_color = tint
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s) as BaseMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as BaseMaterial3D
			m.albedo_color = Color(tint.lerp(Color.WHITE, 0.35), src.albedo_color.a)
			m.albedo_texture = null
			m.emission_enabled = true
			m.emission = tint
			m.emission_energy_multiplier = 2.0
			mi.set_surface_override_material(s, m)
