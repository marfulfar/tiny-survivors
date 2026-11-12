class_name MenuStyle
extends RefCounted
## Shared look for full-screen menus (main menu, battle end screen): the dark gradient on
## the left, the big outlined title and the large menu buttons. Change it here and every
## menu follows.

const TITLE_COLOR := Color(1.0, 0.93, 0.7)
const HEADING_COLOR := Color(0.85, 0.8, 1.0)
const BUTTON_WIDTH := 320.0


## Dark gradient down the left side so menu text reads over a 3D backdrop.
static func left_shade(width := 620.0) -> TextureRect:
	var shade := TextureRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = width
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.03, 0.04, 0.08, 0.8), Color(0.03, 0.04, 0.08, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return shade


## The left column that holds a title and the buttons, vertically centred.
static func left_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = 80.0
	column.offset_right = 520.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 40)
	return column


static func title(text: String, color := TITLE_COLOR, size := 72) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.2))
	l.add_theme_constant_override("outline_size", 18)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 6)
	return l


static func heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", HEADING_COLOR)
	return l


static func button_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	return box


static func button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(BUTTON_WIDTH, 58)
	b.add_theme_font_size_override("font_size", 24)
	var states := {
		"normal": Color(0.12, 0.13, 0.22, 0.9),
		"hover": Color(0.26, 0.3, 0.48, 0.95),
		"pressed": Color(0.38, 0.43, 0.65, 1.0),
		"focus": Color(0, 0, 0, 0),
		"disabled": Color(0.1, 0.1, 0.14, 0.7),
	}
	for s: String in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = states[s]
		sb.set_corner_radius_all(10)
		if s == "focus":
			sb.draw_center = false
			sb.border_color = Color(TITLE_COLOR, 0.8)
			sb.set_border_width_all(2)
		else:
			sb.border_color = Color(0.45, 0.4, 0.7, 0.8)
			sb.set_border_width_all(1)
		b.add_theme_stylebox_override(s, sb)
	b.pressed.connect(action)
	return b
