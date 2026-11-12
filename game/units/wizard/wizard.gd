class_name Wizard
extends AnimatedUnit
## Player wizard (KayKit Mage model, game/units/models/mage.tscn). Everything shared with other
## units (health, AP, walking, idle/walk/hit/death clips) lives in Unit / AnimatedUnit; this adds
## the Fireball ability.

@export_group("Fireball")
@export var shoot_cost := 2
## Squares (diagonals count as one) within which Shoot can target an enemy.
@export var shoot_range := 10
@export var fireball_scene: PackedScene = preload("res://game/effects/fireball/fireball.tscn")
@export var cast_animation := &"general/Throw"
## Seconds into cast_animation when the fireball leaves the staff (arm whips forward ~0.6 s).
@export var cast_release_time := 0.6
## Launch point: this high above the feet...
@export var cast_height := 1.2
## ...and this far in front of the wizard, towards the target.
@export var cast_forward := 0.5

@export_group("Special Attack")
@export var special_cost := 3
## Squares (same measure as Shoot) to the centre of the blast.
@export var special_range := 10
## Side of the square blast, in cells (6 = 6x6).
@export var special_area := 6
@export var special_color := Color(0.6, 0.85, 1.0)


## Turns to face the target, casts a fireball at it, then emits action_finished.
## `result` is the already-rolled attack (rolled here, silently, if not given).
func shoot_at(target: Node3D, result: AttackResult = null) -> void:
	_busy = true
	if result == null and target is Unit:
		result = CombatRules.resolve(self, target as Unit)
	face_toward(target.global_position)
	await get_tree().create_timer(0.25).timeout
	if play_oneshot(cast_animation):
		await get_tree().create_timer(cast_release_time).timeout
	_spawn_fireball(target, result)
	await get_tree().create_timer(0.8 - minf(cast_release_time, 0.8) + 0.2).timeout
	_busy = false
	action_finished.emit()


## The fireball leaves from a fixed point in front of the chest (cast_height, cast_forward)
## rather than the swinging staff tip: mid-throw the tip can dip to the ground and the shot
## would fizzle there. A fixed origin also matches the controller's line-of-sight sweep.
## Special Attack: lobs a blue-white fireball at `point` on the ground; when it bursts every
## unit in `victims` (chosen by the controller: enemies inside the blast) is attacked.
func special_attack(point: Vector3, victims: Array) -> void:
	_busy = true
	face_toward(point)
	await get_tree().create_timer(0.25).timeout
	if play_oneshot(cast_animation):
		await get_tree().create_timer(cast_release_time).timeout
	var facing := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	facing = facing.normalized() if facing.length_squared() > 0.0001 else Vector3(sin(model.rotation.y), 0.0, cos(model.rotation.y))
	var fireball := fireball_scene.instantiate()
	fireball.tint = special_color
	fireball.blast_scale = special_area / 2.4
	get_tree().current_scene.add_child(fireball)
	fireball.launch_at_point(global_position + Vector3.UP * cast_height + facing * cast_forward, point + Vector3.UP * 0.1, self)
	var at: Vector3 = await fireball.exploded
	# area blasts roll to hit each victim too, but silently (one overlay per victim would drag)
	for v in victims:
		if is_instance_valid(v) and v.is_alive():
			v.receive_attack(CombatRules.resolve(self, v), at)
	await get_tree().create_timer(0.7).timeout
	_busy = false
	action_finished.emit()


func _spawn_fireball(target: Node3D, result: AttackResult = null) -> void:
	var facing := Vector3(sin(model.rotation.y), 0.0, cos(model.rotation.y))
	var aim: Vector3
	if is_instance_valid(target):
		aim = target.call("get_aim_point") if target.has_method("get_aim_point") else target.global_position + Vector3.UP * 0.8
		var flat := aim - global_position
		flat.y = 0.0
		if flat.length_squared() > 0.0001:
			facing = flat.normalized()
	var origin := global_position + Vector3.UP * cast_height + facing * cast_forward
	var dir := (aim - origin).normalized() if is_instance_valid(target) else facing
	var fireball := fireball_scene.instantiate()
	fireball.payload = result
	get_tree().current_scene.add_child(fireball)
	fireball.launch(origin, dir, self, false)
