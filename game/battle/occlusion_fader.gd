class_name OcclusionFader
extends Node
## Fades scenery that stands between the camera and the units, so nobody is hidden behind a
## tree, rock or building. Purely visual: colliders, line of sight and (later) cover are
## untouched, so a faded rock still blocks shots.
##
## Scenery opts in through the group SCENERY_GROUP (see `scenery_obstacle` on the objects in a
## mission's scenery scene). The same tag is meant to carry cover data later.
## Each tagged object fades as a whole (all its meshes). On first fade it gets its own
## alpha-blended copies of its materials (the originals are shared by every copy of that asset);
## a shadow-only twin keeps its shadow solid while it is faded. Once fully visible again the
## original materials are put back, so unfaded scenery renders exactly as before.
##
## Every frame, sight lines are traced from the camera to each living unit (feet, chest, head)
## and to the hovered square in Move mode; an object whose bounds a line crosses is faded.

const SCENERY_GROUP := &"scenery_obstacle"

@export var camera_path := NodePath("../CameraRig")
@export var tactics_path := NodePath("../Tactics")
## Transparency of a faded object (0 = opaque, 1 = invisible).
@export_range(0.0, 1.0) var faded_transparency := 0.9
@export var fade_speed := 5.0 ## transparency units per second
## Bounds are shrunk by this fraction so lines grazing a box corner don't fade it.
@export_range(0.0, 0.5) var bounds_shrink := 0.12

var camera: Camera3D
var tactics: TacticsController

## One entry per tagged object: {root, aabb, meshes: Array[GeometryInstance3D],
## twins: Array[MeshInstance3D], value: float, goal: float}
var _objects: Array[Dictionary] = []


func _ready() -> void:
	camera = get_node_or_null(camera_path) as Camera3D
	tactics = get_node_or_null(tactics_path) as TacticsController
	_collect.call_deferred() # scenery may sit after the battle rig in the tree


func _collect() -> void:
	_objects.clear()
	for n in get_tree().get_nodes_in_group(SCENERY_GROUP):
		var root := n as Node3D
		if root == null:
			continue
		var meshes: Array[GeometryInstance3D] = []
		for g in root.find_children("*", "GeometryInstance3D", true, false):
			meshes.append(g as GeometryInstance3D)
		if meshes.is_empty():
			continue
		var box := _world_bounds(meshes)
		box = box.grow(-minf(box.size.x, box.size.z) * bounds_shrink * 0.5)
		_objects.append({root = root, aabb = box, meshes = meshes, twins = [], fades = [],
				value = 0.0, goal = 0.0})


func _process(delta: float) -> void:
	if camera == null or _objects.is_empty():
		return
	var eye := camera.global_position
	var points := _sight_points()
	for o in _objects:
		var box: AABB = o.aabb
		var hit := false
		for p in points:
			if box.intersects_segment(eye, p):
				hit = true
				break
		o.goal = faded_transparency if hit else 0.0
		if not is_equal_approx(o.value, o.goal):
			_set_fade(o, move_toward(o.value, o.goal, fade_speed * delta))


## Points that must stay visible: each living unit at three heights, plus the hovered square.
func _sight_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for t in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		for u in Unit.living(get_tree(), t):
			var base := u.global_position
			out.append(base + Vector3.UP * 0.2)
			out.append(base + Vector3.UP * u.aim_height)
			out.append(base + Vector3.UP * maxf(u.health_bar_height - 0.6, u.aim_height))
	if tactics:
		var hover: Variant = tactics.hover_point()
		if hover != null:
			out.append((hover as Vector3) + Vector3.UP * 0.2)
	return out


func _set_fade(o: Dictionary, value: float) -> void:
	var was_faded: bool = o.value > 0.0
	o.value = value
	var faded := value > 0.0
	if faded and o.twins.is_empty():
		_make_shadow_twins(o)
	if faded and o.fades.is_empty():
		_make_fade_materials(o)
	for f: Array in o.fades:
		var mat := f[2] as BaseMaterial3D
		var c := mat.albedo_color
		c.a = (f[3] as float) * (1.0 - value)
		mat.albedo_color = c
		if faded != was_faded:
			(f[0] as MeshInstance3D).set_surface_override_material(f[1], mat if faded else f[4])
	for g: GeometryInstance3D in o.meshes:
		if faded != was_faded:
			# the twin casts the shadow while faded, so the shadow doesn't fade with it
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if faded \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if faded != was_faded:
		for t: MeshInstance3D in o.twins:
			t.visible = faded


## Per surface: [mesh_instance, surface, faded_copy, original_alpha, previous_override].
func _make_fade_materials(o: Dictionary) -> void:
	for g: GeometryInstance3D in o.meshes:
		var mi := g as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as BaseMaterial3D
			if src == null:
				continue # custom shaders are left alone
			var copy := src.duplicate() as BaseMaterial3D
			copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			o.fades.append([mi, i, copy, src.albedo_color.a, mi.get_surface_override_material(i)])


func _make_shadow_twins(o: Dictionary) -> void:
	for g: GeometryInstance3D in o.meshes:
		var mi := g as MeshInstance3D
		if mi == null or mi.mesh == null or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var twin := MeshInstance3D.new()
		twin.mesh = mi.mesh
		twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		twin.visible = false
		mi.add_child(twin) # identity transform = same place as the original
		o.twins.append(twin)


static func _world_bounds(meshes: Array[GeometryInstance3D]) -> AABB:
	var out := AABB()
	var first := true
	for g in meshes:
		var box := g.global_transform * g.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
