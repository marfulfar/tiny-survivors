class_name EnemyUnit
extends AnimatedUnit
## Base for enemies. EnemyAI (game/battle/enemy_ai.gd) drives anything extending this:
## it moves the unit with move_along() and calls attack() when next to a player unit.
## Being an AnimatedUnit, a KayKit model gets idle / walk / hit / death clips for free.
## On death the body lies on the ground for a while, then sinks away and is removed.

@export_group("Detection")
## Squares (diagonals count as one, obstacles ignored) within which this enemy notices a player
## unit and heads for it. Separate from move_range, which is how far it walks per move.
@export_range(1, 60) var detection_range := 20 ## cells: how close a player must be before this enemy starts moving toward them

@export_group("Attack")
@export var attack_cost := 2
## Clip played for the attack. The free KayKit set has no melee swing; Throw reads as a chop.
@export var attack_animation := &"general/Throw"
## Seconds into attack_animation when the blow lands.
@export var attack_hit_time := 0.6

@export_group("Corpse")
## Seconds the body stays down after the death clip before sinking. Negative keeps it forever.
@export var corpse_linger := 3.0
@export var corpse_sink_time := 1.0
@export var corpse_sink_depth := 1.0


func _init() -> void:
	# Enemy defaults; a scene can still override any of them in the Inspector.
	team = Team.ENEMY
	show_ap_pips = false
	watch_opponents = true


## Melee attack on an adjacent unit: turn, swing, apply the rolled result on the downswing. Awaitable.
## `result` is the already-rolled attack (rolled here, silently, if not given).
func attack(target: Unit, result: AttackResult = null) -> void:
	if not is_alive() or not is_instance_valid(target):
		return
	if result == null:
		result = CombatRules.resolve(self, target)
	_busy = true
	face_toward(target.global_position)
	await get_tree().create_timer(0.25).timeout
	var swung := play_oneshot(attack_animation)
	await get_tree().create_timer(attack_hit_time if swung else 0.1).timeout
	if is_instance_valid(target) and is_alive():
		target.receive_attack(result, global_position)
	await get_tree().create_timer(0.4).timeout
	_busy = false


func _on_died() -> void:
	super()
	# a body on the ground is not an obstacle: let units walk and shoot through
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", true)
	if corpse_linger < 0.0:
		return
	var t := create_tween()
	t.tween_interval(1.0 + corpse_linger) # ~1 s for the death clip itself
	t.tween_property(self, "global_position:y", global_position.y - corpse_sink_depth, corpse_sink_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)
