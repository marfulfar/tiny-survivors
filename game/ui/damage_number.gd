class_name DamageNumber
## Floating red "-N" that rises and fades above whoever took damage.


static func spawn(parent: Node, at: Vector3, amount: int) -> void:
	var label := Label3D.new()
	label.text = "-%d" % amount
	label.font_size = 72
	label.outline_size = 18
	label.pixel_size = 0.0095 # ~2.4x the original 0.004
	label.modulate = Color(1.0, 0.25, 0.2)
	label.outline_modulate = Color(0.2, 0.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
	label.global_position = at + Vector3(randf_range(-0.2, 0.2), 0.0, 0.0)
	var t := label.create_tween().set_parallel()
	t.tween_property(label, "position:y", label.position.y + 0.7, 0.8).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	t.tween_property(label, "outline_modulate:a", 0.0, 0.8).set_delay(0.3)
	t.chain().tween_callback(label.queue_free)


## Floating action caption ("1st mov", "attack"...) in the same style, attached to `unit` so it
## follows it while it walks. Rises a little and fades.
static func spawn_text(unit: Node3D, height: float, text: String, color := Color(1.0, 0.9, 0.45)) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 72
	label.outline_size = 18
	label.pixel_size = 0.0075
	label.modulate = color
	label.outline_modulate = Color(0.15, 0.1, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	unit.add_child(label)
	label.position = Vector3(0.0, height, 0.0)
	var t := label.create_tween().set_parallel()
	t.tween_property(label, "position:y", height + 0.6, 1.2).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.8)
	t.tween_property(label, "outline_modulate:a", 0.0, 0.6).set_delay(0.8)
	t.chain().tween_callback(label.queue_free)
