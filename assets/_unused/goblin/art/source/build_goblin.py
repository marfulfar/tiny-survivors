"""Builds the hooded goblin ranger and its corpse in Blender, and exports both GLBs.

Run inside Blender:  exec(open(r"<path>/build_goblin.py").read())
Collections "Goblin" and "GoblinCorpse" are cleared and rebuilt each time.
"""
import bpy, bmesh, math, os
from mathutils import Vector

OUT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(
    r"<path-to-tiny-survivors>\assets\_unused\goblin\art\source\build_goblin.py")))  # set before running


def mat(name, color, rough=0.8, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


M = {
    "skin": mat("GB_Skin", (0.34, 0.56, 0.18)),
    "dark": mat("GB_SkinDark", (0.17, 0.33, 0.08)),
    "hood": mat("GB_Hood", (0.26, 0.22, 0.11)),
    "cloth": mat("GB_Cloth", (0.40, 0.27, 0.13)),
    "leather": mat("GB_Leather", (0.24, 0.13, 0.06)),
    "rope": mat("GB_Rope", (0.62, 0.50, 0.30)),
    "metal": mat("GB_Metal", (0.58, 0.60, 0.63), 0.35, 0.8),
    "shield": mat("GB_ShieldWood", (0.47, 0.29, 0.13)),
    "wood": mat("WZ_Wood", (0.40, 0.22, 0.10)),
    "eye": mat("GB_Eye", (1.0, 0.85, 0.15), 0.4),
    "pupil": mat("GB_Pupil", (0.02, 0.02, 0.02), 0.3),
    "tooth": mat("GB_Tooth", (0.95, 0.92, 0.80), 0.4),
    "mouth": mat("GB_Mouth", (0.22, 0.03, 0.04)),
    "tongue": mat("GB_Tongue", (0.95, 0.40, 0.50), 0.5),
}


def get_col(name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    for o in list(col.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    return col


def set_origin(o, point):
    cur = bpy.context.scene.cursor.location.copy()
    bpy.context.scene.cursor.location = point
    for x in bpy.context.view_layer.objects:
        x.select_set(False)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.context.scene.cursor.location = cur
    o.select_set(False)


def finish(o, col, name, m, parent, smooth=True, origin=None, post=None):
    o.name = name
    o.data.name = name
    for c in list(o.users_collection):
        c.objects.unlink(o)
    col.objects.link(o)
    o.data.materials.clear()
    o.data.materials.append(m)
    if smooth:
        for p in o.data.polygons:
            p.use_smooth = True
    if post:
        post(o)
    bpy.context.view_layer.update()
    if origin is not None:
        set_origin(o, origin)
        bpy.context.view_layer.update()
    if parent is not None:
        wm = o.matrix_world.copy()
        o.parent = parent
        o.matrix_world = wm
    return o


def add(col, parent, name, kind, m, loc, rot=(0, 0, 0), scale=(1, 1, 1), origin=None, post=None, **kw):
    if kind == 'sphere':
        bpy.ops.mesh.primitive_uv_sphere_add(segments=kw.get('seg', 18), ring_count=kw.get('rings', 12), radius=kw['r'], location=loc, rotation=rot)
    elif kind == 'cone':
        bpy.ops.mesh.primitive_cone_add(vertices=kw.get('seg', 14), radius1=kw['r1'], radius2=kw['r2'], depth=kw['d'], location=loc, rotation=rot)
    elif kind == 'cyl':
        bpy.ops.mesh.primitive_cylinder_add(vertices=kw.get('seg', 12), radius=kw['r'], depth=kw['d'], location=loc, rotation=rot)
    elif kind == 'cube':
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    elif kind == 'torus':
        bpy.ops.mesh.primitive_torus_add(major_radius=kw['R'], minor_radius=kw['r'], major_segments=kw.get('seg', 24), minor_segments=8, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = scale
    return finish(o, col, name, m, parent, smooth=(kind != 'cube'), origin=origin, post=post)


def along(d):
    return Vector(d).normalized().to_track_quat('Z', 'Y').to_euler()


def limb(col, parent, name, a, b, r, m, seg=10):
    a, b = Vector(a), Vector(b)
    return add(col, parent, name, 'cyl', m, (a + b) / 2, rot=along(b - a), origin=a, r=r, d=(b - a).length, seg=seg)


def ragged(amount):
    """Zig-zags the bottom ring of a cone for a torn-cloth edge."""
    def f(o):
        vs = list(o.data.vertices)
        zmin = min(v.co.z for v in vs)
        ring = sorted([v for v in vs if abs(v.co.z - zmin) < 1e-5], key=lambda v: math.atan2(v.co.y, v.co.x))
        for i, v in enumerate(ring):
            v.co.z += amount if i % 2 else -amount * 0.4
    return f


def empty(col, name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    col.objects.link(e)
    e.location = loc
    if parent is not None:
        bpy.context.view_layer.update()
        e.parent = parent
        e.matrix_parent_inverse = parent.matrix_world.inverted()
    return e


def hood(col, parent, name, center, r):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=28, v_segments=18, radius=r)
    kill = []
    for f in bm.faces:
        n = f.calc_center_median().normalized()
        if (n.y < -0.42 and n.z > -0.8) or n.z < -0.62:  # face opening + neck hole
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    for v in bm.verts:
        n = v.co.normalized()
        k = max(0.0, n.y) * max(0.0, n.z + 0.25)
        v.co += Vector((0.0, 1.1 * r * k * k, 0.25 * r * k * k))  # pointed tip, back and up
        if n.y < -0.2:  # flare the front opening a little
            v.co.x *= 1.06
            v.co.z *= 1.04
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    o.location = center
    bpy.context.scene.collection.objects.link(o)
    sub = o.modifiers.new("Subsurf", 'SUBSURF')
    sub.levels = sub.render_levels = 1
    sol = o.modifiers.new("Solidify", 'SOLIDIFY')
    sol.thickness = 0.018
    sol.offset = 1.0
    return finish(o, col, name, M["hood"], parent)


def build(col, prefix, corpse=False):
    """Goblin faces -Y (Godot +Z). Upper body hangs off a 'Body' empty at the hips,
    head off 'HeadPivot' at the neck, so Godot can animate them."""
    root = empty(col, prefix)
    body = empty(col, "Body", root, (0, 0, 0.55))
    # torso & clothes
    add(col, body, "Torso", 'sphere', M["cloth"], (0, 0, 0.78), scale=(1.0, 0.8, 1.6), r=0.16)
    add(col, body, "Skirt", 'cone', M["cloth"], (0, 0, 0.52), r1=0.2, r2=0.13, d=0.26, seg=18, post=ragged(0.035))
    add(col, body, "Belt", 'torus', M["rope"], (0, 0, 0.63), R=0.14, r=0.016)
    add(col, body, "Mantle", 'cone', M["hood"], (0, 0.01, 0.97), r1=0.27, r2=0.08, d=0.2, seg=18, post=ragged(0.04))
    limb(col, body, "Neck", (0, 0, 1.0), (0, -0.01, 1.08), 0.04, M["skin"])
    # head
    head = empty(col, "HeadPivot", body, (0, 0, 1.04))
    add(col, head, "Head", 'sphere', M["skin"], (0, -0.02, 1.18), scale=(0.95, 1.05, 1.0), r=0.15, seg=24, rings=16)
    hood(col, head, "Hood", (0, 0.0, 1.2), 0.185)
    for s, side in ((-1, 'R'), (1, 'L')):  # faces -Y, so its right side is -X
        base = Vector((s * 0.13, 0.0, 1.2))
        d = Vector((s * 0.9, 0.3, 0.3)).normalized()
        add(col, head, f"Ear_{side}", 'cone', M["skin"], base + d * 0.16, rot=along(d), scale=(1, 0.4, 1), origin=base, r1=0.065, r2=0.0, d=0.32)
        add(col, head, f"Eye_{side}", 'sphere', M["eye"], (s * 0.055, -0.16, 1.21), scale=(1.2, 0.6, 0.7), r=0.035, seg=12, rings=8)
        if corpse:
            for ang in (45, -45):
                add(col, head, f"X_{side}_{ang}", 'cube', M["pupil"], (s * 0.055, -0.182, 1.21), rot=(0, math.radians(ang), 0), scale=(0.055, 0.01, 0.012))
        else:
            add(col, head, f"Pupil_{side}", 'sphere', M["pupil"], (s * 0.06, -0.18, 1.21), r=0.016, seg=8, rings=6)
        add(col, head, f"Brow_{side}", 'cube', M["dark"], (s * 0.058, -0.17, 1.245), rot=(0, -s * math.radians(25 if not corpse else -10), 0), scale=(0.065, 0.02, 0.016))
    nd = Vector((0, -0.85, -0.5)).normalized()
    add(col, head, "Nose", 'cone', M["skin"], Vector((0, -0.165, 1.17)) + nd * 0.085, rot=along(nd), r1=0.045, r2=0.01, d=0.17)
    add(col, head, "Mouth", 'sphere', M["mouth"], (0, -0.14, 1.095), scale=(1.5, 0.5, 0.45), r=0.07, seg=16, rings=10)
    for i, x in enumerate((-0.06, -0.03, 0.0, 0.03, 0.06)):
        add(col, head, f"Tooth_{i}", 'cone', M["tooth"], (x, -0.168, 1.098), rot=(math.pi, 0, 0), r1=0.012, r2=0.0, d=0.03, seg=6)
    if corpse:
        add(col, head, "Tongue", 'sphere', M["tongue"], (0.03, -0.17, 1.065), scale=(0.6, 0.35, 1.1), r=0.035, seg=10, rings=8)
    # arms: shoulder, elbow, hand
    if corpse:  # flung out above the head
        arms = {'L': ((0.17, 0, 0.98), (0.36, 0.0, 1.06), (0.52, -0.03, 1.16)),
                'R': ((-0.17, 0, 0.98), (-0.36, 0.0, 1.04), (-0.53, -0.02, 1.12))}
    else:
        arms = {'L': ((0.17, 0, 0.98), (0.25, -0.06, 0.78), (0.22, -0.22, 0.7)),
                'R': ((-0.17, 0, 0.98), (-0.25, -0.02, 0.77), (-0.18, -0.2, 0.62))}
    for side, (sh, el, ha) in arms.items():
        sh, el, ha = Vector(sh), Vector(el), Vector(ha)
        limb(col, body, f"UpperArm_{side}", sh, el, 0.038, M["skin"])
        limb(col, body, f"Forearm_{side}", el, ha, 0.034, M["skin"])
        limb(col, body, f"Bracer_{side}", el + (ha - el) * 0.3, el + (ha - el) * 0.85, 0.05, M["leather"])
        add(col, body, f"Hand_{side}", 'sphere', M["skin"], ha, r=0.047, seg=12, rings=8)
    if not corpse:
        # spear in the right hand, tip forward and low
        hand = Vector(arms['R'][2])
        d = Vector((0.15, -0.9, -0.25)).normalized()
        limb(col, body, "Spear", hand - d * 0.75, hand + d * 0.75, 0.018, M["wood"], seg=8)
        add(col, body, "SpearTip", 'cone', M["metal"], hand + d * 0.85, rot=along(d), scale=(1, 0.35, 1), r1=0.045, r2=0.0, d=0.2, seg=8)
        limb(col, body, "SpearWrap", hand + d * 0.7, hand + d * 0.76, 0.024, M["leather"])
        # round shield on the left arm
        hand = Vector(arms['L'][2])
        n = Vector((0.55, -0.8, 0.1)).normalized()
        c = hand + n * 0.05
        add(col, body, "Shield", 'cyl', M["shield"], c, rot=along(n), r=0.23, d=0.035, seg=24)
        add(col, body, "ShieldRim", 'torus', M["metal"], c, rot=along(n), R=0.23, r=0.018, seg=28)
        add(col, body, "ShieldBoss", 'sphere', M["metal"], c + n * 0.025, r=0.045, seg=12, rings=8)
    # legs stay outside Body so the upper body can bob and hunch on its own
    knee_y = -0.02 if corpse else -0.07
    for s, side in ((-1, 'R'), (1, 'L')):
        hip, knee, ankle = Vector((s * 0.09, 0, 0.5)), Vector((s * 0.11, knee_y, 0.29)), Vector((s * 0.12, 0.0, 0.07))
        limb(col, root, f"Thigh_{side}", hip, knee, 0.045, M["skin"])
        limb(col, root, f"Shin_{side}", knee, ankle, 0.04, M["skin"])
        add(col, root, f"Knee_{side}", 'sphere', M["skin"], knee, r=0.046, seg=10, rings=8)
        add(col, root, f"Foot_{side}", 'sphere', M["skin"], (s * 0.12, -0.07, 0.035), scale=(0.85, 1.9, 0.5), r=0.065, seg=14, rings=10)
    # pose
    if corpse:
        head.rotation_euler = (0, math.radians(25), 0)  # head lolls to the side
    else:
        body.rotation_euler = (math.radians(20), 0, 0)   # hunched forward...
        head.rotation_euler = (math.radians(-18), 0, 0)  # ...but looking up at you
    bpy.context.view_layer.update()
    return root


def lay_down(col, root):
    """Rotates the corpse onto its back (head toward +Y = behind) and lifts it onto the ground.
    Returns the lift, which goblin.gd's CORPSE_LIFT must match."""
    root.rotation_euler = (math.radians(-90), 0, 0)
    bpy.context.view_layer.update()
    minz = min((o.matrix_world @ Vector(c)).z for o in col.objects if o.type == 'MESH' for c in o.bound_box)
    root.location.z = -minz
    bpy.context.view_layer.update()
    # dropped gear lying on the ground
    a, b = Vector((-0.5, -0.65, 0.03)), Vector((-0.38, 0.85, 0.03))
    limb(col, root, "DroppedSpear", a, b, 0.018, M["wood"], seg=8)
    d = (a - b).normalized()
    add(col, root, "DroppedSpearTip", 'cone', M["metal"], a + d * 0.1, rot=along(d), scale=(1, 0.35, 1), r1=0.045, r2=0.0, d=0.2, seg=8)
    c = Vector((0.6, 0.2, 0.02))
    add(col, root, "DroppedShield", 'cyl', M["shield"], c, r=0.23, d=0.035, seg=24)
    add(col, root, "DroppedShieldRim", 'torus', M["metal"], c, R=0.23, r=0.018, seg=28)
    add(col, root, "DroppedShieldBoss", 'sphere', M["metal"], c + Vector((0, 0, 0.025)), r=0.045, seg=12, rings=8)
    return -minz


def export(col_name, root, path):
    saved = root.location.copy()
    root.location.x = root.location.y = 0
    vl = bpy.context.view_layer
    vl.active_layer_collection = vl.layer_collection.children[col_name]
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_active_collection=True, export_apply=True, export_yup=True)
    root.location = saved


gcol = get_col("Goblin")
gob = build(gcol, "Goblin")
ccol = get_col("GoblinCorpse")
cor = build(ccol, "GoblinCorpse", corpse=True)
LIFT = lay_down(ccol, cor)
for me in list(bpy.data.meshes):
    if me.users == 0:
        bpy.data.meshes.remove(me)

export("Goblin", gob, os.path.join(OUT_DIR, "goblin.glb"))
export("GoblinCorpse", cor, os.path.join(OUT_DIR, "goblin_corpse.glb"))
# display positions in the viewport
gob.location = (-1.5, 0, 0)
cor.location = (-1.5, 1.8, LIFT)
bpy.context.view_layer.update()
