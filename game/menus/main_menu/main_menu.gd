extends Node3D
## Title screen: the forest clearing as a live backdrop (camera slowly circling the heroes),
## the game title, and Start Game / Settings / Exit. Settings holds the music toggle
## (GameSettings autoload). Start Game loads FIRST_MISSION.

const FIRST_MISSION := "res://game/missions/forest_clearing/forest_clearing.tscn"
const TITLE := "Tiny Survivors"

@export var orbit_speed := 0.06 ## radians per second
@export var orbit_radius := 8.5
@export var orbit_height := 3.6
@export var look_target := Vector3(0.4, 1.0, -0.3)

@onready var camera: Camera3D = $Camera

var _angle := 0.6
var _main_panel: Control
var _settings_panel: Control
var _music_toggle: CheckButton
var _fade: ColorRect


func _ready() -> void:
	camera.h_offset = -2.6 # heroes sit right of centre, menu on the left
	_build_ui()
	_place_camera()


func _process(delta: float) -> void:
	_angle += orbit_speed * delta
	_place_camera()


func _place_camera() -> void:
	camera.global_position = look_target + Vector3(sin(_angle) * orbit_radius, orbit_height, cos(_angle) * orbit_radius)
	camera.look_at(look_target)


# ---------------------------------------------------------------- actions

func _on_start() -> void:
	_set_buttons_disabled(true)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.4)
	await t.finished
	get_tree().change_scene_to_file(FIRST_MISSION)


func _show_settings(open: bool) -> void:
	_main_panel.visible = not open
	_settings_panel.visible = open


func _on_exit() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _settings_panel.visible:
		_show_settings(false)


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	layer.add_child(MenuStyle.left_shade())
	var column := MenuStyle.left_column()
	layer.add_child(column)
	column.add_child(MenuStyle.title(TITLE))

	var panels := Control.new()
	panels.custom_minimum_size = Vector2(320, 230)
	column.add_child(panels)

	_main_panel = _menu_box(panels)
	_menu_button(_main_panel, "Start Game", _on_start).grab_focus.call_deferred()
	_menu_button(_main_panel, "Settings", _show_settings.bind(true))
	_menu_button(_main_panel, "Exit", _on_exit)

	_settings_panel = _menu_box(panels)
	_settings_panel.add_child(MenuStyle.heading("Settings"))
	_music_toggle = CheckButton.new()
	_music_toggle.text = "Music"
	_music_toggle.add_theme_font_size_override("font_size", 22)
	_music_toggle.button_pressed = GameSettings.music_enabled
	_music_toggle.toggled.connect(func(on: bool) -> void: GameSettings.music_enabled = on)
	_settings_panel.add_child(_music_toggle)
	_menu_button(_settings_panel, "Back", _show_settings.bind(false))
	_settings_panel.visible = false

	var version := Label.new()
	version.text = "v0.1"
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -80.0
	version.offset_top = -36.0
	version.modulate.a = 0.6
	layer.add_child(version)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


func _menu_box(parent: Control) -> VBoxContainer:
	var box := MenuStyle.button_box()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(box)
	return box


func _menu_button(parent: Control, text: String, action: Callable) -> Button:
	var b := MenuStyle.button(text, action)
	parent.add_child(b)
	return b


func _set_buttons_disabled(disabled: bool) -> void:
	for b in _main_panel.get_children():
		if b is Button:
			(b as Button).disabled = disabled
