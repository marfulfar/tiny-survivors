class_name Unit
extends CharacterBody3D
## Base for everything that takes turns on the board: player characters and enemies.
##
## Owns what every unit shares: team, health, action points (AP), the floating health bar and
## AP pips, walking a grid path, turning to face things, and taking damage. Subclasses add
## looks and abilities through the hooks at the bottom (_on_hit, _on_died, _on_walking_changed).
##
## Scene contract: the unit scene's root uses this script (or a subclass) and has a child
## named "Model" (the visual, rotated to face) plus a CollisionShape3D (the grid treats the
## body as an obstacle). Teams are tracked with groups, see GROUP_PLAYERS / GROUP_ENEMIES.
## The model's front is +Z.

signal died
signal ap_changed(points: int, max_points: int)
signal health_changed(current: int, maximum: int)
## Emitted when a player-issued action (move, ability) finishes.
signal action_finished

enum Team { PLAYER, ENEMY }

const GROUP_PLAYERS := &"player_units"
const GROUP_ENEMIES := &"enemy_units"

@export var display_name := "Unit"
@export var team := Team.PLAYER

@export_group("Stats")
@export var max_health := 10
@export var max_ap := 3
## AP for the first move of a turn.
@export var move_cost := 1
## AP for every further move in the same turn (with 3 AP: 1 + 2, so two moves per turn).
@export var repeat_move_cost := 2
## Squares per move action (diagonal steps count as one).
@export var move_range := 6

@export_group("Combat")
## Added to this unit's to-hit d20 to make the damage of a landed hit (see CombatRules).
@export var strength := 0
## Taken off the damage of every hit this unit receives.
@export var armour := 0

@export_group("Movement")
## Metres per second while walking a path.
@export var walk_speed := 4.5
## How fast the model turns while acting (radians-ish per second, used as a lerp rate).
@export var turn_speed := 12.0
## When idle, slowly turn to watch the closest living opponent.
@export var watch_opponents := false
@export var idle_turn_speed := 3.0

@export_group("Overhead")
## Height of the health bar above the unit's origin. AP pips sit just below it.
@export var health_bar_height := 2.0
@export var show_ap_pips := true
## Height that attacks and projectiles aim at.
@export var aim_height := 0.8

var health := 0
var ap := 0

@onready var model: Node3D = $Model

var _busy := false
var _walking := false
var _dead := false
var _target_yaw := 0.0
var _health_bar: HealthBar3D
var _ap_display: APDisplay3D


func _ready() -> void:
	add_to_group(group_for(team))
	health = max_health
	ap = max_ap
	_target_yaw = model.rotation.y
	_health_bar = HealthBar3D.new()
	_health_bar.position = Vector3(0.0, health_bar_height, 0.0)
	add_child(_health_bar)
	_health_bar.set_ratio(1.0, false)
	if show_ap_pips:
		_ap_display = APDisplay3D.new()
		_ap_display.position = Vector3(0.0, health_bar_height - 0.4, 0.0)
		add_child(_ap_display)
	_emit_ap()


func _process(delta: float) -> void:
	if _dead:
		return
	var rate := turn_speed
	if watch_opponents and not _busy:
		var other := closest_opponent()
		if other:
			_face_yaw_to(other.global_position)
		rate = idle_turn_speed
	model.rotation.y = lerp_angle(model.rotation.y, _target_yaw, rate * delta)


# ---------------------------------------------------------------- queries

static func group_for(t: Team) -> StringName:
	return GROUP_PLAYERS if t == Team.PLAYER else GROUP_ENEMIES


## Living units of a team, in scene-tree order.
static func living(tree: SceneTree, t: Team) -> Array[Unit]:
	var out: Array[Unit] = []
	for n in tree.get_nodes_in_group(group_for(t)):
		var u := n as Unit
		if u and u.is_alive():
			out.append(u)
	return out


func opponent_team() -> Team:
	return Team.ENEMY if team == Team.PLAYER else Team.PLAYER


func closest_opponent() -> Unit:
	var best: Unit = null
	for u in living(get_tree(), opponent_team()):
		if best == null or global_position.distance_squared_to(u.global_position) < global_position.distance_squared_to(best.global_position):
			best = u
	return best


func is_alive() -> bool:
	return not _dead


func is_busy() -> bool:
	return _busy


func is_walking() -> bool:
	return _walking


func get_aim_point() -> Vector3:
	return global_position + Vector3(0.0, aim_height, 0.0)


# ---------------------------------------------------------------- action points

## Moves already made this turn (reset by refill_ap).
var moves_this_turn := 0


## AP the next move costs: move_cost for the first one, repeat_move_cost after that.
func next_move_cost() -> int:
	return move_cost if moves_this_turn == 0 else repeat_move_cost


## Pays for a move and counts it. False (nothing spent) if AP is short.
func spend_move() -> bool:
	if not spend_ap(next_move_cost()):
		return false
	moves_this_turn += 1
	return true


func spend_ap(cost: int) -> bool:
	if ap < cost:
		return false
	ap -= cost
	_emit_ap()
	return true


func refill_ap() -> void:
	ap = max_ap
	moves_this_turn = 0
	_emit_ap()


## Shows or hides the floating health bar and AP pips (e.g. behind the battle end screen).
func set_overhead_visible(on: bool) -> void:
	if _health_bar and not _dead:
		_health_bar.visible = on
	if _ap_display and not _dead:
		_ap_display.visible = on


## Highlights the pips an action would spend (0 = none).
func preview_ap(cost: int) -> void:
	if _ap_display:
		_ap_display.set_preview(cost)


func _emit_ap() -> void:
	if _ap_display:
		_ap_display.set_points(ap, max_ap)
	ap_changed.emit(ap, max_ap)


# ---------------------------------------------------------------- movement

## Walks through the given world points (cell centres) in order. Awaitable; also emits
## action_finished when done so the player controller can wait on the signal instead.
func move_along(points: Array[Vector3]) -> void:
	if points.is_empty() or _dead:
		return
	_busy = true
	_set_walking(true)
	for p in points:
		var dest := Vector3(p.x, global_position.y, p.z)
		var dist := global_position.distance_to(dest)
		_face_yaw_to(dest)
		var t := create_tween()
		t.tween_property(self, "global_position", dest, dist / walk_speed)
		await t.finished
		if _dead:
			break
	_set_walking(false)
	_busy = false
	action_finished.emit()


func face_toward(point: Vector3) -> void:
	_face_yaw_to(point)


func _face_yaw_to(point: Vector3) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		_target_yaw = atan2(to.x, to.z) # the model's front is +Z


func _set_walking(walking: bool) -> void:
	if _walking == walking:
		return
	_walking = walking
	_on_walking_changed(walking)


# ---------------------------------------------------------------- damage

const MISS_COLOR := Color(0.7, 0.82, 1.0)
const CRIT_COLOR := Color(1.0, 0.55, 0.15)


## Applies a rolled attack when the blow lands: damage on a hit, a floating "Miss" otherwise,
## "Blocked" for a hit that armour soaked completely.
func receive_attack(result: AttackResult, from: Vector3) -> void:
	if _dead or result == null:
		return
	if not result.hit:
		DamageNumber.spawn_text(self, health_bar_height - 0.2, "Miss", MISS_COLOR)
	elif result.damage <= 0:
		DamageNumber.spawn_text(self, health_bar_height - 0.2, "Blocked", MISS_COLOR)
	else:
		if result.critical:
			DamageNumber.spawn_text(self, health_bar_height + 0.4, "Critical!", CRIT_COLOR)
		take_hit(from, result.damage)


## Raw damage, no roll (debug keys, environment). Attacks go through receive_attack.
func take_hit(from: Vector3, damage := 1) -> void:
	if _dead:
		return
	health = maxi(health - damage, 0)
	_health_bar.set_ratio(float(health) / max_health)
	health_changed.emit(health, max_health)
	DamageNumber.spawn(get_parent(), global_position + Vector3.UP * (health_bar_height - 0.3), damage)
	if health == 0:
		_die()
	else:
		_on_hit(from, damage)


func _die() -> void:
	_dead = true
	_set_walking(false)
	var t := create_tween()
	t.tween_interval(0.3)
	t.tween_property(_health_bar, "scale", Vector3(1.0, 0.0, 1.0), 0.15)
	t.tween_callback(_health_bar.hide)
	if _ap_display:
		_ap_display.hide()
	_on_died()
	died.emit()


# ---------------------------------------------------------------- hooks for subclasses

## Took damage but survived.
func _on_hit(_from: Vector3, _damage: int) -> void:
	pass


## Health reached 0 (is_alive() is already false).
func _on_died() -> void:
	pass


## Started or stopped walking a path.
func _on_walking_changed(_walking_now: bool) -> void:
	pass
