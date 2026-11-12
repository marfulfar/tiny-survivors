extends Node
## Touch screen support (phones / tablets, e.g. the web build in a mobile browser).
## Autoload "TouchControls". Godot's own mouse-from-touch emulation is switched off in the
## project settings (it would click the moment a finger lands, even at the start of a pinch);
## instead this turns gestures into the mouse input the game already understands:
##   * Tap               -> left click (with a hover move first, so paths/targets update).
##   * Long press        -> right click (back / cancel), fired on release.
##   * One-finger drag   -> drag the map.
##   * Two fingers       -> drag the map (midpoint), pinch to zoom, twist to rotate.
## Camera moves go to the active CameraRig; clicks are re-injected with Input.parse_input_event,
## so buttons and the TacticsController receive them like real mouse clicks.

## Viewport pixels a finger may move and still count as a tap.
const TAP_SLOP := 22.0
## Seconds a still finger must be held for a long press (right click).
const LONG_PRESS := 0.5

var _touches := {} # index -> current viewport position
var _start_pos := Vector2.ZERO
var _start_time := 0
## The current single-finger touch is still a candidate for a tap / long press.
var _tap_candidate := false
## A second finger joined at some point; no click is sent until all fingers lift.
var _multi := false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
		get_viewport().set_input_as_handled()


func _on_touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		_touches[t.index] = t.position
		if _touches.size() == 1:
			_multi = false
			_tap_candidate = true
			_start_pos = t.position
			_start_time = Time.get_ticks_msec()
		else:
			_multi = true
			_tap_candidate = false
		return
	_touches.erase(t.index)
	if _touches.is_empty():
		if _tap_candidate and not _multi and t.position.distance_to(_start_pos) <= TAP_SLOP:
			var held := (Time.get_ticks_msec() - _start_time) / 1000.0
			_click(t.position, MOUSE_BUTTON_RIGHT if held >= LONG_PRESS else MOUSE_BUTTON_LEFT)
		_tap_candidate = false
		_multi = false


func _on_drag(d: InputEventScreenDrag) -> void:
	if not _touches.has(d.index):
		return
	var old_pos: Vector2 = _touches[d.index]
	if _touches.size() == 1:
		if _tap_candidate and d.position.distance_to(_start_pos) <= TAP_SLOP:
			_touches[d.index] = d.position
			return # still a tap; don't nudge the map
		if _tap_candidate:
			old_pos = _start_pos # first real drag: catch up with the movement so far
			_tap_candidate = false
		_touches[d.index] = d.position
		var rig := _rig()
		if rig and not _multi:
			rig.drag_view(old_pos, d.position)
		return
	# two (or more) fingers: use the first two
	var keys := _touches.keys()
	var other_index: int = keys[0] if keys[0] != d.index else keys[1]
	if not keys.slice(0, 2).has(d.index):
		_touches[d.index] = d.position
		return
	var other: Vector2 = _touches[other_index]
	_touches[d.index] = d.position
	var rig := _rig()
	if rig == null:
		return
	var before_mid := (old_pos + other) * 0.5
	var after_mid := (d.position + other) * 0.5
	rig.drag_view(before_mid, after_mid)
	var before_span := old_pos.distance_to(other)
	var after_span := d.position.distance_to(other)
	if before_span > 8.0 and after_span > 8.0:
		rig.zoom_by(after_span / before_span)
		var twist := rad_to_deg((d.position - other).angle() - (old_pos - other).angle())
		rig.orbit_by(-wrapf(twist, -180.0, 180.0))


## Sends a hover + press + release at a viewport position, as if the mouse did it.
func _click(pos: Vector2, button: MouseButton) -> void:
	# parse_input_event expects window coordinates; touch positions arrive in viewport ones
	var window_pos := get_viewport().get_final_transform() * pos
	var motion := InputEventMouseMotion.new()
	motion.position = window_pos
	motion.global_position = window_pos
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = button
		mb.pressed = pressed
		mb.position = window_pos
		mb.global_position = window_pos
		mb.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
		Input.parse_input_event(mb)


func _rig() -> CameraRig:
	return get_viewport().get_camera_3d() as CameraRig
