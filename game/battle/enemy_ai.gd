class_name EnemyAI
extends RefCounted
## Basic enemy turn logic, shared by every enemy type.
##
## Each turn (max_ap AP; the first move costs move_cost, a second one repeat_move_cost,
## an attack attack_cost):
##   1. Move phase. If a player unit is detected (within the enemy's detection_range squares,
##      diagonals count as one, ignoring obstacles), walk the real path (around obstacles)
##      towards the closest one, using up to move_range squares (stopping next to it if reached).
##      Closest = fewest walking steps; ties -> lowest health; still tied -> random.
##      If no player unit is in range, walk in a straight line in a random direction until
##      move_range is used up or an obstacle is in the way.
##   2. If now next to a player unit (8 directions) and AP >= attack_cost: attack it. Turn ends.
##   3. Otherwise repeat the move phase once more with the AP left (no attack after it).
##   A unit already adjacent at the start of its turn attacks without moving.
##
## Works on any EnemyUnit (game/units/enemy_unit.gd): it reads the unit stats, awaits
## move_along() / attack(), and targets living player Units. New enemy types get this
## behaviour by extending EnemyUnit; give an enemy different behaviour by writing another
## brain with the same take_turn() entry point.

## Move phases per turn: move + attack, or move + move.
const MAX_MOVE_PHASES := 2
## BFS radius used when pathfinding towards a target (covers the whole board).
const SEARCH_STEPS := 200

var grid: GridBoard
## Rolls (and shows) each attack; without one, attacks roll silently.
var combat: CombatResolver


## Seconds an enemy waits after a move before its next action.
const ACTION_GAP := 0.7
## Seconds between the "Attack" caption and the dice duel.
const ATTACK_WINDUP := 1.0


func _init(board: GridBoard, resolver: CombatResolver = null) -> void:
	grid = board
	combat = resolver


func take_turn(enemy: EnemyUnit) -> void:
	var ap: int = enemy.max_ap
	var attacked: bool = await _try_attack(enemy, ap)
	if attacked:
		return
	for phase in MAX_MOVE_PHASES:
		var cost: int = enemy.move_cost if phase == 0 else enemy.repeat_move_cost
		if ap < cost or not _any_player_alive():
			return
		ap -= cost
		_announce(enemy, "1st mov" if phase == 0 else "2nd mov")
		await _move_phase(enemy)
		# breather so the next action (attack or 2nd move) reads as a separate step
		await enemy.get_tree().create_timer(ACTION_GAP).timeout
		var attacked_after_move: bool = await _try_attack(enemy, ap)
		if attacked_after_move:
			return


## Attacks the weakest adjacent player unit if there is one and AP allows. Returns true if it did.
func _try_attack(enemy: EnemyUnit, ap: int) -> bool:
	if ap < enemy.attack_cost:
		return false
	var here := grid.world_to_cell(enemy.global_position)
	var adjacent: Array[Unit] = []
	for p in _alive_players():
		if GridBoard.distance(here, grid.world_to_cell(p.global_position)) == 1:
			adjacent.append(p)
	if adjacent.is_empty():
		return false
	adjacent.shuffle()
	adjacent.sort_custom(func(a: Unit, b: Unit) -> bool: return a.health < b.health)
	var target := adjacent[0]
	enemy.face_toward(target.global_position)
	_announce(enemy, "Attack")
	# let the camera arrive and the player see who is attacking whom before the dice cover it
	await enemy.get_tree().create_timer(ATTACK_WINDUP).timeout
	if not is_instance_valid(target) or not target.is_alive():
		return false
	var result: AttackResult = null
	if combat:
		result = await combat.attack(enemy, target)
	await enemy.attack(target, result)
	return true


## Floating caption over the enemy saying what it is about to do.
func _announce(enemy: EnemyUnit, text: String) -> void:
	DamageNumber.spawn_text(enemy, enemy.health_bar_height + 0.5, text)


func _move_phase(enemy: EnemyUnit) -> void:
	var exclude: Array[RID] = [enemy.get_rid()]
	grid.refresh_blocked(exclude)
	var start := grid.world_to_cell(enemy.global_position)
	var path := _path_to_closest_target(enemy, start)
	if not path.is_empty():
		var steps := mini(enemy.move_range, path.size() - 1)
		if steps > 0:
			await enemy.move_along(_to_points(path.slice(1, steps + 1)))
		return
	await _wander(enemy, start)


## Path (start cell first) to a free square next to the chosen target, or [] if no player
## unit is in range / reachable. A target already adjacent gives [start].
func _path_to_closest_target(enemy: EnemyUnit, start: Vector2i) -> Array[Vector2i]:
	var came := grid.reachable_from(start, SEARCH_STEPS)
	var best: Array[Vector2i] = []
	var best_health := 0
	var candidates := _alive_players()
	candidates.shuffle() # random winner among exact ties
	for p in candidates:
		var target := grid.world_to_cell(p.global_position)
		if GridBoard.distance(start, target) > enemy.detection_range:
			continue
		var path: Array[Vector2i] = []
		if GridBoard.distance(start, target) == 1:
			path = [start]
		else:
			for d in GridBoard.DIRS:
				var candidate := grid.path_to(came, target + d)
				if not candidate.is_empty() and (path.is_empty() or candidate.size() < path.size()):
					path = candidate
		if path.is_empty():
			continue # in range but walled off
		var hp := p.health
		if best.is_empty() or path.size() < best.size() or (path.size() == best.size() and hp < best_health):
			best = path
			best_health = hp
	return best


## Straight line in a random direction until move_range is used or something blocks the way.
## Only directions with at least one free square are considered.
func _wander(enemy: EnemyUnit, start: Vector2i) -> void:
	var dirs := GridBoard.DIRS.duplicate()
	dirs.shuffle()
	for d: Vector2i in dirs:
		var line: Array[Vector2i] = []
		var c := start
		for i in enemy.move_range:
			var n := c + d
			if not grid.is_walkable(n):
				break
			if d.x != 0 and d.y != 0 and (not grid.is_walkable(c + Vector2i(d.x, 0)) or not grid.is_walkable(c + Vector2i(0, d.y))):
				break # same no-corner-cutting rule as pathfinding
			line.append(n)
			c = n
		if not line.is_empty():
			await enemy.move_along(_to_points(line))
			return


func _to_points(cells: Array) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for c: Vector2i in cells:
		points.append(grid.cell_to_world(c))
	return points


func _alive_players() -> Array[Unit]:
	return Unit.living(grid.get_tree(), Unit.Team.PLAYER)


func _any_player_alive() -> bool:
	return not _alive_players().is_empty()
