class_name D20Die
extends Control
## A d20 drawn flat (icosahedron silhouette: a hexagon with the front triangle face) with
## the face value in the middle. roll_to() tumbles it through random faces, slowing down,
## and lands on the given value. Placeholder look; swap for a 3D die later without changing
## the overlay's calls (roll_to / reset / set_outcome).

const FILL := Color(0.2, 0.17, 0.32)
const EDGE := Color(0.85, 0.8, 1.0)
const TEXT := Color(1.0, 0.97, 0.88)
const WIN_FILL := Color(0.62, 0.45, 0.12)
const WIN_EDGE := Color(1.0, 0.86, 0.45)
const LOSE_FILL := Color(0.14, 0.14, 0.18)
const LOSE_EDGE := Color(0.45, 0.45, 0.52)

var sides := Dice.D20

var _face := "?"
var _fill := FILL
var _edge := EDGE
var _shake := Vector2.ZERO


func _init() -> void:
	custom_minimum_size = Vector2(120.0, 120.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(func() -> void: pivot_offset = size * 0.5)


## Back to a blank, neutral die.
func reset() -> void:
	_face = "?"
	_fill = FILL
	_edge = EDGE
	rotation = 0.0
	scale = Vector2.ONE
	queue_redraw()


## Tumbles for about `duration` seconds and lands on `value`. Awaitable.
func roll_to(value: int, duration := 1.0) -> void:
	var elapsed := 0.0
	var step := 0.035
	while elapsed < duration:
		var left := 1.0 - elapsed / duration
		# visual only: the global RNG, never Dice (that would change the real rolls)
		_face = str(randi_range(1, sides))
		rotation = randf_range(-0.6, 0.6) * left
		position_offset(Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)) * left)
		queue_redraw()
		await get_tree().create_timer(step).timeout
		elapsed += step
		step *= 1.13
	rotation = 0.0
	position_offset(Vector2.ZERO)
	_face = str(value)
	queue_redraw()
	scale = Vector2.ONE * 1.3
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished


## Gold for the winning roll, grey for the losing one.
func set_outcome(won: bool) -> void:
	_fill = WIN_FILL if won else LOSE_FILL
	_edge = WIN_EDGE if won else LOSE_EDGE
	queue_redraw()


## Jitters the drawing (not the Control, so the container layout stays put).
func position_offset(offset: Vector2) -> void:
	_shake = offset
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5 + _shake
	var r := minf(size.x, size.y) * 0.46
	var hex := PackedVector2Array()
	for i in 6:
		var a := -PI / 2.0 + i * TAU / 6.0
		hex.append(c + Vector2(cos(a), sin(a)) * r)
	var tri := PackedVector2Array()
	for a_deg in [-90.0, 30.0, 150.0]:
		var a := deg_to_rad(a_deg)
		tri.append(c + Vector2(cos(a), sin(a)) * r * 0.6)

	draw_colored_polygon(hex, _fill)
	draw_colored_polygon(tri, _fill.lightened(0.18))
	# facet lines from the front face out to the rim (hex: 0 top, then clockwise)
	var w := 2.0
	var facet := Color(_edge, 0.55)
	for pair in [[0, 0], [0, 1], [0, 5], [1, 1], [1, 2], [1, 3], [2, 3], [2, 4], [2, 5]]:
		draw_line(tri[pair[0]], hex[pair[1]], facet, w, true)
	var hex_closed := hex.duplicate()
	hex_closed.append(hex[0])
	draw_polyline(hex_closed, _edge, 3.0, true)
	var tri_closed := tri.duplicate()
	tri_closed.append(tri[0])
	draw_polyline(tri_closed, _edge, 2.0, true)

	var font := get_theme_default_font()
	var fs := int(r * 0.52)
	var ts := font.get_string_size(_face, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var baseline := c.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5 + r * 0.06
	draw_string_outline(font, Vector2(c.x - ts.x * 0.5, baseline), _face, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.05, 0.03, 0.1))
	draw_string(font, Vector2(c.x - ts.x * 0.5, baseline), _face, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT)
