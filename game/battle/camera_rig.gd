class_name CameraRig
extends Camera3D
## Tactics camera orbiting a free focus point on the ground.
##  * Right-mouse drag: grab the ground and drag the view (a quick right-click is left
##    to the game, e.g. cancel).  Shift + middle-drag does the same.
##  * Middle-mouse drag: orbit (left/right rotates, up/down tilts), like the Godot editor.
##  * Mouse wheel: zoom.   F: re-centre on the target.   WASD / arrows: pan.
## While the target is walking the camera follows it. focus_on_target(true) glides over to it.

@export var target_path: NodePath

@export_group("Angles")
@export_range(15.0, 85.0) var pitch_degrees := 55.0
@export var yaw_degrees := 0.0
@export var min_pitch := 15.0
@export var max_pitch := 85.0
@export var orbit_sensitivity := 0.3 ## degrees per pixel dragged

@export_group("Zoom")
@export var distance := 10.0
@export var min_distance := 4.0
@export var max_distance := 22.0
@export var zoom_step := 1.2

@export_group("Panning")
@export var key_pan_speed := 0.8 ## multiplied by the zoom distance, metres per second
@export var bounds := 19.0 ## the focus stays within +-bounds on X and Z
@export var follow_speed := 6.0
## Pixels a right-button press may move and still count as a click rather than a drag.
@export var drag_threshold := 6.0

var focus := Vector3.ZERO

## The unit the camera follows while it walks. The battle controller points this at the
## selected unit, and at each enemy while it acts.
var target: Node3D
var _zoom := 10.0
var _orbiting := false
var _grab_panning := false
var _right_down := false
var _right_moved := 0.0
var _right_was_drag := false
## True while gliding to the target; any manual pan cancels it.
var _gliding := false
## Where the glide is heading; null = the target.
var _glide_point: Variant = null
## Showcase mode (battle end screen): slow automatic orbit, player controls off.
var _showcase := false
var _showcase_pitch := 28.0
var _showcase_speed := 6.0


func _ready() -> void:
	if not target_path.is_empty():
		target = get_node_or_null(target_path) as Node3D
	_zoom = distance
	current = true
	if target:
		focus = _ground(target.global_position)
	_apply_transform()


func _process(delta: float) -> void:
	distance = lerpf(distance, _zoom, 1.0 - exp(-10.0 * delta))
	if _showcase:
		yaw_degrees = wrapf(yaw_degrees + _showcase_speed * delta, -180.0, 180.0)
		pitch_degrees = lerpf(pitch_degrees, _showcase_pitch, 1.0 - exp(-2.0 * delta))
		h_offset = lerpf(h_offset, -2.2, 1.0 - exp(-2.0 * delta))
	if _target_is_walking():
		_gliding = false
		focus = focus.lerp(_ground(target.global_position), 1.0 - exp(-follow_speed * delta))
	elif not (_orbiting or _grab_panning or _right_down):
		var dir := Vector2.ZERO if _showcase else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if dir != Vector2.ZERO:
			_gliding = false
			_pan_screen(dir * key_pan_speed * distance * delta)
		elif _gliding:
			if _glide_point == null and (target == null or not is_instance_valid(target)):
				_gliding = false
			else:
				var goal: Vector3 = _glide_point if _glide_point != null else _ground(target.global_position)
				focus = focus.lerp(goal, 1.0 - exp(-follow_speed * delta))
				if focus.distance_to(goal) < 0.02:
					focus = goal
					_gliding = false
	_apply_transform()


## True if the last right-button press turned into a drag (so it should not count as a click).
func right_click_was_drag() -> bool:
	return _right_was_drag


## Re-centre on the target (also bound to F). With smooth = true the camera glides there.
func focus_on_target(smooth := false) -> void:
	if target == null or not is_instance_valid(target):
		return
	_glide_point = null
	if smooth:
		_gliding = true
	else:
		_gliding = false
		focus = _ground(target.global_position)


## Slowly circles a point, low and close, with player camera controls disabled. Used behind
## the battle end screen. The subject sits right of centre to leave room for the menu.
func showcase(point: Vector3, zoom := 6.0, pitch := 28.0, degrees_per_second := 6.0) -> void:
	_showcase = true
	_orbiting = false
	_grab_panning = false
	_right_down = false
	target = null
	_zoom = zoom
	_showcase_pitch = pitch
	_showcase_speed = degrees_per_second
	glide_to(point)


## Glides to look at a world point without changing the target.
func glide_to(point: Vector3) -> void:
	var p := _ground(point)
	p.x = clampf(p.x, -bounds, bounds)
	p.z = clampf(p.z, -bounds, bounds)
	_glide_point = p
	_gliding = true


func _input(event: InputEvent) -> void:
	if _showcase:
		return
	# Right button is tracked in _input so drags work even when they start over UI-free space
	# and the game still receives the click; we only decide whether it was a drag.
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_right_down = true
			_right_moved = 0.0
			_right_was_drag = false
		else:
			_right_down = false
			_right_was_drag = _right_moved > drag_threshold
	elif event is InputEventMouseMotion and _right_down:
		var mm := event as InputEventMouseMotion
		_right_moved += mm.relative.length()
		if _right_moved > drag_threshold:
			_grab(mm)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_orbiting = false
		_grab_panning = false
		_right_down = false


func _unhandled_input(event: InputEvent) -> void:
	if _showcase:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom = clampf(_zoom - zoom_step, min_distance, max_distance)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom = clampf(_zoom + zoom_step, min_distance, max_distance)
			MOUSE_BUTTON_MIDDLE:
				_grab_panning = mb.pressed and mb.shift_pressed
				_orbiting = mb.pressed and not mb.shift_pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			yaw_degrees = wrapf(yaw_degrees - mm.relative.x * orbit_sensitivity, -180.0, 180.0)
			pitch_degrees = clampf(pitch_degrees + mm.relative.y * orbit_sensitivity, min_pitch, max_pitch)
		elif _grab_panning:
			_grab(mm)
	elif event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F:
			focus_on_target()


# ---------------------------------------------------------------- touch (TouchControls)

## Drags the view so the ground point under `from_pos` ends up under `to_pos` (viewport px).
func drag_view(from_pos: Vector2, to_pos: Vector2) -> void:
	if _showcase:
		return
	_drag_ground(from_pos, to_pos)


## Pinch zoom: factor > 1 moves closer (fingers spreading apart).
func zoom_by(factor: float) -> void:
	if _showcase or factor <= 0.0:
		return
	_zoom = clampf(_zoom / factor, min_distance, max_distance)
	distance = _zoom # follow the fingers directly, no easing


## Two-finger twist / tilt, in degrees.
func orbit_by(yaw_delta: float, pitch_delta := 0.0) -> void:
	if _showcase:
		return
	yaw_degrees = wrapf(yaw_degrees + yaw_delta, -180.0, 180.0)
	pitch_degrees = clampf(pitch_degrees + pitch_delta, min_pitch, max_pitch)
	_apply_transform()


## Grab-and-drag: moves the focus so the ground point under the cursor stays under it.
func _grab(mm: InputEventMouseMotion) -> void:
	_drag_ground(mm.position - mm.relative, mm.position)


func _drag_ground(from_pos: Vector2, to_pos: Vector2) -> void:
	var before: Variant = _ground_under(from_pos)
	var after: Variant = _ground_under(to_pos)
	if before == null or after == null:
		return
	_gliding = false
	focus += (before as Vector3) - (after as Vector3)
	_clamp_focus()
	_apply_transform()


func _ground_under(screen_pos: Vector2) -> Variant:
	var from := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	if dir.y > -0.01:
		return null # ray doesn't hit the ground (cursor above the horizon)
	return from + dir * (-from.y / dir.y)


func _apply_transform() -> void:
	var pitch := deg_to_rad(pitch_degrees)
	var yaw := deg_to_rad(yaw_degrees)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	global_position = focus + offset
	look_at(focus + Vector3(0.0, 0.4, 0.0))


## Pans by `amount` metres in screen terms (x = right, y = down the screen).
func _pan_screen(amount: Vector2) -> void:
	var yaw := deg_to_rad(yaw_degrees)
	focus += Vector3(cos(yaw), 0.0, -sin(yaw)) * amount.x + Vector3(sin(yaw), 0.0, cos(yaw)) * amount.y
	_clamp_focus()


func _clamp_focus() -> void:
	focus.x = clampf(focus.x, -bounds, bounds)
	focus.z = clampf(focus.z, -bounds, bounds)


func _target_is_walking() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is Unit:
		return (target as Unit).is_walking()
	if not (target is CharacterBody3D):
		return false
	var v := (target as CharacterBody3D).velocity
	return Vector2(v.x, v.z).length() > 0.05


static func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)
