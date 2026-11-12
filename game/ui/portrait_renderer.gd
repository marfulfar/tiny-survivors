class_name PortraitRenderer
extends RefCounted
## Takes a still head-and-shoulders snapshot of a unit's model, for UI portraits.
## A copy of the unit's "Model" node is posed in a private 3D world (its own SubViewport,
## camera, light and transparent background), rendered once and turned into a texture.
## Works for any unit scene that follows the Unit contract, so new characters and enemies
## get a portrait with no extra art. Awaitable:
##     var tex := await PortraitRenderer.capture(unit)

const SIZE := 160
## Fraction of the model's height shown (from the top down): head and shoulders.
const FRAME_FRACTION := 0.5
## Camera yaw off straight-on, so the face reads in three-quarter view.
const YAW_DEGREES := 25.0


static func capture(unit: Unit, size := SIZE) -> Texture2D:
	if unit == null or not is_instance_valid(unit) or unit.model == null:
		return null
	var tree := unit.get_tree()

	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(vp)

	var model := unit.model.duplicate() as Node3D
	model.transform = Transform3D.IDENTITY # front (+Z) towards the camera
	vp.add_child(model)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.9)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	vp.add_child(key)
	key.look_at_from_position(Vector3(1.5, 3.0, 3.0), Vector3.ZERO)

	# let the AnimationPlayer apply its first idle frame so the bounds reflect the pose
	await tree.process_frame
	var bounds := _bounds(model)
	var top := bounds.end.y
	var height := maxf(bounds.size.y, 0.5)
	var frame := height * FRAME_FRACTION
	var look_at := Vector3(0.0, top - frame * 0.5, 0.0)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = frame * 1.05
	cam.environment = env
	cam.current = true
	vp.add_child(cam)
	var yaw := deg_to_rad(YAW_DEGREES)
	cam.look_at_from_position(look_at + Vector3(sin(yaw), 0.08, cos(yaw)) * 6.0, look_at)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return ImageTexture.create_from_image(img)


## Weapons and props hang off BoneAttachment3D nodes; a tall staff must not set the framing.
static func _is_held_item(n: Node, root: Node) -> bool:
	var p := n.get_parent()
	while p and p != root:
		if p is BoneAttachment3D:
			return true
		p = p.get_parent()
	return false


## Bounding box of every visible body mesh (held items excluded) under `root`, in root's space.
static func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for vi: Node in root.find_children("*", "VisualInstance3D", true, false):
		var v := vi as VisualInstance3D
		if not v.is_visible_in_tree() or _is_held_item(v, root):
			continue
		var box := root.global_transform.affine_inverse() * v.global_transform * v.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
