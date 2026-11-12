extends Node
## Autoload "GameSettings": player options, saved to user://settings.cfg.
## Music plays through the "Music" audio bus (created here if the project has none), so any
## future music player just sets bus = &"Music" and obeys the toggle automatically.

signal changed

const PATH := "user://settings.cfg"
const MUSIC_BUS := &"Music"

var music_enabled := true:
	set(value):
		music_enabled = value
		_apply()
		save()
		changed.emit()


func _ready() -> void:
	if AudioServer.get_bus_index(MUSIC_BUS) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, MUSIC_BUS)
		AudioServer.set_bus_send(i, &"Master")
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		music_enabled = cfg.get_value("audio", "music_enabled", true)
	_apply()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_enabled", music_enabled)
	cfg.save(PATH)


func _apply() -> void:
	var i := AudioServer.get_bus_index(MUSIC_BUS)
	if i != -1:
		AudioServer.set_bus_mute(i, not music_enabled)
