extends EnemyUnit
## Goblin enemy (HD Blender model). Turn logic comes from EnemyAI via EnemyUnit; this script is
## only the goblin's look and feel: procedural idle (breathing, sway, ears, head), a hop while
## walking, a wind-up lunge for attack(), a white flash + flinch when hit, and on death it
## topples over and is replaced by a corpse that sinks away.

@export var corpse_scene: PackedScene = preload("res://game/units/goblin/goblin_corpse.tscn")

## How high the corpse model's root sits above the ground (matches the Blender export).
const CORPSE_LIFT := 0.178

var _time := 0.0
var _hit_tween: Tween
var _flash_tween: Tween
var _flash_material: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _body: Node3D
var _body_rest_pos: Vector3
var _body_rest_rot: Vector3
var _head: Node3D
var _flinch := 0.0
var _ears: Array[Node3D] = []
var _ear_rest: Array[Vector3] = []

@onready var collision: CollisionShape3D = $Collision


func _ready() -> void:
	super()
	GoblinMaterials.apply(model)
	_time = randf() * 10.0
	_body = _find("Body*")
	if _body:
		_body_rest_pos = _body.position
		_body_rest_rot = _body.rotation # the model is built hunched forward
	_head = _find("HeadPivot*")
	for pattern in ["Ear_L*", "Ear_R*"]:
		var ear := _find(pattern)
		if ear:
			_ears.append(ear)
			_ear_rest.append(ear.rotation)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node as MeshInstance3D)

	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1.0, 1.0, 1.0, 0.0)


func _find(pattern: String) -> Node3D:
	var found := model.find_children(pattern, "Node3D", true, false)
	return found[0] as Node3D if found.size() > 0 else null


func _process(delta: float) -> void:
	super(delta)
	if not is_alive():
		return
	_time += delta
	# Idle: breathing, shifty side-to-side sway, twitching ears, head glancing around.
	# _flinch (set on hit) hunches him further behind his shield and decays back.
	_flinch = move_toward(_flinch, 0.0, delta * 2.5)
	if _body:
		var breath := sin(_time * 3.0)
		_body.position = _body_rest_pos + Vector3(0.0, breath * 0.012, 0.0)
		_body.rotation = _body_rest_rot + Vector3(_flinch * 0.45, 0.0, sin(_time * 1.3) * 0.06)
		_body.scale = Vector3(1.0 + breath * 0.02, 1.0 - breath * 0.012, 1.0 + breath * 0.02)
		if is_walking():
			_body.position.y += absf(sin(_time * 12.0)) * 0.07 # waddle-hop
	if _head:
		_head.rotation.y = sin(_time * 0.9) * 0.2
	for i in _ears.size():
		var twitch := pow(maxf(0.0, sin(_time * 1.7 + i * 1.3)), 12.0) * 0.35
		_ears[i].rotation = _ear_rest[i] + Vector3(twitch + sin(_time * 4.0 + i) * 0.04, 0.0, 0.0)


# ---------------------------------------------------------------- attack

## Melee: turn to the target, wind up, lunge, deal attack_damage, step back. Awaitable.
func attack(target: Unit) -> void:
	if not is_alive() or not is_instance_valid(target):
		return
	_busy = true
	face_toward(target.global_position)
	await get_tree().create_timer(0.3).timeout
	if _hit_tween:
		_hit_tween.kill()
	var dir := target.global_position - global_position
	dir.y = 0.0
	dir = global_basis.inverse() * dir.normalized() # model.position is in local space
	var t := create_tween()
	t.tween_property(model, "position", -dir * 0.15, 0.2).set_ease(Tween.EASE_OUT) # wind up
	t.tween_property(model, "position", dir * 0.45, 0.1).set_ease(Tween.EASE_IN)
	await t.finished
	if is_instance_valid(target):
		target.take_hit(global_position, attack_damage)
	var back := create_tween()
	back.tween_property(model, "position", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await back.finished
	_busy = false


# ---------------------------------------------------------------- hit / death

func _on_hit(from: Vector3, _damage: int) -> void:
	_flash()
	var push := global_position - from
	push.y = 0.0
	var local_push := (global_basis.inverse() * push.normalized()) * 0.25
	_flinch = 1.0
	if _hit_tween:
		_hit_tween.kill()
	model.position = local_push
	model.scale = Vector3(1.2, 0.8, 1.2)
	_hit_tween = create_tween().set_parallel()
	_hit_tween.tween_property(model, "position", Vector3.ZERO, 0.4) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_property(model, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _flash() -> void:
	for m in _meshes:
		m.material_overlay = _flash_material
	if _flash_tween:
		_flash_tween.kill()
	_flash_material.albedo_color = Color(1.0, 0.95, 0.9, 0.85)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_material, "albedo_color:a", 0.0, 0.25)
	_flash_tween.tween_callback(func() -> void:
		for m in _meshes:
			if is_instance_valid(m):
				m.material_overlay = null)


func _on_died() -> void:
	_flash()
	collision.set_deferred("disabled", true)
	if _hit_tween:
		_hit_tween.kill()
	model.position = Vector3.ZERO
	model.scale = Vector3.ONE
	# Hop up, then topple onto his back (front is +Z, so negative X rotation falls backwards).
	var t := create_tween()
	t.tween_property(model, "position:y", 0.35, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(model, "rotation:x", -0.35, 0.15)
	t.tween_property(model, "rotation:x", -PI / 2.0, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(model, "position:y", CORPSE_LIFT, 0.35).set_ease(Tween.EASE_IN)
	t.tween_callback(_become_corpse)


func _become_corpse() -> void:
	var corpse := corpse_scene.instantiate() as Node3D
	get_parent().add_child(corpse)
	# the body itself never rotates (the Model does), so take the facing from the model
	corpse.global_transform = Transform3D(Basis(Vector3.UP, model.rotation.y), global_position)
	queue_free()
