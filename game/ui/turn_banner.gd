class_name TurnBanner
extends Control
## Turn hand-over card: a semi-transparent band over the top third of the screen with
## "Player's Turn" / "Enemy's Turn" and the turn number. play() fades it in, holds it
## (the board is frozen: clicks are swallowed), fades it out and returns. Lives in the BattleHUD.

const FADE_IN := 0.18
const HOLD := 1.0
const FADE_OUT := 0.25
const PLAYER_COLOR := Color(0.55, 0.88, 1.0)
const ENEMY_COLOR := Color(1.0, 0.45, 0.38)

var _band: ColorRect
var _title: Label
var _subtitle: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# swallow clicks while the banner is up (the freeze); hidden controls ignore input anyway
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_band = ColorRect.new()
	_band.color = Color(0.02, 0.02, 0.06, 0.55)
	_band.anchor_right = 1.0
	_band.anchor_bottom = 1.0 / 3.0
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_band)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(box)

	_title = _label(64, 14)
	_subtitle = _label(38, 10)
	_subtitle.add_theme_color_override("font_color", Color(0.85, 0.82, 0.95))
	box.add_child(_title)
	box.add_child(_subtitle)


## Shows the banner for one side's turn. Awaitable.
func play(player_side: bool, turn: int) -> void:
	_title.text = "Player's Turn" if player_side else "Enemy's Turn"
	_title.add_theme_color_override("font_color", PLAYER_COLOR if player_side else ENEMY_COLOR)
	_subtitle.text = "Turn %d" % turn
	visible = true
	modulate.a = 0.0
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2.ONE * 1.25
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, FADE_IN)
	t.parallel().tween_property(_title, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(HOLD)
	t.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	await t.finished
	visible = false


func _label(font_size: int, outline: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.1, 0.9))
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
