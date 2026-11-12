class_name BattleHUD
extends CanvasLayer
## On-screen battle UI, built in code: turn panel (top-left), the action menu that floats next
## to the selected unit, a help line (bottom) and toast messages (top). Holds no game rules:
## the TacticsController fills it in and reacts to its signals.

signal action_pressed(id: StringName)
## Emitted with the action id when the mouse enters an action button, and &"" when it leaves.
signal action_hovered(id: StringName)
signal end_turn_pressed

const MENU_WIDTH := 230.0
## Lines reserved for the action description, so the menu never changes size on hover
## (a resizing menu moved the buttons out from under the cursor).
const HINT_LINES := 3
const HINT_IDLE := "Hover an action for details."
const ACCENT := Color(0.5, 0.88, 1.0)

var _menu: PanelContainer
var _menu_title: Label
var _menu_buttons: VBoxContainer
var _hint: Label
var _hint_button: Button ## the action whose description the hint shows
var _buttons := {} # id -> Button
var _turn_label: Label
var _end_turn_button: Button
var _ap_label: Label
var _help: Label
var _toast: Label
var _toast_tween: Tween
## Roster of every unit in the battle (right edge). Filled by the TacticsController.
var sidebar: UnitSidebar
## Centre-screen dice duel shown before each single-target attack (CombatResolver presenter).
var duel: DiceDuelOverlay
## "Player's Turn" / "Enemy's Turn" band over the top third, shown when the turn changes.
var turn_banner: TurnBanner


func _ready() -> void:
	_build_menu()
	_build_turn_panel()
	_build_help()
	_build_toast()
	sidebar = UnitSidebar.new()
	add_child(sidebar)
	duel = DiceDuelOverlay.new()
	duel.portrait_source = sidebar.portrait_of
	add_child(duel)
	turn_banner = TurnBanner.new()
	add_child(turn_banner)


# ---------------------------------------------------------------- public API

func set_turn(turn: int) -> void:
	_turn_label.text = "Turn %d" % turn


func set_ap(unit_name: String, points: int, max_points: int) -> void:
	_ap_label.text = "%s  AP: %d / %d" % [unit_name, points, max_points]


## Greys out the End Turn button (enemy turn, banners, end of battle).
func set_end_turn_enabled(enabled: bool) -> void:
	_end_turn_button.disabled = not enabled


func set_help(text: String) -> void:
	_help.text = text


func toast(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


## actions: [{id: StringName, label: String, cost: int, desc: String}, ...]
func open_menu(title: String, actions: Array[Dictionary]) -> void:
	_menu_title.text = title
	for b: Button in _buttons.values():
		_menu_buttons.remove_child(b)
		b.queue_free()
	_buttons.clear()
	for a in actions:
		_buttons[a.id] = _make_action_button(a)
	_clear_hint()
	_menu.visible = true
	_menu.reset_size()


func close_menu() -> void:
	_menu.visible = false


func is_menu_open() -> bool:
	return _menu.visible


## reason == "" enables the action; otherwise it is greyed out and the reason shown on hover.
func set_action_state(id: StringName, reason: String) -> void:
	var btn: Button = _buttons.get(id)
	if btn == null:
		return
	btn.disabled = reason != ""
	btn.set_meta("reason", reason)
	if _hint_button == btn:
		_show_hint(btn)


func is_action_enabled(id: StringName) -> bool:
	var btn: Button = _buttons.get(id)
	return btn != null and not btn.disabled


## Places the menu just right of a screen point (the unit), kept inside the viewport.
func place_menu(anchor: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	var size := _menu.size
	_menu.position = Vector2(
		clampf(anchor.x + 60.0, 8.0, vp.x - size.x - 8.0),
		clampf(anchor.y - size.y * 0.5, 8.0, vp.y - size.y - 8.0))


# ---------------------------------------------------------------- building

func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", _panel_style())
	_menu.visible = false
	add_child(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_menu.add_child(box)
	_menu_title = Label.new()
	_menu_title.add_theme_font_size_override("font_size", 17)
	_menu_title.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))
	box.add_child(_menu_title)
	_menu_buttons = VBoxContainer.new()
	_menu_buttons.add_theme_constant_override("separation", 6)
	box.add_child(_menu_buttons)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.max_lines_visible = HINT_LINES
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var line_h := _hint.get_theme_font("font").get_height(13) + _hint.get_theme_constant("line_spacing")
	_hint.custom_minimum_size = Vector2(MENU_WIDTH, ceilf(line_h * HINT_LINES))
	box.add_child(_hint)


func _build_turn_panel() -> void:
	var hud := PanelContainer.new()
	hud.add_theme_stylebox_override("panel", _panel_style())
	hud.position = Vector2(16.0, 16.0)
	add_child(hud)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	hud.add_child(v)
	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 22)
	v.add_child(_turn_label)
	_ap_label = Label.new()
	_ap_label.add_theme_color_override("font_color", ACCENT)
	v.add_child(_ap_label)
	var end_btn := Button.new()
	end_btn.text = "End Turn  [Enter]"
	end_btn.focus_mode = Control.FOCUS_NONE
	_style_button(end_btn)
	end_btn.pressed.connect(func() -> void: end_turn_pressed.emit())
	v.add_child(end_btn)
	_end_turn_button = end_btn


func _build_help() -> void:
	_help = Label.new()
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_help.offset_top = -40.0
	_help.offset_bottom = -14.0
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_help.add_theme_constant_override("outline_size", 6)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_help)


func _build_toast() -> void:
	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 70.0
	_toast.offset_bottom = 110.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 24)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)


func _make_action_button(a: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = a.label
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(MENU_WIDTH, 36.0)
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta("desc", a.desc)
	btn.set_meta("reason", "")
	_style_button(btn)
	var cost_label := Label.new()
	cost_label.text = "%d AP" % a.cost
	cost_label.add_theme_color_override("font_color", ACCENT)
	cost_label.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	cost_label.offset_left = -60.0
	cost_label.offset_right = -10.0
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(cost_label)
	var id: StringName = a.id
	btn.pressed.connect(func() -> void: action_pressed.emit(id))
	btn.mouse_entered.connect(func() -> void:
		_show_hint(btn)
		action_hovered.emit(id))
	btn.mouse_exited.connect(func() -> void:
		if _hint_button == btn:
			_clear_hint()
		action_hovered.emit(&""))
	# dim the cost when the button is disabled
	btn.draw.connect(func() -> void:
		cost_label.modulate.a = 0.4 if btn.disabled else 1.0)
	_menu_buttons.add_child(btn)
	return btn


func _show_hint(btn: Button) -> void:
	_hint_button = btn
	if btn.disabled:
		_hint.text = btn.get_meta("reason")
		_hint.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	else:
		_hint.text = btn.get_meta("desc")
		_hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))


func _clear_hint() -> void:
	_hint_button = null
	_hint.text = HINT_IDLE
	_hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85, 0.45))


func _style_button(btn: Button) -> void:
	var states := {
		"normal": Color(0.2, 0.22, 0.32, 0.95),
		"hover": Color(0.3, 0.34, 0.5, 1.0),
		"pressed": Color(0.4, 0.45, 0.65, 1.0),
		"disabled": Color(0.16, 0.16, 0.2, 0.8),
	}
	for state: String in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = states[state]
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 12.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 6.0
		sb.content_margin_bottom = 6.0
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55))


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.13, 0.88)
	sb.set_corner_radius_all(8)
	sb.border_color = Color(0.45, 0.4, 0.7, 0.8)
	sb.set_border_width_all(1)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb
