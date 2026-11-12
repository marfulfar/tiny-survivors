class_name Knight
extends AnimatedUnit
## Player knight (KayKit Knight model, game/units/models/knight.tscn) with sword and shield.
## Abilities: Melee (one adjacent enemy) and Sliced Attack (a spinning slash that hits every
## enemy in the 8 cells around him). The TacticsController picks targets and calls these.

@export_group("Melee")
@export var melee_cost := 2
## The free KayKit set has no sword swing; Throw reads as a chop.
@export var melee_animation := &"general/Throw"
## Seconds into melee_animation when the blow lands.
@export var melee_hit_time := 0.55

@export_group("Sliced Attack")
@export var slice_cost := 3
## Cells around the knight the slash reaches (1 = the 8 surrounding cells).
@export var slice_radius := 1
@export var slice_color := Color(1.0, 0.9, 0.6)


## Turns, swings and hits `target` on the downswing, then emits action_finished.
## `result` is the already-rolled attack (rolled here, silently, if not given).
func melee_attack(target: Unit, result: AttackResult = null) -> void:
	_busy = true
	if result == null:
		result = CombatRules.resolve(self, target)
	face_toward(target.global_position)
	await get_tree().create_timer(0.2).timeout
	var swung := play_oneshot(melee_animation)
	await get_tree().create_timer(melee_hit_time if swung else 0.1).timeout
	if is_instance_valid(target) and target.is_alive():
		target.receive_attack(result, global_position)
	await get_tree().create_timer(0.5).timeout
	_busy = false
	action_finished.emit()


## Spins once with the sword out; every unit in `victims` is attacked (rolled separately).
func sliced_attack(victims: Array) -> void:
	_busy = true
	play_oneshot(melee_animation)
	var start := model.rotation.y
	var spin := create_tween()
	spin.tween_property(model, "rotation:y", start + TAU, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_spawn_slash_ring()
	await get_tree().create_timer(0.3).timeout
	# each victim gets its own (silent) to-hit roll
	for v in victims:
		if is_instance_valid(v) and v.is_alive():
			v.receive_attack(CombatRules.resolve(self, v), global_position)
	await spin.finished
	model.rotation.y = start
	await get_tree().create_timer(0.5).timeout
	_busy = false
	action_finished.emit()


## A flat glowing ring that sweeps out over the slashed cells and fades.
func _spawn_slash_ring() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 48
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(slice_color, 0.85)
	torus.material = mat
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.position = Vector3(0.0, 0.7, 0.0)
	ring.scale = Vector3(0.3, 0.15, 0.3)
	var reach := slice_radius + 0.5
	var t := create_tween().set_parallel()
	t.tween_property(ring, "scale", Vector3(reach, 0.15, reach), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	t.chain().tween_callback(ring.queue_free)
