class_name Battle
extends Node3D
## Battle rig: camera + grid + turn controller. Instance game/battle/battle.tscn once in each
## mission scene; the mission supplies the map (ground, scenery, lighting) and places unit
## scenes anywhere in its tree. Units are found by team group (see Unit), so the rig needs no
## node paths to them.

## Playable squares run from -board_half_extent to +board_half_extent on X and Z
## (cell size 1 m, centred on the world origin). Also limits how far the camera can pan.
@export var board_half_extent := 19


func _ready() -> void:
	($Grid as GridBoard).half_extent = board_half_extent
	($CameraRig as CameraRig).bounds = float(board_half_extent)
