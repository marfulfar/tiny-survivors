class_name UnitSidebar
extends PanelContainer
## Roster panel pinned to the right edge, vertically centred: a "Characters" section with every
## player unit and an "Enemies" section with every enemy in the mission. Each card shows a
## portrait snapshot (PortraitRenderer), the name, a red health bar and AP pips, kept live
## through the unit's health_changed / ap_changed / died signals. Dead units stay, greyed out.
## Clicking a card emits unit_clicked; the TacticsController decides what that does.

signal unit_clicked(unit: Unit)

const PORTRAIT := 84.0
const CARD_WIDTH := 112.0
const HEALTH_COLOR := Color(0.9, 0.12, 0.12)
const HEALTH_BG := Color(0.08, 0.05, 0.05, 0.85)
const AP_COLOR := Color(0.35, 0.85, 1.0)
const AP_EMPTY := Color(0.1, 0.12, 0.18, 0.9)
const SELECTED_BORDER := Color(0.5, 0.88, 1.0)

var _cards := {} # Unit -> Dictionary of the card's parts
var _list: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.13, 0.88)
	sb.set_corner_radius_all(8)
	sb.border_color = Color(0.45, 0.4, 0.7, 0.8)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10.0)
	add_theme_stylebox_override("panel", sb)
	# right edge, centred vertically (anchors/offsets set in _fit)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)
	get_viewport().size_changed.connect(_fit)


## Builds the cards. Portraits fill in a moment later (they render asynchronously).
func setup(players: Array[Unit], enemies: Array[Unit]) -> void:
	for c in _list.get_children():
		c.queue_free()
	_cards.clear()
	_add_section("Characters", players)
	_add_section("Enemies", enemies)
	_fit.call_deferred()
	for u in players + enemies:
		_load_portrait(u)


## The unit's portrait snapshot, or null if it has no card or it is still rendering.
func portrait_of(unit: Unit) -> Texture2D:
	if not _cards.has(unit):
		return null
	return (_cards[unit].portrait as TextureRect).texture


## Outlines the card of the selected unit (null clears it).
func set_selected(unit: Unit) -> void:
	for key in _cards.keys():
		if not is_instance_valid(key):
			continue # unit was freed (e.g. a dead enemy removed from the board)
		var u := key as Unit
		var frame: PanelContainer = _cards[key].frame
		var style := frame.get_theme_stylebox("panel") as StyleBoxFlat
		style.border_color = SELECTED_BORDER if u == unit else Color(0, 0, 0, 0)


# ---------------------------------------------------------------- building

func _add_section(title: String, units: Array[Unit]) -> void:
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))
	_list.add_child(label)
	if units.is_empty():
		var none := Label.new()
		none.text = "None"
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.modulate.a = 0.5
		_list.add_child(none)
	for u in units:
		_list.add_child(_make_card(u))


func _make_card(unit: Unit) -> Control:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.22, 0.95)
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = Color(0, 0, 0, 0)
	style.set_content_margin_all(6.0)
	frame.add_theme_stylebox_override("panel", style)
	frame.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame.tooltip_text = "%s - click to focus" % unit.display_name
	frame.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			unit_clicked.emit(unit))
	frame.mouse_entered.connect(func() -> void: style.bg_color = Color(0.2, 0.22, 0.34, 1.0))
	frame.mouse_exited.connect(func() -> void: style.bg_color = Color(0.13, 0.14, 0.22, 0.95))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(v)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color(0.05, 0.06, 0.1, 1.0)
	backdrop.set_corner_radius_all(4)
	var portrait_bg := PanelContainer.new()
	portrait_bg.add_theme_stylebox_override("panel", backdrop)
	portrait_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_bg.add_child(portrait)
	v.add_child(portrait_bg)

	var name_label := Label.new()
	name_label.text = unit.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_label)

	# health bar: dark track with a red fill anchored left
	var track := Panel.new()
	track.custom_minimum_size = Vector2(0.0, 9.0)
	track.add_theme_stylebox_override("panel", _flat(HEALTH_BG, 2))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := Panel.new()
	fill.add_theme_stylebox_override("panel", _flat(HEALTH_COLOR, 2))
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_bottom = 1.0
	fill.offset_left = 1.5
	fill.offset_top = 1.5
	fill.offset_bottom = -1.5
	track.add_child(fill)
	v.add_child(track)

	# AP row: "AP" + one pip per max AP, like the pips over the unit
	var ap_row := HBoxContainer.new()
	ap_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ap_row.add_theme_constant_override("separation", 4)
	ap_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ap_label := Label.new()
	ap_label.text = "AP"
	ap_label.add_theme_font_size_override("font_size", 12)
	ap_label.add_theme_color_override("font_color", AP_COLOR)
	ap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ap_row.add_child(ap_label)
	v.add_child(ap_row)

	var parts := {frame = frame, portrait = portrait, track = track, fill = fill,
			ap_row = ap_row, pips = []}
	_cards[unit] = parts
	unit.health_changed.connect(func(_h: int, _m: int) -> void: _refresh_health(unit))
	unit.ap_changed.connect(func(p: int, m: int) -> void: _refresh_ap(unit, p, m))
	unit.died.connect(func() -> void: _mark_dead(unit))
	track.resized.connect(func() -> void: _refresh_health(unit))
	_refresh_ap(unit, unit.ap, unit.max_ap)
	if not unit.is_alive():
		_mark_dead(unit)
	return frame


func _load_portrait(unit: Unit) -> void:
	var tex := await PortraitRenderer.capture(unit)
	if tex and _cards.has(unit):
		(_cards[unit].portrait as TextureRect).texture = tex


# ---------------------------------------------------------------- live updates

func _refresh_health(unit: Unit) -> void:
	if not _cards.has(unit):
		return
	var parts: Dictionary = _cards[unit]
	var track: Panel = parts.track
	var fill: Panel = parts.fill
	var ratio := 0.0
	if is_instance_valid(unit) and unit.max_health > 0:
		ratio = clampf(float(unit.health) / unit.max_health, 0.0, 1.0)
	var inner := track.size.x - 3.0
	fill.visible = ratio > 0.0
	fill.offset_right = 1.5 + inner * ratio
	fill.anchor_right = 0.0


func _refresh_ap(unit: Unit, points: int, max_points: int) -> void:
	var parts: Dictionary = _cards.get(unit, {})
	if parts.is_empty():
		return
	var pips: Array = parts.pips
	var row: HBoxContainer = parts.ap_row
	while pips.size() < max_points:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(11.0, 11.0)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)
		pips.append(pip)
	while pips.size() > max_points:
		(pips.pop_back() as Node).queue_free()
	for i in pips.size():
		var sb := _flat(AP_COLOR if i < points else AP_EMPTY, 6)
		if i >= points: # spent: dark with a faint ring so the max is still readable
			sb.border_color = Color(AP_COLOR, 0.45)
			sb.set_border_width_all(1)
		(pips[i] as Panel).add_theme_stylebox_override("panel", sb)


func _mark_dead(unit: Unit) -> void:
	var parts: Dictionary = _cards.get(unit, {})
	if parts.is_empty():
		return
	var frame: PanelContainer = parts.frame
	frame.modulate = Color(0.55, 0.55, 0.55, 0.65)
	(parts.portrait as TextureRect).self_modulate = Color(0.6, 0.6, 0.6)
	frame.tooltip_text = "%s (defeated)" % unit.display_name
	frame.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_refresh_health(unit)
	_refresh_ap(unit, 0, unit.max_ap)


# ---------------------------------------------------------------- layout

## Caps the panel to the screen height (it scrolls beyond that) and re-centres it.
func _fit() -> void:
	var vp := get_viewport().get_visible_rect().size
	var wanted := _list.get_combined_minimum_size()
	_scroll.custom_minimum_size = Vector2(wanted.x, minf(wanted.y, vp.y - 120.0))
	var s := get_combined_minimum_size()
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_right = -16.0
	offset_left = offset_right - s.x
	offset_top = -s.y * 0.5
	offset_bottom = s.y * 0.5


static func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb
