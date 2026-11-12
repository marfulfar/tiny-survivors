extends Node3D
## Goblin corpse: flops onto the ground in a puff of snow, lies there, then sinks into
## the snow and removes itself. The goblin's 0.5 s fall plus linger + sink = 5 s after death.

@export var linger_time := 3.5
@export var sink_time := 1.0
@export var sink_depth := 0.7

@onready var model: Node3D = $Model


func _ready() -> void:
	GoblinMaterials.apply(model)
	_snow_puff()
	var t := create_tween()
	# small flop when it hits the ground
	t.tween_property(model, "position:y", 0.06, 0.1).set_ease(Tween.EASE_OUT)
	t.tween_property(model, "position:y", 0.0, 0.12).set_ease(Tween.EASE_IN)
	t.tween_interval(maxf(linger_time - 0.22, 0.0))
	# sink into the ground, flattening a little as it goes
	t.tween_property(model, "position:y", -sink_depth, sink_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(model, "scale", Vector3(1.15, 0.4, 1.15), sink_time)
	t.tween_callback(queue_free)


## A one-shot burst of snow dust where the body lands.
func _snow_puff() -> void:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.35, 0.05, 0.6)
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, -1.5, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(0.9, 0.95, 1.0, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	mat.albedo_texture = tex
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	p.position = Vector3(0, 0.05, 0)
	p.emitting = true
