class_name TacticsController
extends Node
## Turn flow and player input for a battle (lives in game/battle/battle.tscn).
##  * Click one of your units (or its square) to select it: its action menu opens beside it.
##  * Move: reachable squares + a path arrow; click a square to walk there.
##  * Shoot (units with shoot_at(), e.g. the Wizard): auto-targets the closest visible enemy
##    within shoot_range squares. Click the target (or press Space) to cast.
##  * Right-click / Esc steps back. End Turn (button or Enter) hands over to the enemies:
##    each living enemy acts in turn (EnemyAI), then every player unit's AP refills.
##  * Killing every enemy wins, losing every player unit loses: the HUD hides, the camera
##    circles the hero (or the last one to fall) and the BattleEndScreen offers what next.
## Units are discovered through their team groups (Unit.GROUP_PLAYERS / GROUP_ENEMIES), so a
## mission only has to place unit scenes; nothing here names a specific character.

enum Mode { IDLE, MENU, MOVE, SHOOT, MELEE, SPECIAL, BUSY, ENEMY_TURN, GAME_OVER }

const NO_CELL := Vector2i(1 << 20, 1 << 20)
## Radius swept for line-of-sight checks: fireball radius (0.2) + margin for the cast point's offset.
const LOS_CLEARANCE := 0.35
## Pause before the first enemy acts and between enemies, so the player can follow.
const ENEMY_PAUSE := 0.4
const ACTION_MOVE := &"move"
const ACTION_SHOOT := &"shoot"
const ACTION_SPECIAL := &"special"
const ACTION_MELEE := &"melee"
const ACTION_SLICE := &"slice"
const BLAST_COLOR := Color(0.55, 0.8, 1.0, 0.45)
## Height the line-of-sight sweep starts from, above the shooter's feet.
const EYE_HEIGHT := 1.5
const MAIN_MENU := "res://game/menus/main_menu/main_menu.tscn"
## Seconds between the deciding death and the end screen, so the death plays out.
const END_DELAY := 1.8

@export var grid_path := NodePath("../Grid")
@export var camera_path := NodePath("../CameraRig")

var mode := Mode.IDLE
var turn := 1
var selected: Unit
var grid: GridBoard
var camera: CameraRig
var hud: BattleHUD
var markers: BattleMarkers
## Rolls single-target attacks and shows the dice duel (shared with EnemyAI).
var combat: CombatResolver

var _reach := {}
var _hover_cell := NO_CELL
var _targets: Array[Node3D] = []
var _target: Node3D
var _last_fallen: Unit
var _blast_key := NO_CELL ## lower corner of the aimed blast square
var _blast_cells: Array[Vector2i] = []
var _blast_center := Vector3.ZERO
var _blast_ok := false
var _end_screen: BattleEndScreen


func _ready() -> void:
	grid = get_node(grid_path) as GridBoard
	camera = get_node_or_null(camera_path) as CameraRig
	hud = BattleHUD.new()
	add_child(hud)
	hud.action_pressed.connect(_on_action_pressed)
	hud.action_hovered.connect(_on_action_hovered)
	hud.end_turn_pressed.connect(_end_turn)
	combat = CombatResolver.new(hud.duel)
	markers = BattleMarkers.new()
	add_child(markers)
	hud.set_turn(turn)
	# Units may sit after the battle rig in the tree; wait until they have all joined their groups.
	_start_battle.call_deferred()


func _start_battle() -> void:
	for u in _players():
		u.ap_changed.connect(_on_ap_changed.bind(u))
		u.action_finished.connect(_on_action_finished.bind(u))
		u.died.connect(func() -> void:
			_last_fallen = u
			if _players().is_empty():
				_finish_battle(false))
	for e in _enemies():
		e.died.connect(_on_enemy_died)
	hud.sidebar.setup(_players(), _enemies())
	hud.sidebar.unit_clicked.connect(_on_sidebar_unit_clicked)
	var first := _players()
	if not first.is_empty():
		_select(first[0])
		_focus_camera_on(first[0])
	_set_mode(Mode.ENEMY_TURN) # input locked until the opening banner is gone
	hud.set_help("")
	await hud.turn_banner.play(true, turn)
	_set_mode(Mode.IDLE)


## World position of the square under the cursor in Move mode, else null (used by OcclusionFader).
func hover_point() -> Variant:
	if mode == Mode.MOVE and _hover_cell != NO_CELL:
		return grid.cell_to_world(_hover_cell)
	return null


func _players() -> Array[Unit]:
	return Unit.living(get_tree(), Unit.Team.PLAYER)


func _enemies() -> Array[Unit]:
	return Unit.living(get_tree(), Unit.Team.ENEMY)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_mouse_move(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			# right-drag pans the camera; only a plain right-click cancels
			if not (camera and camera.right_click_was_drag()):
				_cancel()
	elif event.is_action_pressed("ui_cancel"):
		_cancel()
	elif event.is_action_pressed("cast") and mode == Mode.SHOOT:
		_fire()
	elif event.is_action_pressed("cast") and mode == Mode.MELEE:
		_fire_melee()
	elif event.is_action_pressed("cast") and mode == Mode.SPECIAL:
		_fire_special()
	elif OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F4:
		# debug only: the next attack rolls 20 vs 20 (critical that beats a tie)
		Dice.force_next([20, 20])
		hud.toast("Debug: next attack is a natural 20 vs 20")
	elif OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_F9 or event.keycode == KEY_F10) and mode != Mode.GAME_OVER:
		# debug only: F9 wins (kills every enemy), F10 loses (kills every player unit)
		var team := Unit.Team.ENEMY if event.keycode == KEY_F9 else Unit.Team.PLAYER
		for u in Unit.living(get_tree(), team):
			u.take_hit(u.global_position, u.health)
	elif event.is_action_pressed("end_turn"):
		_end_turn()


func _on_mouse_move(pos: Vector2) -> void:
	match mode:
		Mode.IDLE, Mode.MENU:
			_set_cursor(_player_unit_at(pos) != null)
		Mode.MOVE:
			_update_move_hover(pos)
		Mode.SHOOT, Mode.MELEE:
			_set_cursor(_targets.has(_pick(pos)))
		Mode.SPECIAL:
			_update_blast(pos)
		_:
			_set_cursor(false)


func _on_left_click(pos: Vector2) -> void:
	match mode:
		Mode.IDLE, Mode.MENU:
			var unit := _player_unit_at(pos)
			if unit and not unit.is_busy():
				_select(unit)
				_open_menu()
			elif mode == Mode.MENU:
				_close_all()
		Mode.MOVE:
			_update_move_hover(pos)
			_confirm_move()
		Mode.SHOOT:
			var hit := _pick(pos)
			if _targets.has(hit):
				_target = hit
				_fire()
		Mode.MELEE:
			var hit := _pick(pos)
			if _targets.has(hit):
				_target = hit
				_fire_melee()
		Mode.SPECIAL:
			_update_blast(pos)
			_fire_special()


func _cancel() -> void:
	match mode:
		Mode.MOVE, Mode.SHOOT, Mode.MELEE, Mode.SPECIAL:
			grid.clear_overlays()
			markers.hide_reticle()
			_open_menu()
		Mode.MENU:
			_close_all()


# ---------------------------------------------------------------- selection & menu

func _select(unit: Unit) -> void:
	if selected and selected != unit:
		selected.preview_ap(0)
	selected = unit
	hud.sidebar.set_selected(unit)
	if camera:
		camera.target = unit
	hud.set_ap(unit.display_name, unit.ap, unit.max_ap)


## Sidebar card clicked: always glide the camera there; on your turn a living player unit
## is also selected, as if clicked in the world.
func _on_sidebar_unit_clicked(unit: Unit) -> void:
	if not is_instance_valid(unit):
		return
	if unit.team == Unit.Team.PLAYER and unit.is_alive() and mode in [Mode.IDLE, Mode.MENU, Mode.MOVE, Mode.SHOOT, Mode.MELEE, Mode.SPECIAL] 			and not unit.is_busy() and not (selected and selected.is_busy()):
		if mode in [Mode.MOVE, Mode.SHOOT, Mode.MELEE, Mode.SPECIAL]:
			grid.clear_overlays()
			markers.hide_reticle()
		_select(unit)
		_focus_camera_on(unit)
		_open_menu()
	elif camera:
		camera.glide_to(unit.global_position)


## Points the camera at a unit and glides over to it (start of a turn / an enemy acting).
func _focus_camera_on(unit: Node3D) -> void:
	if camera:
		camera.target = unit
		camera.focus_on_target(true)


## The actions a unit offers. Move is universal; the rest depend on what the unit can do.
func _actions_for(unit: Unit) -> Array[Dictionary]:
	var actions: Array[Dictionary] = [
		{id = ACTION_MOVE, label = "Move", cost = unit.next_move_cost(),
			desc = "Walk up to %d squares." % unit.move_range},
	]
	if unit.has_method("shoot_at"):
		actions.append({id = ACTION_SHOOT, label = "Shoot", cost = unit.get("shoot_cost"),
			desc = "Fireball the nearest enemy within %d squares (d20 %+d STR vs their d20 + ARM)." % [unit.get("shoot_range"), unit.strength]})
	if unit.has_method("melee_attack"):
		actions.append({id = ACTION_MELEE, label = "Melee", cost = unit.get("melee_cost"),
			desc = "Strike an adjacent enemy (d20 %+d STR vs their d20 + ARM)." % unit.strength})
	if unit.has_method("sliced_attack"):
		actions.append({id = ACTION_SLICE, label = "Sliced Attack", cost = unit.get("slice_cost"),
			desc = "Spin and slash every enemy in the cells around you (rolled per enemy)."})
	if unit.has_method("special_attack"):
		var area: int = unit.get("special_area")
		actions.append({id = ACTION_SPECIAL, label = "Special Attack", cost = unit.get("special_cost"),
			desc = "Fireball a spot up to %d squares away: attacks every enemy in a %dx%d area." \
				% [unit.get("special_range"), area, area]})
	return actions


func _open_menu() -> void:
	if selected == null or not selected.is_alive():
		return
	_set_mode(Mode.MENU)
	selected.preview_ap(0)
	hud.open_menu(selected.display_name, _actions_for(selected))
	_update_menu_state()
	markers.show_ring(selected)


func _close_all() -> void:
	grid.clear_overlays()
	markers.hide_reticle()
	markers.hide_ring()
	hud.close_menu()
	if selected:
		selected.preview_ap(0)
	_set_mode(Mode.IDLE)


func _update_menu_state() -> void:
	var move_reason := ""
	if selected.ap < selected.next_move_cost():
		move_reason = "Not enough AP (needs %d)" % selected.next_move_cost()
	hud.set_action_state(ACTION_MOVE, move_reason)

	if selected.has_method("shoot_at"):
		var cost: int = selected.get("shoot_cost")
		var shoot_reason := ""
		var info := _find_targets()
		if selected.ap < cost:
			shoot_reason = "Not enough AP (needs %d)" % cost
		elif info.in_range.is_empty():
			shoot_reason = "No enemies in range"
		elif info.visible.is_empty():
			shoot_reason = "No clear line of sight"
		hud.set_action_state(ACTION_SHOOT, shoot_reason)

	if selected.has_method("melee_attack"):
		var melee_cost: int = selected.get("melee_cost")
		var melee_reason := ""
		if selected.ap < melee_cost:
			melee_reason = "Not enough AP (needs %d)" % melee_cost
		elif _enemies_around(selected, 1).is_empty():
			melee_reason = "No adjacent enemy"
		hud.set_action_state(ACTION_MELEE, melee_reason)

	if selected.has_method("sliced_attack"):
		var slice_cost: int = selected.get("slice_cost")
		var slice_reason := ""
		if selected.ap < slice_cost:
			slice_reason = "Not enough AP (needs %d)" % slice_cost
		elif _enemies_around(selected, selected.get("slice_radius")).is_empty():
			slice_reason = "No enemy in range"
		hud.set_action_state(ACTION_SLICE, slice_reason)

	if selected.has_method("special_attack"):
		var special_cost: int = selected.get("special_cost")
		hud.set_action_state(ACTION_SPECIAL, "" if selected.ap >= special_cost else "Not enough AP (needs %d)" % special_cost)


func _on_action_pressed(id: StringName) -> void:
	match id:
		ACTION_MOVE:
			_start_move()
		ACTION_SHOOT:
			_start_shoot()
		ACTION_SPECIAL:
			_start_special()
		ACTION_MELEE:
			_start_melee()
		ACTION_SLICE:
			_do_slice()


func _on_action_hovered(id: StringName) -> void:
	if selected == null:
		return
	var cost := 0
	for a in _actions_for(selected):
		if a.id == id:
			cost = a.cost
	# show the pips the action would spend; if unaffordable, the pips show what's missing
	selected.preview_ap(cost if hud.is_action_enabled(id) or selected.ap < cost else 0)


# ---------------------------------------------------------------- move

func _start_move() -> void:
	if selected.ap < selected.next_move_cost():
		return
	hud.close_menu()
	_set_mode(Mode.MOVE)
	selected.preview_ap(selected.next_move_cost())
	var exclude: Array[RID] = [selected.get_rid()]
	grid.refresh_blocked(exclude)
	var origin := grid.world_to_cell(selected.global_position)
	_reach = grid.reachable_from(origin, selected.move_range)
	var cells := _reach.keys()
	cells.erase(origin)
	grid.show_tiles(cells, grid.move_tile_color)
	grid.show_grid_lines(origin, selected.move_range + 1)
	_hover_cell = NO_CELL
	_update_move_hover(get_viewport().get_mouse_position())


func _update_move_hover(pos: Vector2) -> void:
	var p: Variant = _ground_point(pos)
	if p == null:
		return
	var c := grid.world_to_cell(p)
	if c == _hover_cell:
		return
	_hover_cell = c
	var origin := grid.world_to_cell(selected.global_position)
	if c == origin:
		grid.set_hover(c, true)
		grid.show_path([])
	elif _reach.has(c):
		grid.set_hover(c, true)
		grid.show_path(grid.path_to(_reach, c))
	else:
		grid.set_hover(c, false)
		grid.show_path([])
	_set_cursor(_reach.has(c) and c != origin)


func _confirm_move() -> void:
	var origin := grid.world_to_cell(selected.global_position)
	if _hover_cell == origin or _hover_cell == NO_CELL:
		return
	if not _reach.has(_hover_cell):
		hud.toast("Can't reach that square (max %d squares)" % selected.move_range)
		return
	var cells := grid.path_to(_reach, _hover_cell)
	if not selected.spend_move():
		return
	var points: Array[Vector3] = []
	for i in range(1, cells.size()):
		points.append(grid.cell_to_world(cells[i]))
	grid.clear_overlays()
	markers.hide_ring()
	_set_mode(Mode.BUSY)
	selected.preview_ap(0)
	selected.move_along(points)


# ---------------------------------------------------------------- shoot

## Enemies within the selected unit's shoot range (by squares), and those of them with a
## clear line of sight, both sorted closest first.
func _find_targets() -> Dictionary:
	var origin := grid.world_to_cell(selected.global_position)
	var shoot_range: int = selected.get("shoot_range")
	var in_range: Array[Node3D] = []
	for enemy in _enemies():
		if GridBoard.distance(origin, grid.world_to_cell(enemy.global_position)) <= shoot_range:
			in_range.append(enemy)
	in_range.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(selected.global_position) < b.global_position.distance_squared_to(selected.global_position))
	var visible: Array[Node3D] = []
	for enemy in in_range:
		if _has_line_of_sight(selected, enemy):
			visible.append(enemy)
	return {"in_range": in_range, "visible": visible}


## Sweeps a sphere as wide as the fireball (plus a margin, since the real shot leaves from the
## cast point rather than the unit's centre). A thin ray would let shots that only graze a
## rock through, and the fireball would then explode on it.
func _has_line_of_sight(shooter: Unit, enemy: Node3D) -> bool:
	var from := shooter.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	var to: Vector3 = enemy.call("get_aim_point") if enemy.has_method("get_aim_point") else enemy.global_position + Vector3.UP * 0.8
	var shape := SphereShape3D.new()
	shape.radius = LOS_CLEARANCE
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), from)
	q.motion = to - from
	q.collide_with_areas = false
	var exclude: Array[RID] = [shooter.get_rid()]
	if enemy is CollisionObject3D:
		exclude.append((enemy as CollisionObject3D).get_rid())
	q.exclude = exclude
	return shooter.get_world_3d().direct_space_state.cast_motion(q)[0] >= 1.0


func _start_shoot() -> void:
	var cost: int = selected.get("shoot_cost")
	var info := _find_targets()
	if selected.ap < cost or info.visible.is_empty():
		return
	_targets = info.visible
	_target = _targets[0]
	hud.close_menu()
	_set_mode(Mode.SHOOT)
	selected.preview_ap(cost)
	selected.face_toward(_target.global_position)
	var origin := grid.world_to_cell(selected.global_position)
	grid.show_tiles(grid.cells_within(origin, selected.get("shoot_range")), grid.range_tile_color)
	markers.show_reticle(_target)


func _fire() -> void:
	if not is_instance_valid(_target) or not selected.spend_ap(selected.get("shoot_cost")):
		return
	grid.clear_overlays()
	markers.hide_reticle()
	markers.hide_ring()
	_set_mode(Mode.BUSY)
	selected.preview_ap(0)
	var shooter := selected
	var target := _target as Unit
	var result: AttackResult = await combat.attack(shooter, target)
	shooter.call("shoot_at", target, result)


# ---------------------------------------------------------------- melee (knight)

## Living enemies within `radius` cells of the unit (diagonals count as one), closest first.
func _enemies_around(unit: Unit, radius: int) -> Array[Node3D]:
	var origin := grid.world_to_cell(unit.global_position)
	var out: Array[Node3D] = []
	for e in _enemies():
		if GridBoard.distance(origin, grid.world_to_cell(e.global_position)) <= radius:
			out.append(e)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(unit.global_position) < b.global_position.distance_squared_to(unit.global_position))
	return out


func _start_melee() -> void:
	var cost: int = selected.get("melee_cost")
	var near := _enemies_around(selected, 1)
	if selected.ap < cost or near.is_empty():
		return
	_targets = near
	_target = near[0]
	hud.close_menu()
	_set_mode(Mode.MELEE)
	selected.preview_ap(cost)
	selected.face_toward(_target.global_position)
	grid.show_tiles(grid.cells_within(grid.world_to_cell(selected.global_position), 1), grid.range_tile_color)
	markers.show_reticle(_target)


func _fire_melee() -> void:
	if not is_instance_valid(_target) or not selected.spend_ap(selected.get("melee_cost")):
		return
	grid.clear_overlays()
	markers.hide_reticle()
	markers.hide_ring()
	_set_mode(Mode.BUSY)
	selected.preview_ap(0)
	var striker := selected
	var target := _target as Unit
	var result: AttackResult = await combat.attack(striker, target)
	striker.call("melee_attack", target, result)


## Sliced Attack needs no aiming: it hits everything around the knight right away.
func _do_slice() -> void:
	var victims := _enemies_around(selected, selected.get("slice_radius"))
	if victims.is_empty() or not selected.spend_ap(selected.get("slice_cost")):
		return
	hud.close_menu()
	grid.clear_overlays()
	markers.hide_ring()
	_set_mode(Mode.BUSY)
	selected.preview_ap(0)
	selected.call("sliced_attack", victims)


# ---------------------------------------------------------------- special attack

func _start_special() -> void:
	if selected.ap < int(selected.get("special_cost")):
		return
	hud.close_menu()
	_set_mode(Mode.SPECIAL)
	selected.preview_ap(selected.get("special_cost"))
	_blast_key = NO_CELL
	_blast_ok = false
	_update_blast(get_viewport().get_mouse_position())


## Aims the blast square under the cursor. The square snaps to the grid with its centre on
## the cell corner nearest the cursor. It is valid when the cell under the cursor is within
## special_range and the centre is in line of sight.
func _update_blast(pos: Vector2) -> void:
	var p: Variant = _ground_point(pos)
	if p == null:
		return
	var n: int = selected.get("special_area")
	var half := (n - 1) / 2.0
	var lo := Vector2i(roundi(p.x / grid.cell_size - half), roundi(p.z / grid.cell_size - half))
	if lo == _blast_key:
		return
	_blast_key = lo
	_blast_center = Vector3((lo.x + half) * grid.cell_size, 0.0, (lo.y + half) * grid.cell_size)
	_blast_cells.clear()
	for x in n:
		for y in n:
			var c := lo + Vector2i(x, y)
			if grid.in_bounds(c):
				_blast_cells.append(c)
	var origin := grid.world_to_cell(selected.global_position)
	var aim_cell := grid.world_to_cell(p)
	_blast_ok = grid.in_bounds(aim_cell) \
		and GridBoard.distance(origin, aim_cell) <= int(selected.get("special_range")) \
		and _clear_shot_to(selected, _blast_center + Vector3.UP * 0.5)
	grid.show_tiles(grid.cells_within(origin, selected.get("special_range")), grid.range_tile_color)
	grid.add_tiles(_blast_cells, BLAST_COLOR if _blast_ok else grid.invalid_color, 0.03)
	_set_cursor(_blast_ok)


## Line of sight to a point: only scenery blocks (the fireball flies over units).
func _clear_shot_to(shooter: Unit, point: Vector3) -> bool:
	var from := shooter.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	var shape := SphereShape3D.new()
	shape.radius = LOS_CLEARANCE
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), from)
	q.motion = point - from
	q.collide_with_areas = false
	var exclude: Array[RID] = []
	for u in get_tree().get_nodes_in_group(Unit.GROUP_PLAYERS) + get_tree().get_nodes_in_group(Unit.GROUP_ENEMIES):
		if u is CollisionObject3D:
			exclude.append((u as CollisionObject3D).get_rid())
	q.exclude = exclude
	return shooter.get_world_3d().direct_space_state.cast_motion(q)[0] >= 1.0


func _fire_special() -> void:
	if not _blast_ok:
		hud.toast("Out of range or no line of sight")
		return
	if not selected.spend_ap(selected.get("special_cost")):
		return
	var victims: Array = []
	for e in _enemies():
		if _blast_cells.has(grid.world_to_cell(e.global_position)):
			victims.append(e)
	grid.clear_overlays()
	markers.hide_ring()
	_set_mode(Mode.BUSY)
	selected.preview_ap(0)
	selected.call("special_attack", _blast_center, victims)


# ---------------------------------------------------------------- turns

func _on_action_finished(unit: Unit) -> void:
	if mode != Mode.BUSY or unit != selected:
		return
	if selected.ap > 0:
		_open_menu()
	else:
		_close_all()
		hud.toast("%s is out of action points" % selected.display_name)


func _on_ap_changed(points: int, max_points: int, unit: Unit) -> void:
	if unit == selected:
		hud.set_ap(unit.display_name, points, max_points)
	if mode == Mode.MENU:
		_update_menu_state()


func _end_turn() -> void:
	if mode in [Mode.BUSY, Mode.ENEMY_TURN, Mode.GAME_OVER] or (selected and selected.is_busy()):
		return
	_close_all()
	_set_mode(Mode.ENEMY_TURN)
	await hud.turn_banner.play(false, turn)
	if mode == Mode.GAME_OVER:
		return

	var ai := EnemyAI.new(grid, combat)
	for enemy in _enemies():
		if _players().is_empty():
			break
		if not is_instance_valid(enemy) or not enemy.is_alive() or not (enemy is EnemyUnit):
			continue
		_focus_camera_on(enemy)
		await ai.take_turn(enemy as EnemyUnit)
		await get_tree().create_timer(ENEMY_PAUSE).timeout

	var players := _players()
	if players.is_empty():
		_finish_battle(false)
		return
	turn += 1
	hud.set_turn(turn)
	for u in players:
		u.refill_ap()
	if not is_instance_valid(selected) or not selected.is_alive():
		selected = players[0]
	_select(selected)
	_focus_camera_on(selected)
	# still ENEMY_TURN here, so nothing can be clicked or ended while the banner is up
	await hud.turn_banner.play(true, turn)
	if mode == Mode.GAME_OVER:
		return
	_set_mode(Mode.IDLE)


# ---------------------------------------------------------------- end of battle

func _on_enemy_died() -> void:
	if _enemies().is_empty():
		_finish_battle(true)


func _finish_battle(victory: bool) -> void:
	if mode == Mode.GAME_OVER:
		return
	_close_all()
	_set_mode(Mode.GAME_OVER)
	await get_tree().create_timer(END_DELAY).timeout
	hud.visible = false
	for team in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		for u in Unit.living(get_tree(), team):
			u.set_overhead_visible(false)
	grid.clear_overlays()
	markers.hide_ring()
	markers.hide_reticle()
	var subject: Unit = _last_fallen
	var subtitle := ""
	if victory:
		subject = selected if is_instance_valid(selected) and selected.is_alive() else null
		if subject == null and not _players().is_empty():
			subject = _players()[0]
		subtitle = "All enemies defeated in %d turn%s." % [turn, "" if turn == 1 else "s"]
	elif subject:
		subtitle = "%s has fallen." % subject.display_name
	if camera and subject:
		camera.showcase(subject.global_position)
	_end_screen = BattleEndScreen.new()
	add_child(_end_screen)
	_end_screen.retry_pressed.connect(func() -> void: get_tree().reload_current_scene())
	_end_screen.main_menu_pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU))
	_end_screen.next_mission_pressed.connect(func() -> void: pass) # no second mission yet
	_end_screen.show_result(victory, subtitle)


# ---------------------------------------------------------------- per frame

func _process(_delta: float) -> void:
	if mode == Mode.MOVE:
		# the camera can pan/orbit under a still cursor, so re-check the hovered square
		_update_move_hover(get_viewport().get_mouse_position())
	if mode == Mode.SPECIAL:
		_update_blast(get_viewport().get_mouse_position())
	if mode in [Mode.SHOOT, Mode.MELEE] and not is_instance_valid(_target):
		_cancel()
	if hud.is_menu_open():
		if mode == Mode.MENU:
			_update_menu_state()
		var cam := get_viewport().get_camera_3d()
		if cam and selected:
			hud.place_menu(cam.unproject_position(selected.global_position + Vector3(0.0, 1.2, 0.0)))


# ---------------------------------------------------------------- picking

func _pick(screen_pos: Vector2) -> Object:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen_pos) * 200.0)
	var hit := grid.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.get("collider")


func _ground_point(screen_pos: Vector2) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := -from.y / dir.y
	if t <= 0.0:
		return null
	return from + dir * t


## The living player unit under the cursor (its body or the square it stands on), or null.
func _player_unit_at(screen_pos: Vector2) -> Unit:
	var hit := _pick(screen_pos)
	if hit is Unit and (hit as Unit).team == Unit.Team.PLAYER and (hit as Unit).is_alive():
		return hit
	var p: Variant = _ground_point(screen_pos)
	if p == null:
		return null
	var c := grid.world_to_cell(p)
	for u in _players():
		if grid.world_to_cell(u.global_position) == c:
			return u
	return null


func _set_cursor(pointing: bool) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if pointing else Input.CURSOR_ARROW)


func _set_mode(m: Mode) -> void:
	mode = m
	_set_cursor(false)
	# ENEMY_TURN also covers the turn banners, so End Turn is only live on the player's turn
	hud.set_end_turn_enabled(m != Mode.ENEMY_TURN and m != Mode.GAME_OVER)
	match m:
		Mode.IDLE:
			hud.set_help("Click one of your units to choose an action.     Enter: End Turn     Right-drag: move view · Middle-drag: rotate · Wheel: zoom · F: focus")
		Mode.MENU:
			hud.set_help("Choose an action.     Right-click / Esc: deselect")
		Mode.MOVE:
			hud.set_help("Click a highlighted square to move (%d AP).     Right-click / Esc: back" % selected.next_move_cost())
		Mode.SHOOT:
			hud.set_help("Click the target or press Space to cast (%d AP).     Right-click / Esc: back" % selected.get("shoot_cost"))
		Mode.MELEE:
			hud.set_help("Click the target or press Space to strike (%d AP).     Right-click / Esc: back" % selected.get("melee_cost"))
		Mode.SPECIAL:
			hud.set_help("Click the ground (or press Space) to cast the blast (%d AP).     Right-click / Esc: back" % selected.get("special_cost"))
		Mode.BUSY:
			hud.set_help("")
		Mode.ENEMY_TURN:
			hud.set_help("Enemy turn...")
		Mode.GAME_OVER:
			hud.set_help("")
