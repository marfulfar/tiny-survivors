class_name AnimatedUnit
extends Unit
## A Unit whose Model scene contains an AnimationPlayer, e.g. the KayKit character scenes in
## game/units/models/ (they share the Rig_Medium clip libraries "general/..." and "movement/...").
## Plays idle / walk automatically, and one-shot clips (hit, death, ability casts) on demand.

@export_group("Animation")
@export var idle_animation := &"general/Idle_A"
@export var walk_animation := &"movement/Walking_A"
@export var hit_animation := &"general/Hit_A"
@export var death_animation := &"general/Death_A"
## Held after death_animation ends so the body stays down.
@export var dead_pose_animation := &"general/Death_A_Pose"
## Walk clip playback speed per m/s of walk_speed (stops feet from sliding).
@export var walk_anim_speed_per_mps := 0.45

var _anim: AnimationPlayer
## One-shot clip currently playing; idle/walk wait until it ends.
var _oneshot := &""


func _ready() -> void:
	super()
	_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		push_warning("%s: model has no AnimationPlayer; it will not animate." % name)
	else:
		_anim.animation_finished.connect(_on_animation_finished)


func _process(delta: float) -> void:
	super(delta)
	_update_locomotion()


## Plays a clip once; idle/walk resume when it ends. Returns false if the clip is missing.
func play_oneshot(anim_name: StringName) -> bool:
	if _anim == null or not _anim.has_animation(anim_name):
		return false
	_oneshot = anim_name
	_anim.speed_scale = 1.0
	_anim.play(anim_name, 0.1)
	return true


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != _oneshot:
		return
	_oneshot = &""
	if not is_alive() and _anim.has_animation(dead_pose_animation):
		_oneshot = dead_pose_animation # never cleared: stays down
		_anim.play(dead_pose_animation, 0.0)


func _update_locomotion() -> void:
	if _anim == null or _oneshot != &"":
		return
	if is_walking():
		if _anim.current_animation != walk_animation:
			_anim.play(walk_animation)
		_anim.speed_scale = walk_speed * walk_anim_speed_per_mps
	else:
		if _anim.current_animation != idle_animation:
			_anim.play(idle_animation)
		_anim.speed_scale = 1.0


func _on_hit(from: Vector3, _damage: int) -> void:
	face_toward(from)
	play_oneshot(hit_animation)


func _on_died() -> void:
	play_oneshot(death_animation)
