class_name DiceDuelOverlay
extends Control
## Centre-screen panel that replays an AttackResult: attacker portrait on the left, defender
## on the right (the same snapshots as the sidebar cards), a d20 under each. For every check
## in the result both dice tumble and land (attacker first), the higher total turns gold and
## the verdict appears ("HIT!" / "MISS"); on a hit the damage sum follows
## ((attacker d20 + Strength) - (defender d20 + Armour)). Then the panel fades and play() returns, so the
## caller can start the attack animation. Lives in the BattleHUD; holds no rules.

const PORTRAIT := 150.0
const ROLL_TIME := 0.9
## Extra tumbling for the defender's die, so the two land one after the other.
const SECOND_DIE_DELAY := 0.35
const VERDICT_HOLD := 1.0
const FADE := 0.15
const HIT_COLOR := Color(1.0, 0.86, 0.4)
const MISS_COLOR := Color(0.7, 0.8, 1.0)
const DAMAGE_COLOR := Color(1.0, 0.4, 0.32)
## Verdict colour for a natural 20.
const CRIT_COLOR := Color(1.0, 0.55, 0.15)
## How long the damage line stays up after a hit.
const DAMAGE_HOLD := 1.2

## Returns a unit's portrait texture (or null). Set by the HUD to the sidebar's cache.
var portrait_source: Callable

var _panel: PanelContainer
var _title: Label
var _verdict: Label
var _damage_label: Label
var _sides := [] # [attacker, defender]: {name, role, portrait, die, total}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.13, 0.94)
	sb.set_corner_radius_all(12)
	sb.border_color = Color(0.45, 0.4, 0.7, 0.9)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(24.0)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)

	_title = _label("To hit", 26, Color(0.85, 0.8, 1.0))
	column.add_child(_title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 36)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)

	var a := _make_side("Attack")
	var vs := _label("VS", 34, Color(0.75, 0.7, 0.9))
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var d := _make_side("Defense")
	row.add_child(a.root)
	row.add_child(vs)
	row.add_child(d.root)
	_sides = [a, d]

	_verdict = _label("", 48, HIT_COLOR)
	_verdict.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.2))
	_verdict.add_theme_constant_override("outline_size", 12)
	_verdict.custom_minimum_size = Vector2(0.0, 64.0)
	column.add_child(_verdict)

	_damage_label = _label("", 30, DAMAGE_COLOR)
	_damage_label.add_theme_color_override("font_outline_color", Color(0.15, 0.02, 0.02))
	_damage_label.add_theme_constant_override("outline_size", 10)
	_damage_label.custom_minimum_size = Vector2(0.0, 44.0)
	column.add_child(_damage_label)


## Shows every roll in `result`, then hides again. Awaitable.
func play(result: AttackResult) -> void:
	_fill_side(_sides[0], result.attacker)
	_fill_side(_sides[1], result.defender)
	_damage_label.text = ""
	_panel.pivot_offset = _panel.size * 0.5
	visible = true
	modulate.a = 0.0
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, FADE)
	await t.finished
	for check in result.checks:
		await _play_check(check)
	if result.hit:
		await _show_damage(result)
	t = create_tween()
	t.tween_property(self, "modulate:a", 0.0, FADE)
	await t.finished
	visible = false


func _play_check(check: OpposedRoll) -> void:
	_title.text = check.label
	_verdict.text = ""
	for s in _sides:
		(s.die as D20Die).sides = check.sides
		(s.die as D20Die).reset()
		(s.total as Label).text = " "
	var a_die: D20Die = _sides[0].die
	var d_die: D20Die = _sides[1].die
	# both tumble at once; the defender's lands a beat later
	a_die.roll_to(check.attacker_roll, ROLL_TIME)
	await d_die.roll_to(check.defender_roll, ROLL_TIME + SECOND_DIE_DELAY)
	_sides[0].total.text = _total_text(check.attacker_roll, check.attacker_bonus)
	_sides[1].total.text = _total_text(check.defender_roll, check.defender_bonus)
	var won := check.attacker_wins()
	a_die.set_outcome(won)
	d_die.set_outcome(not won)
	_verdict.text = check.verdict_text()
	if check.is_tie():
		_verdict.text += "  (tie)"
	var crit := check.is_critical()
	_verdict.add_theme_color_override("font_color",
		CRIT_COLOR if crit else (HIT_COLOR if won else MISS_COLOR))
	_verdict.pivot_offset = _verdict.size * 0.5
	_verdict.scale = Vector2.ONE * (1.8 if crit else 1.4)
	var t := create_tween()
	t.tween_property(_verdict, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(VERDICT_HOLD).timeout


## Under each die its total ("15 + 4 STR = 19" / "10 + 1 ARM = 11"), then the damage line
## ("19 - 11 = 8 damage") under the verdict, popping in like it.
func _show_damage(result: AttackResult) -> void:
	_sides[0].total.text = "%d %+d STR = %d" % [result.damage_roll, result.strength, result.attack_total()]
	if result.critical:
		_sides[1].total.text = "%d  (ARM ignored) = %d" % [result.defense_roll, result.defense_total()]
	else:
		_sides[1].total.text = "%d %+d ARM = %d" % [result.defense_roll, result.armour, result.defense_total()]
	await get_tree().create_timer(0.35).timeout
	_damage_label.text = "%d - %d = %s" % [result.attack_total(), result.defense_total(),
		"%d damage" % result.damage if result.damage > 0 else "0  -  Blocked!"]
	_damage_label.add_theme_color_override("font_color", DAMAGE_COLOR if result.damage > 0 else MISS_COLOR)
	_damage_label.pivot_offset = _damage_label.size * 0.5
	_damage_label.scale = Vector2.ONE * 1.4
	var t := create_tween()
	t.tween_property(_damage_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(DAMAGE_HOLD).timeout


func _total_text(roll: int, bonus: int) -> String:
	if bonus == 0:
		return "Total %d" % roll
	return "%d %s %d = %d" % [roll, "+" if bonus > 0 else "-", absi(bonus), roll + bonus]


func _fill_side(side: Dictionary, unit: Unit) -> void:
	var alive := is_instance_valid(unit)
	(side.name as Label).text = unit.display_name if alive else "?"
	(side.stats as Label).text = "STR %+d   ARM %+d   HP %d/%d" % [unit.strength, unit.armour,
		unit.health, unit.max_health] if alive else ""
	var tex: Texture2D = null
	if alive and portrait_source.is_valid():
		tex = portrait_source.call(unit)
	(side.portrait as TextureRect).texture = tex
	(side.die as D20Die).reset()
	(side.total as Label).text = " "


func _make_side(role: String) -> Dictionary:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var role_label := _label(role, 15, Color(0.6, 0.58, 0.75))
	var name_label := _label("", 22, Color(1.0, 0.95, 0.85))
	var stats_label := _label("", 14, Color(0.75, 0.85, 1.0))

	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color(0.05, 0.06, 0.1, 1.0)
	backdrop.set_corner_radius_all(8)
	backdrop.border_color = Color(0.45, 0.4, 0.7, 0.6)
	backdrop.set_border_width_all(1)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", backdrop)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(portrait)

	var die := D20Die.new()
	die.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var total := _label(" ", 18, Color(0.9, 0.88, 1.0))

	for n in [role_label, name_label, stats_label, frame, die, total]:
		v.add_child(n)
	return {root = v, name = name_label, stats = stats_label, portrait = portrait, die = die, total = total}


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
