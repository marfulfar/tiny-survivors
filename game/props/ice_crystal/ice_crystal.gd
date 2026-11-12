extends StaticBody3D
## Ice crystal target. Wobbles and shrinks when a fireball hits it,
## and melts into the ground after `hits_to_melt` hits.

@export var hits_to_melt := 3

var _hits := 0
var _tween: Tween

@onready var visual: Node3D = $Visual


func take_hit(_from: Vector3, _damage := 1) -> void:
	_hits += 1
	if _tween:
		_tween.kill()
	_tween = create_tween()
	if _hits >= hits_to_melt:
		collision_layer = 0
		_tween.tween_property(visual, "scale", Vector3(1.4, 0.0, 1.4), 0.7) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_callback(queue_free)
		return
	var size := 1.0 - 0.15 * _hits
	visual.scale = Vector3(size * 1.25, size * 0.75, size * 1.25) # squash on impact
	_tween.tween_property(visual, "scale", Vector3.ONE * size, 0.5) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
