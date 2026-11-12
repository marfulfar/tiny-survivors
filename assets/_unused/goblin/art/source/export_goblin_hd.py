"""Builds the HD goblin + its corpse and exports both GLBs for Godot.

Run inside Blender:
    exec(compile(open(PATH).read(), PATH, "exec"), {"__name__": "__main__"})

The corpse is a copy of the HD goblin: hunch straightened, arms flung out, eyes shut,
tongue out, laid on its back, spear and shield dropped on the ground beside it.
Procedural materials can't be exported, so base colours are flattened for the export and
Godot rebuilds the look by material name (scripts/goblin_materials.gd).
"""
import bpy, math, os
from mathutils import Vector, Matrix

HERE = r"<path-to-tiny-survivors>\assets\_unused\goblin\art\source"  # set before running
OUT = os.path.dirname(HERE)

g = {"__name__": "__main__"}
build_path = os.path.join(HERE, "build_goblin_hd.py")
exec(compile(open(build_path).read(), build_path, "exec"), g)

src = bpy.data.collections["GoblinHD"]
src_root = bpy.data.objects[[o.name for o in src.objects if o.parent is None][0]]

# ---------------------------------------------------------------- corpse copy
dst = bpy.data.collections.get("GoblinHDCorpse")
if dst is None:
    dst = bpy.data.collections.new("GoblinHDCorpse")
    bpy.context.scene.collection.children.link(dst)
for o in list(dst.objects):
    bpy.data.objects.remove(o, do_unlink=True)

import re

parts = []     # (base name without Blender's .001 suffix, corpse copy)
mapping = {}
for o in src.objects:
    c = o.copy()
    if o.type == 'MESH' and o.name.startswith("TorsoArms"):
        c.data = o.data.copy()  # we edit its skin nodes
    dst.objects.link(c)
    mapping[o] = c
    parts.append((re.sub(r"\.\d{3}$", "", o.name), c))
for o, c in mapping.items():
    if o.parent in mapping:
        c.parent = mapping[o.parent]
        c.matrix_parent_inverse = o.matrix_parent_inverse.copy()


def find(prefix):
    return [c for name, c in parts if name.startswith(prefix)]


def exact(name):
    return next(c for n, c in parts if n == name)


root = mapping[src_root]
root.location = (0, 0, 0)
root.rotation_euler = (0, 0, 0)
body = exact("Body")
head = exact("HeadPivot")
body.rotation_euler = (0, 0, 0)
head.rotation_euler = (0, 0, 0)
bpy.context.view_layer.update()


def rotate_about(objs, pivot, mat3):
    M = Matrix.Translation(pivot) @ mat3.to_4x4() @ Matrix.Translation(-pivot)
    for o in objs:
        o.matrix_world = M @ o.matrix_world
    bpy.context.view_layer.update()


# arms flung out: rotate the arm skin nodes (mesh vertices) and everything worn on the arms
torso = find("TorsoArms")[0]
for side, sx, ang in (('L', 1, -80), ('R', -1, 80)):
    pivot = Vector((sx * 0.14, -0.15, 0.935))
    R = Matrix.Rotation(math.radians(ang), 3, 'Y') @ Matrix.Rotation(math.radians(-20), 3, 'X')
    for v in torso.data.vertices:
        if v.index >= 7 and v.co.x * sx > 0.12:
            v.co = pivot + R @ (v.co - pivot)
    worn = find(f"Bracer_{side}") + find(f"BracerStrap_{side}") + find(f"BracerBuckle_{side}")
    if side == 'R':
        worn += find("Claw_R")
    rotate_about(worn, pivot, R)

# eyes shut: swing the upper lids down over the eyeballs
for side in ('L', 'R'):
    eye = find(f"Eye_{side}")[0]
    ec = eye.matrix_world.translation.copy()
    rotate_about(find(f"LidUpper_{side}"), ec, Matrix.Rotation(math.radians(55), 3, 'X'))
    for o in find(f"Pupil_{side}") + find(f"Iris_{side}"):
        o.hide_render = True
        dst.objects.unlink(o)

# tongue lolling out of the corner of the mouth
tongue_mat = g["pmat"]("GHD_Tongue", (0.75, 0.25, 0.32), (0.95, 0.45, 0.52), rough=0.35, scale=12, bump=0.1)
tp = g["to_world"](g["head_point"](0.28, g["mouth_z"](0.28) - 0.03) + Vector((0, -0.02, -0.12)))
t = g["prim"]('sphere', "Tongue", tongue_mat, tp, None, scale=(0.55, 0.4, 1.3), r=0.022, seg=14, rings=10)
for c in list(t.users_collection):
    c.objects.unlink(t)
dst.objects.link(t)
bpy.context.view_layer.update()
wm = t.matrix_world.copy()
t.parent = head
t.matrix_world = wm

head.rotation_euler = (0, math.radians(25), 0)  # head lolls to the side
bpy.context.view_layer.update()

# lay him on his back (head toward +Y, i.e. behind him) and rest him on the ground
spear_parts = find("Spear")
shield_parts = [c for name, c in parts if name.startswith(("ShieldPlank", "ShieldRim", "ShieldRivet",
                                                           "ShieldStrap", "StrapRivet", "ShieldBoss", "ShieldHorn"))]
gear = set(spear_parts + shield_parts)
root.rotation_euler = (math.radians(-90), 0, 0)
bpy.context.view_layer.update()


def world_min_z(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    z = 1e9
    for o in objs:
        if o.type not in ('MESH', 'CURVE'):
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        for v in me.vertices:
            z = min(z, (ev.matrix_world @ v.co).z)
        ev.to_mesh_clear()
    return z


body_parts = [o for o in dst.objects if o not in gear]
LIFT = -world_min_z(body_parts)
root.location.z = LIFT
bpy.context.view_layer.update()


def drop(parts, axis_obj, local_axis, target_pos, target_axis):
    """Moves a rigid group so axis_obj's local axis lines up with target_axis at target_pos,
    then settles it onto the ground."""
    a = (axis_obj.matrix_world.to_3x3() @ Vector(local_axis)).normalized()
    c = axis_obj.matrix_world.translation.copy()
    R = a.rotation_difference(Vector(target_axis).normalized()).to_matrix().to_4x4()
    M = Matrix.Translation(Vector(target_pos)) @ R @ Matrix.Translation(-c)
    for o in parts:
        o.matrix_world = M @ o.matrix_world
    bpy.context.view_layer.update()
    dz = -world_min_z(parts) + 0.003
    for o in parts:
        o.matrix_world = Matrix.Translation((0, 0, dz)) @ o.matrix_world
    bpy.context.view_layer.update()


drop(spear_parts, exact("Spear"), (0, 0, 1),
     (-0.5, 0.05, 0.0), (0.18, -1.0, 0.0))
drop(shield_parts, exact("ShieldBoss"), (0, 0, 1), (0.58, 0.2, 0.0), (0.0, 0.0, 1.0))


# ---------------------------------------------------------------- export
def flatten_base_colors(flat):
    """glTF can't carry the noise -> ramp base colour; temporarily unlink it so the
    exported colour is the material's mid colour."""
    for m in bpy.data.materials:
        if not m.name.startswith("GHD_") or not m.node_tree:
            continue
        nt = m.node_tree
        bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        ramp = next((n for n in nt.nodes if n.type == 'VALTORGB'), None)
        if not bsdf or not ramp:
            continue
        if flat:
            for l in list(bsdf.inputs["Base Color"].links):
                nt.links.remove(l)
        else:
            nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])


def export(col_name, root_obj, path):
    saved = root_obj.location.copy()
    root_obj.location.x = root_obj.location.y = 0
    bpy.context.view_layer.update()
    vl = bpy.context.view_layer
    vl.active_layer_collection = vl.layer_collection.children[col_name]
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_active_collection=True,
                              export_apply=True, export_yup=True)
    root_obj.location = saved


flatten_base_colors(True)
try:
    export("GoblinHD", src_root, os.path.join(OUT, "goblin_hd.glb"))
    export("GoblinHDCorpse", root, os.path.join(OUT, "goblin_hd_corpse.glb"))
finally:
    flatten_base_colors(False)

# display the corpse beside the goblin
root.location = Vector((-3.5, 1.6, LIFT))
bpy.context.view_layer.update()
