class_name BattleEndScreen
extends CanvasLayer
## Full-screen result shown when a battle ends, in the main menu's style (MenuStyle).
## Defeat: "Defeat!" + Try Again / Main Menu. Victory: "Victory!" + Next Mission / Try Again /
## Main Menu. Emits a signal per button; the TacticsController decides what each one does.

signal retry_pressed
signal main_menu_pressed
signal next_mission_pressed

const DEFEAT_COLOR := Color(1.0, 0.45, 0.4)
const VICTORY_COLOR := Color(1.0, 0.85, 0.35)

var _root: Control


func _init() -> void:
	layer = 10 # above the battle HUD


func show_result(victory: bool, subtitle := "") -> void:
	if _root:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_root.add_child(MenuStyle.left_shade())
	var column := MenuStyle.left_column()
	_root.add_child(column)

	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.add_child(MenuStyle.title("Victory!" if victory else "Defeat!",
			VICTORY_COLOR if victory else DEFEAT_COLOR, 84))
	if subtitle != "":
		var sub := Label.new()
		sub.text = subtitle
		sub.add_theme_font_size_override("font_size", 22)
		sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		sub.add_theme_constant_override("outline_size", 6)
		head.add_child(sub)
	column.add_child(head)

	var buttons := MenuStyle.button_box()
	column.add_child(buttons)
	var first: Button
	if victory:
		first = MenuStyle.button("Next Mission", func() -> void: next_mission_pressed.emit())
		first.tooltip_text = "Coming soon"
		buttons.add_child(first)
	var retry := MenuStyle.button("Try Again This Mission", func() -> void: retry_pressed.emit())
	buttons.add_child(retry)
	buttons.add_child(MenuStyle.button("Main Menu", func() -> void: main_menu_pressed.emit()))
	(first if first else retry).grab_focus.call_deferred()

	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.8)
