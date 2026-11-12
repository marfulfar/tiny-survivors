class_name GoblinMaterials
extends RefCounted
## Rebuilds the HD goblin's Blender procedural materials inside Godot.
## glTF can only carry flat colours, so the imported materials are swapped by name
## for StandardMaterial3Ds that use triplanar noise (two-colour ramp + bump),
## which needs no UVs. Materials are built once and shared by every goblin.

## name -> [dark colour, light colour, roughness, metallic, noise scale (per metre), bump strength]
const SPECS := {
	"GHD_Skin": [Color(0.27, 0.40, 0.11), Color(0.44, 0.56, 0.20), 0.55, 0.0, 6.0, 0.6],
	"GHD_Claw": [Color(0.07, 0.06, 0.04), Color(0.18, 0.15, 0.10), 0.4, 0.0, 20.0, 0.2],
	"GHD_Cloth": [Color(0.26, 0.17, 0.08), Color(0.42, 0.30, 0.16), 0.9, 0.0, 5.0, 1.0],
	"GHD_Hood": [Color(0.16, 0.15, 0.08), Color(0.30, 0.26, 0.13), 0.9, 0.0, 5.0, 1.0],
	"GHD_Leather": [Color(0.13, 0.07, 0.035), Color(0.29, 0.16, 0.08), 0.5, 0.0, 9.0, 0.6],
	"GHD_Rope": [Color(0.45, 0.36, 0.21), Color(0.66, 0.55, 0.35), 0.9, 0.0, 25.0, 1.0],
	"GHD_Wood": [Color(0.22, 0.12, 0.05), Color(0.46, 0.29, 0.14), 0.7, 0.0, 4.0, 0.7],
	"GHD_Metal": [Color(0.30, 0.27, 0.24), Color(0.62, 0.62, 0.64), 0.45, 0.9, 8.0, 0.4],
	"GHD_Bone": [Color(0.70, 0.64, 0.48), Color(0.92, 0.88, 0.74), 0.5, 0.0, 8.0, 0.3],
	"GHD_Tooth": [Color(0.72, 0.64, 0.40), Color(0.96, 0.92, 0.76), 0.35, 0.0, 10.0, 0.0],
	"GHD_Mouth": [Color(0.10, 0.015, 0.02), Color(0.28, 0.05, 0.06), 0.4, 0.0, 10.0, 0.0],
	"GHD_Sclera": [Color(0.93, 0.88, 0.62), Color(1.0, 0.97, 0.80), 0.12, 0.0, 6.0, 0.0],
	"GHD_Iris": [Color(0.95, 0.42, 0.0), Color(1.0, 0.75, 0.05), 0.12, 0.0, 30.0, 0.0],
	"GHD_Pupil": [Color(0.0, 0.0, 0.0), Color(0.03, 0.02, 0.01), 0.1, 0.0, 10.0, 0.0],
	"GHD_Tongue": [Color(0.75, 0.25, 0.32), Color(0.95, 0.45, 0.52), 0.35, 0.0, 12.0, 0.2],
}

static var _cache := {}


## Swaps every GHD_* surface material under `root` for its Godot rebuild.
static func apply(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src == null:
				continue
			var key := _base_name(src.resource_name)
			if SPECS.has(key):
				mi.set_surface_override_material(i, get_material(key))


static func get_material(key: String) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var s: Array = SPECS[key]
	var mat := StandardMaterial3D.new()
	mat.resource_name = key
	mat.roughness = s[2]
	mat.metallic = s[3]
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.uv1_scale = Vector3.ONE * float(s[4])

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	noise.seed = key.hash()

	# SPECS colours are Blender's linear values; Godot colours are sRGB.
	var ramp := Gradient.new()
	ramp.set_color(0, (s[0] as Color).linear_to_srgb())
	ramp.set_color(1, (s[1] as Color).linear_to_srgb())
	var albedo := NoiseTexture2D.new()
	albedo.width = 256
	albedo.height = 256
	albedo.seamless = true
	albedo.noise = noise
	albedo.color_ramp = ramp
	mat.albedo_texture = albedo

	if float(s[5]) > 0.0:
		var bump_noise := FastNoiseLite.new()
		bump_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		bump_noise.frequency = 0.08
		bump_noise.fractal_octaves = 3
		bump_noise.seed = key.hash() + 1
		var normal := NoiseTexture2D.new()
		normal.width = 256
		normal.height = 256
		normal.seamless = true
		normal.as_normal_map = true
		normal.bump_strength = 6.0
		normal.noise = bump_noise
		mat.normal_enabled = true
		mat.normal_texture = normal
		mat.normal_scale = s[5]

	_cache[key] = mat
	return mat


## "GHD_Skin.001" / "GHD_Skin_001" -> "GHD_Skin"
static func _base_name(n: String) -> String:
	for key in SPECS:
		if n.begins_with(key):
			# make sure GHD_Pupil doesn't swallow some longer name and vice versa
			var rest := n.substr(key.length())
			if rest == "" or rest.begins_with(".") or rest.begins_with("_0"):
				return key
	return n
