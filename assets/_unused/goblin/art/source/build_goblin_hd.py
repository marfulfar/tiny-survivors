"""Detailed (non-low-poly) hooded goblin ranger, built procedurally in Blender.

Run inside Blender:
    exec(compile(open(PATH).read(), PATH, "exec"), {"__name__": "__main__"})
Rebuilds the "GoblinHD" collection. Organic parts use Skin + Subdivision modifiers,
the head is a deformed sphere, clothes are lofted shells. Materials are procedural
(noise/wave + bump), so they need baking before export to a game engine.

Hierarchy (kept compatible with the game's goblin script):
    GoblinHD (root, feet on the ground, faces -Y)
      Body      (empty at the hips: torso, arms, clothes, gear)
        HeadPivot (empty at the neck: head, ears, eyes, nose, teeth, hood)
      Legs
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix

COLLECTION = "GoblinHD"
DISPLAY_OFFSET = Vector((-3.5, 0.0, 0.0))
rng = random.Random(7)


# ---------------------------------------------------------------- materials
def pmat(name, c1, c2, rough=0.6, scale=6.0, bump=0.15, fine=80.0, metal=0.0, sss=0.0, wave=False):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    tex = nt.nodes.new("ShaderNodeTexWave" if wave else "ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = scale
    if wave:
        tex.inputs["Distortion"].default_value = 6.0
        tex.inputs["Detail"].default_value = 3.0
    else:
        tex.inputs["Detail"].default_value = 6.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*c1, 1)
    ramp.color_ramp.elements[1].color = (*c2, 1)
    finen = nt.nodes.new("ShaderNodeTexNoise")
    finen.inputs["Scale"].default_value = fine
    finen.inputs["Detail"].default_value = 4.0
    bmp = nt.nodes.new("ShaderNodeBump")
    bmp.inputs["Strength"].default_value = bump
    L = nt.links
    L.new(tc.outputs["Object"], tex.inputs["Vector"])
    L.new(tc.outputs["Object"], finen.inputs["Vector"])
    L.new(tex.outputs["Fac"], ramp.inputs["Fac"])
    L.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    L.new(finen.outputs["Fac"], bmp.inputs["Height"])
    L.new(bmp.outputs["Normal"], bsdf.inputs["Normal"])
    L.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    mid = tuple((a + b) / 2 for a, b in zip(c1, c2))
    bsdf.inputs["Base Color"].default_value = (*mid, 1)  # fallback for exporters
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if sss > 0:
        bsdf.inputs["Subsurface Weight"].default_value = sss
        bsdf.inputs["Subsurface Radius"].default_value = (1.0, 0.5, 0.25)
        bsdf.inputs["Subsurface Scale"].default_value = 0.02
    m.diffuse_color = (*mid, 1)
    return m


M = {
    "skin": pmat("GHD_Skin", (0.27, 0.40, 0.11), (0.44, 0.56, 0.20), rough=0.55, scale=9, bump=0.25, fine=140, sss=0.08),
    "claw": pmat("GHD_Claw", (0.07, 0.06, 0.04), (0.18, 0.15, 0.10), rough=0.4),
    "cloth": pmat("GHD_Cloth", (0.26, 0.17, 0.08), (0.42, 0.30, 0.16), rough=0.9, scale=5, bump=0.3, fine=260),
    "hood": pmat("GHD_Hood", (0.16, 0.15, 0.08), (0.30, 0.26, 0.13), rough=0.9, scale=5, bump=0.3, fine=260),
    "leather": pmat("GHD_Leather", (0.13, 0.07, 0.035), (0.29, 0.16, 0.08), rough=0.5, scale=12, bump=0.2, fine=120),
    "rope": pmat("GHD_Rope", (0.45, 0.36, 0.21), (0.66, 0.55, 0.35), rough=0.9, scale=20, bump=0.4, fine=300),
    "wood": pmat("GHD_Wood", (0.22, 0.12, 0.05), (0.46, 0.29, 0.14), rough=0.7, scale=3, bump=0.25, fine=90, wave=True),
    "metal": pmat("GHD_Metal", (0.30, 0.27, 0.24), (0.62, 0.62, 0.64), rough=0.45, scale=10, bump=0.2, fine=60, metal=0.9),
    "bone": pmat("GHD_Bone", (0.70, 0.64, 0.48), (0.92, 0.88, 0.74), rough=0.5, scale=8, bump=0.15),
    "tooth": pmat("GHD_Tooth", (0.72, 0.64, 0.40), (0.96, 0.92, 0.76), rough=0.35, scale=10, bump=0.05),
    "mouth": pmat("GHD_Mouth", (0.10, 0.015, 0.02), (0.28, 0.05, 0.06), rough=0.4, scale=10, bump=0.1),
    "sclera": pmat("GHD_Sclera", (0.93, 0.88, 0.62), (1.0, 0.97, 0.80), rough=0.12, scale=6, bump=0.0),
    "iris": pmat("GHD_Iris", (0.95, 0.42, 0.0), (1.0, 0.75, 0.05), rough=0.12, scale=30, bump=0.0),
    "pupil": pmat("GHD_Pupil", (0.0, 0.0, 0.0), (0.03, 0.02, 0.01), rough=0.1, bump=0.0),
}


# ---------------------------------------------------------------- helpers
def get_col():
    col = bpy.data.collections.get(COLLECTION)
    if col is None:
        col = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(col)
    for o in list(col.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    return col


COL = get_col()


def lumps_texture():
    t = bpy.data.textures.get("GHD_Lumps") or bpy.data.textures.new("GHD_Lumps", 'CLOUDS')
    t.noise_scale = 0.06
    return t


def link(o, m, parent=None, smooth=True):
    for c in list(o.users_collection):
        c.objects.unlink(o)
    COL.objects.link(o)
    if m is not None and o.data is not None and hasattr(o.data, "materials"):
        o.data.materials.clear()
        o.data.materials.append(m)
    if smooth and o.type == 'MESH':
        for p in o.data.polygons:
            p.use_smooth = True
    if parent is not None:
        bpy.context.view_layer.update()
        wm = o.matrix_world.copy()
        o.parent = parent
        o.matrix_world = wm
    return o


def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    COL.objects.link(e)
    e.location = loc
    if parent is not None:
        bpy.context.view_layer.update()
        e.parent = parent
        e.matrix_parent_inverse = parent.matrix_world.inverted()
    return e


def mesh_obj(name, bm, m, parent, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    return link(o, m, parent, smooth)


def subsurf(o, levels=1):
    s = o.modifiers.new("Subsurf", 'SUBSURF')
    s.levels = s.render_levels = levels
    return o


def solidify(o, t, offset=0.0):
    s = o.modifiers.new("Solidify", 'SOLIDIFY')
    s.thickness = t
    s.offset = offset
    return o


def displace(o, strength, scale=0.06):
    t = bpy.data.textures.get(f"GHD_Lumps_{scale}") or bpy.data.textures.new(f"GHD_Lumps_{scale}", 'CLOUDS')
    t.noise_scale = scale
    d = o.modifiers.new("Lumps", 'DISPLACE')
    d.texture = t
    d.strength = strength
    d.texture_coords = 'GLOBAL'
    return o


def prim(kind, name, m, loc, parent, rot=(0, 0, 0), scale=(1, 1, 1), smooth=True, **kw):
    if kind == 'sphere':
        bpy.ops.mesh.primitive_uv_sphere_add(segments=kw.get('seg', 16), ring_count=kw.get('rings', 10), radius=kw['r'], location=loc, rotation=rot)
    elif kind == 'cone':
        bpy.ops.mesh.primitive_cone_add(vertices=kw.get('seg', 10), radius1=kw['r1'], radius2=kw['r2'], depth=kw['d'], location=loc, rotation=rot)
    elif kind == 'cyl':
        bpy.ops.mesh.primitive_cylinder_add(vertices=kw.get('seg', 12), radius=kw['r'], depth=kw['d'], location=loc, rotation=rot)
    elif kind == 'torus':
        bpy.ops.mesh.primitive_torus_add(major_radius=kw['R'], minor_radius=kw['r'], major_segments=kw.get('seg', 32), minor_segments=kw.get('mseg', 8), location=loc, rotation=rot)
    elif kind == 'cube':
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    o.scale = scale
    bpy.context.view_layer.update()
    return link(o, m, parent, smooth)


def along(d):
    return Vector(d).normalized().to_track_quat('Z', 'Y').to_euler()


def skin_obj(name, nodes, edges, m, parent, levels=2, root=0, lumps=0.0):
    """nodes: list of (position, radius). Skin modifier + subdivision = organic tube mesh."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(p) for p, _ in nodes], edges, [])
    o = bpy.data.objects.new(name, me)
    COL.objects.link(o)
    sk = o.modifiers.new("Skin", 'SKIN')
    sk.branch_smoothing = 0.6
    sk.use_smooth_shade = True
    for i, (_, r) in enumerate(nodes):
        me.skin_vertices[0].data[i].radius = (r, r) if isinstance(r, (int, float)) else r
        me.skin_vertices[0].data[i].use_root = (i == root)
    subsurf(o, levels)
    if lumps:
        displace(o, lumps, 0.03)
    return link(o, m, parent)


def chain(nodes, start_index):
    """Edges for a simple chain of node indices starting at start_index."""
    return [(start_index + i, start_index + i + 1) for i in range(len(nodes) - 1)]


def curve_obj(name, pts, bevel, m, parent, cyclic=False):
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = bevel
    cu.bevel_resolution = 1
    cu.use_fill_caps = True
    sp = cu.splines.new('POLY')
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (*p, 1.0)
    sp.use_cyclic_u = cyclic
    o = bpy.data.objects.new(name, cu)
    cu.materials.append(m)
    return link(o, None, parent, smooth=False)


def loft(name, rings, m, parent, levels=1, thickness=0.0, lumps=0.0, cap_bottom=False):
    """rings: list of equal-length point lists, top to bottom, each a closed loop."""
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for a, b in zip(vr, vr[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    if cap_bottom:
        bm.faces.new(list(reversed(vr[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm, m, None)
    if thickness:
        solidify(o, thickness)
    if levels:
        subsurf(o, levels)
    if lumps:
        displace(o, lumps, 0.05)
    return link(o, None, parent)


def ring(center, rx, ry, n, f=None, z=None):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        dr, dz = f(a, i) if f else (0.0, 0.0)
        pts.append(Vector((center[0] + rx * (1 + dr) * math.cos(a),
                           center[1] + ry * (1 + dr) * math.sin(a),
                           (center[2] if z is None else z) + dz)))
    return pts


def gauss(p, c, s):
    return math.exp(-((p - Vector(c)).length_squared) / (s * s))


# ---------------------------------------------------------------- skeleton / pose
SPINE = [  # (pos, radius)
    ((0, 0.00, 0.56), 0.10),
    ((0, -0.03, 0.67), 0.098),
    ((0, -0.075, 0.78), 0.11),
    ((0, -0.125, 0.875), 0.122),
    ((0, -0.165, 0.945), 0.105),
    ((0, -0.21, 1.0), 0.05),
    ((0, -0.245, 1.045), 0.045),
]


def spine_y(z):
    pts = [(p[2], p[1]) for p, _ in SPINE]
    if z <= pts[0][0]:
        return pts[0][1]
    for (z0, y0), (z1, y1) in zip(pts, pts[1:]):
        if z0 <= z <= z1:
            return y0 + (y1 - y0) * (z - z0) / (z1 - z0)
    return pts[-1][1]


HEAD_C = Vector((0, -0.31, 1.12))
HEAD_S = 0.135
SPEAR_G = Vector((-0.212, -0.352, 0.598))          # grip point in the right hand
SPEAR_D = Vector((0.12, -0.95, 0.02)).normalized()  # tip direction (the hunch tilts it down ~13 deg)
SHIELD_N = Vector((0.5, -0.85, 0.06)).normalized()  # shield facing
L_PALM = Vector((0.27, -0.375, 0.66))
SHIELD_C = L_PALM + SHIELD_N * 0.045


# ---------------------------------------------------------------- build
root = empty("GoblinHD")
body = empty("Body", root, (0, 0, 0.55))
head = empty("HeadPivot", body, (0, -0.245, 1.045))


def build_torso_arms():
    nodes = list(SPINE)
    edges = chain(SPINE, 0)
    upper = 4  # index of upper chest

    def add_chain(pts, attach):
        nonlocal nodes, edges
        start = len(nodes)
        nodes += pts
        edges.append((attach, start))
        edges += chain(pts, start)
        return start

    # left arm (shield side, goblin's left = +X)
    la = add_chain([((0.14, -0.15, 0.935), 0.05), ((0.2, -0.17, 0.85), 0.038), ((0.25, -0.2, 0.77), 0.042),
                    ((0.265, -0.28, 0.715), 0.036), ((0.27, -0.345, 0.672), 0.025), (tuple(L_PALM), 0.03)], upper)
    lpalm = la + 5
    # left fist: three curled fingers + thumb
    for k, dz in enumerate((-0.016, 0.0, 0.016)):
        kn = L_PALM + Vector((-0.012, -0.022, dz))
        add_chain([(tuple(kn), 0.012), (tuple(kn + Vector((-0.022, -0.01, 0))), 0.011),
                   (tuple(kn + Vector((-0.03, 0.012, 0))), 0.009)], lpalm)
    add_chain([(tuple(L_PALM + Vector((-0.018, -0.005, 0.026))), 0.012),
               (tuple(L_PALM + Vector((-0.035, -0.018, 0.03))), 0.009)], lpalm)

    # right arm (spear side)
    ra = add_chain([((-0.14, -0.15, 0.935), 0.05), ((-0.21, -0.14, 0.85), 0.038), ((-0.27, -0.12, 0.765), 0.042),
                    ((-0.26, -0.2, 0.69), 0.036), ((-0.237, -0.285, 0.628), 0.025), ((-0.228, -0.325, 0.612), 0.03)], upper)
    rpalm = ra + 5
    # fingers wrapping around the spear shaft
    u = (Vector((-1.0, 0.0, 0.7)) - SPEAR_D * SPEAR_D.dot(Vector((-1.0, 0.0, 0.7)))).normalized()
    tips = []
    for k, s in enumerate((-0.022, 0.0, 0.022)):
        pts = []
        for j, ang in enumerate((0, 70, 150, 220)):
            q = SPEAR_G + SPEAR_D * s + (Matrix.Rotation(math.radians(ang), 3, SPEAR_D) @ u) * (0.03 if j == 0 else 0.027)
            pts.append((tuple(q), (0.013, 0.012, 0.011, 0.009)[j]))
        add_chain(pts, rpalm)
        tips.append((Vector(pts[-1][0]), Vector(pts[-1][0]) - Vector(pts[-2][0])))
    thumb = [(tuple(SPEAR_G + SPEAR_D * 0.035 + (Matrix.Rotation(math.radians(a), 3, SPEAR_D) @ u) * 0.03), r)
             for a, r in ((-40, 0.013), (-95, 0.011), (-140, 0.009))]
    add_chain(thumb, rpalm)
    tips.append((Vector(thumb[-1][0]), Vector(thumb[-1][0]) - Vector(thumb[-2][0])))
    o = skin_obj("TorsoArms", nodes, edges, M["skin"], body, levels=2, root=0, lumps=0.004)
    # claws on the spear hand
    for i, (p, d) in enumerate(tips):
        prim('cone', f"Claw_R{i}", M["claw"], p + d.normalized() * 0.008, body, rot=along(d), r1=0.007, r2=0.0, d=0.018, seg=6)
    return o


def build_legs():
    pelvis = ((0, 0.0, 0.56), 0.095)
    nodes = [pelvis]
    edges = []

    def add_chain(pts, attach):
        start = len(nodes)
        nodes.extend(pts)
        edges.append((attach, start))
        edges.extend(chain(pts, start))
        return start

    claw_tips = []
    legs = {
        'L': dict(leg=[((0.085, -0.02, 0.53), 0.064), ((0.108, -0.09, 0.43), 0.055), ((0.125, -0.17, 0.33), 0.047),
                       ((0.126, -0.152, 0.2), 0.039), ((0.125, -0.12, 0.075), 0.027)],
                  heel=((0.125, -0.085, 0.032), 0.032), ball=((0.125, -0.19, 0.026), 0.036),
                  toes=[((0.1, -0.255, 0.017), (0.086, -0.29, 0.012)), ((0.125, -0.262, 0.017), (0.126, -0.305, 0.012)),
                        ((0.15, -0.252, 0.017), (0.162, -0.285, 0.012))]),
        'R': dict(leg=[((-0.085, 0.0, 0.53), 0.064), ((-0.108, 0.03, 0.42), 0.055), ((-0.125, 0.045, 0.31), 0.047),
                       ((-0.13, 0.095, 0.2), 0.039), ((-0.13, 0.15, 0.1), 0.027)],
                  heel=((-0.13, 0.185, 0.078), 0.03), ball=((-0.13, 0.07, 0.028), 0.036),
                  toes=[((-0.105, 0.005, 0.017), (-0.095, -0.03, 0.012)), ((-0.13, -0.002, 0.017), (-0.132, -0.04, 0.012)),
                        ((-0.155, 0.005, 0.017), (-0.167, -0.025, 0.012))]),
    }
    for side, L in legs.items():
        s = add_chain(L['leg'], 0)
        ankle = s + len(L['leg']) - 1
        add_chain([L['heel']], ankle)
        b = add_chain([L['ball']], ankle)
        for t1, t2 in L['toes']:
            add_chain([(t1, 0.014), (t2, 0.011)], b)
            claw_tips.append((Vector(t2), Vector(t2) - Vector(t1)))
    o = skin_obj("Legs", nodes, edges, M["skin"], root, levels=2, root=0, lumps=0.004)
    for i, (p, d) in enumerate(claw_tips):
        prim('cone', f"ToeClaw_{i}", M["claw"], p + d.normalized() * 0.01, root, rot=along(d), r1=0.008, r2=0.0, d=0.02, seg=6)
    # knobby knee caps
    for side, p in (('L', (0.127, -0.205, 0.335)), ('R', (-0.127, 0.012, 0.315))):
        prim('sphere', f"KneeCap_{side}", M["skin"], p, root, r=0.03, seg=12, rings=8)
    return o


# ---- head: a deformed sphere -----------------------------------------------
def mouth_z(x):
    return -0.36 + 0.42 * x * x  # grin curving up at the corners


def head_deform(p):
    """p: point on the unit sphere. Returns (q, mouth_weight) in head units."""
    q = Vector((p.x * 0.95, p.y * 1.12, p.z))
    bumps = [
        ((0.36, -0.82, 0.34), 0.26, (0.03, -0.17, 0.05)),   # brow ridges
        ((-0.36, -0.82, 0.34), 0.26, (-0.03, -0.17, 0.05)),
        ((0.0, -0.95, 0.24), 0.18, (0.0, -0.05, -0.05)),     # furrow
        ((0.36, -0.86, 0.1), 0.17, (0.0, 0.1, 0.0)),         # eye sockets
        ((-0.36, -0.86, 0.1), 0.17, (0.0, 0.1, 0.0)),
        ((0.6, -0.68, -0.08), 0.24, (0.12, -0.08, 0.0)),      # cheekbones
        ((-0.6, -0.68, -0.08), 0.24, (-0.12, -0.08, 0.0)),
        ((0.0, -0.78, -0.72), 0.3, (0.0, -0.26, -0.12)),      # chin
        ((0.66, -0.3, -0.55), 0.3, (0.13, 0.0, -0.05)),       # jaw corners
        ((-0.66, -0.3, -0.55), 0.3, (-0.13, 0.0, -0.05)),
        ((0.0, 0.7, 0.55), 0.55, (0.0, 0.18, 0.12)),          # long cranium
        ((0.0, -0.4, 0.92), 0.4, (0.0, 0.0, -0.08)),          # flatter top
    ]
    for c, s, d in bumps:
        q += Vector(d) * gauss(p, c, s)
    w = 0.0
    if p.y < -0.25:
        dz = p.z - mouth_z(p.x)
        taper = max(0.0, 1.0 - (abs(p.x) / 0.64) ** 4)
        w = math.exp(-(dz / 0.07) ** 2) * taper * min(1.0, (-p.y - 0.25) * 4)
        q.y += 0.24 * w                                                 # carve the grin
        q.y -= 0.05 * math.exp(-((abs(dz) - 0.11) / 0.04) ** 2) * taper  # lips
        q.z += 0.02 * math.exp(-((dz + 0.2) / 0.08) ** 2) * taper        # cheek fold
    return q, w


def head_point(x, z):
    """Head-unit position on the deformed surface for unit-sphere coords (x, z), front side."""
    y = -math.sqrt(max(0.0, 1 - x * x - z * z))
    return head_deform(Vector((x, y, z)))[0]


def to_world(q):
    return HEAD_C + q * HEAD_S


def build_head():
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=34, radius=1.0)
    weights = []
    for v in bm.verts:
        p = v.co.normalized()
        q, w = head_deform(p)
        v.co = to_world(q)
        weights.append(w)
    o = mesh_obj("Head", bm, M["skin"], None)
    o.data.materials.append(M["mouth"])
    # assign the mouth interior once both material slots exist (to_mesh clamps indices otherwise)
    for poly in o.data.polygons:
        mw = sum(weights[i] for i in poly.vertices) / len(poly.vertices)
        poly.material_index = 1 if mw > 0.42 else 0
    subsurf(o, 1)
    displace(o, 0.0025, 0.025)
    link(o, None, head)

    # teeth: jagged rows along the grin
    i = 0
    for x in [-0.5 + 0.1 * k for k in range(11)]:
        mz = mouth_z(x)
        for upper in (True, False):
            if not upper and abs(x) > 0.42:
                continue
            base = head_point(x, mz + (0.055 if upper else -0.055)) + Vector((0, 0.07, 0))
            length = rng.uniform(0.13, 0.2) * (1.0 - 0.35 * abs(x))
            tip = base + Vector((0, -0.09, -length if upper else length))
            d = tip - base
            prim('cone', f"Tooth_{i}", M["tooth"], to_world(base + d * 0.5), head, rot=along(d),
                 r1=HEAD_S * rng.uniform(0.055, 0.075), r2=0.0, d=d.length * HEAD_S, seg=6)
            i += 1

    # nose: a sphere swept along a hooked path (bridge -> bulb -> hook pointing down)
    path = [Vector(p) for p in ((0, -0.86, 0.24), (0, -1.15, 0.16), (0, -1.42, 0.04), (0, -1.62, -0.12),
                                 (0, -1.68, -0.3), (0, -1.6, -0.42))]
    radii = [0.16, 0.15, 0.16, 0.17, 0.12, 0.05]

    def sample(t):
        f = t * (len(path) - 1)
        i = min(int(f), len(path) - 2)
        k = f - i
        return path[i].lerp(path[i + 1], k), radii[i] + (radii[i + 1] - radii[i]) * k

    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=16, radius=1.0)
    for v in bm.verts:
        t = (1.0 - v.co.z) / 2.0
        c, r = sample(t)
        c2, _ = sample(min(1.0, t + 0.02))
        c1, _ = sample(max(0.0, t - 0.02))
        tang = (c2 - c1).normalized()
        side = Vector((1, 0, 0))
        up = tang.cross(side).normalized()
        rr = math.sqrt(max(0.0, 1 - v.co.z ** 2))
        ang = math.atan2(v.co.y, v.co.x)
        flare = 1.0 + 0.35 * math.exp(-((t - 0.62) / 0.12) ** 2) * abs(math.cos(ang))  # nostril wings
        q = c + (side * math.cos(ang) * flare + up * math.sin(ang)) * r * rr
        v.co = to_world(q)
    no = mesh_obj("Nose", bm, M["skin"], None)
    subsurf(no, 1)
    displace(no, 0.0015, 0.02)
    link(no, None, head)

    # eyes: sclera, iris, slit pupil, squinting lids
    for s, side in ((1, 'L'), (-1, 'R')):
        ec = to_world(Vector((s * 0.36, -0.99, 0.1)))
        re = 0.19 * HEAD_S
        prim('sphere', f"Eye_{side}", M["sclera"], ec, head, r=re, seg=20, rings=14)
        fwd = Vector((s * 0.12, -1.0, 0.05)).normalized()
        prim('sphere', f"Iris_{side}", M["iris"], ec + fwd * re * 0.86, head, rot=along(fwd), scale=(1, 1, 0.4), r=re * 0.62, seg=16, rings=10)
        prim('sphere', f"Pupil_{side}", M["pupil"], ec + fwd * re * 1.03, head, rot=along(fwd), scale=(0.32, 1.0, 0.25), r=re * 0.5, seg=12, rings=8)
        for lid, keep, tilt in (("Upper", lambda z: z > 0.3, 24), ("Lower", lambda z: z < -0.6, -12)):
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=16, radius=re * (1.14 if lid == "Upper" else 1.1))
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v.co.z / re)], context='VERTS')
            rot = Matrix.Rotation(math.radians(tilt), 3, 'X')
            if lid == "Upper":
                rot = Matrix.Rotation(math.radians(-s * 22), 3, 'Y') @ rot  # angry slant
            bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=rot)
            bmesh.ops.translate(bm, verts=bm.verts, vec=ec)
            lo = mesh_obj(f"Lid{lid}_{side}", bm, M["skin"], None)
            solidify(lo, 0.003)
            subsurf(lo, 1)
            link(lo, None, head)


def build_ears():
    for s, side in ((1, 'L'), (-1, 'R')):
        base = to_world(Vector((s * 0.86, 0.02, 0.2)))
        axis = Vector((s * 0.92, 0.32, 0.22)).normalized()
        across = Vector((0, 0, 1)) - axis * axis.z
        across.normalize()
        normal = axis.cross(across) * s  # points forward-ish (inner side of the ear)
        L, W = 0.34, 0.1
        nu, nv = 14, 9
        bm = bmesh.new()
        grid = []
        for i in range(nu + 1):
            t = i / nu
            w = W * (1 - t ** 1.25) * (0.7 + 0.55 * math.sin(math.pi * t))
            row = []
            for j in range(nv + 1):
                v = -1 + 2 * j / nv
                cup = -0.35 * W * (1 - v * v) * math.sin(math.pi * min(1.0, t * 1.15))
                droop = -0.18 * L * t * t
                p = base + axis * (L * t) + across * (w * v * 0.5) + normal * cup + Vector((0, 0, droop))
                # a bite-shaped nick in the left ear
                if side == 'L' and 0.45 < t < 0.6 and v > 0.6:
                    p -= across * (w * 0.25)
                row.append(bm.verts.new(p))
            grid.append(row)
        for i in range(nu):
            for j in range(nv):
                bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        o = mesh_obj(f"Ear_{side}", bm, M["skin"], None)
        solidify(o, 0.008)
        subsurf(o, 1)
        bpy.context.view_layer.update()
        # origin at the base so the game can twitch it
        cur = bpy.context.scene.cursor.location.copy()
        bpy.context.scene.cursor.location = base
        for x in bpy.context.view_layer.objects:
            x.select_set(False)
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        bpy.context.scene.cursor.location = cur
        link(o, None, head)


def build_hood():
    r = HEAD_S * 1.13
    center = HEAD_C + Vector((0, 0.05, 0.0))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=36, v_segments=24, radius=r)
    kill = []
    for f in bm.faces:
        n = f.calc_center_median().normalized()
        # face opening (the brim comes down over the forehead) + neck hole
        if (n.y < -0.42 and -0.85 < n.z < 0.5) or n.z < -0.62:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    for v in bm.verts:
        n = v.co.normalized()
        k = max(0.0, n.y) * max(0.0, n.z + 0.3)
        v.co += Vector((0, 1.25 * r * k * k, 0.15 * r * k * k))            # pointed tip
        ang = math.atan2(n.x, n.y)
        v.co += n * r * 0.035 * math.sin(ang * 9) * max(0.0, -n.z + 0.3)   # folds near the bottom
        if n.y < -0.15:
            v.co.x *= 1.07                                                   # flared opening
            v.co.z += r * 0.06 * max(0.0, n.z)                              # overhanging brim
        v.co += center
    o = mesh_obj("Hood", bm, M["hood"], None)
    solidify(o, 0.012, 1.0)
    subsurf(o, 1)
    displace(o, 0.004, 0.04)
    link(o, None, head)


def build_cowl():
    rings = []
    spec = [(1.06, 0.08, 0.075, 0.0), (1.02, 0.13, 0.12, 0.0), (0.97, 0.2, 0.16, 0.25), (0.92, 0.25, 0.19, 0.6),
            (0.875, 0.275, 0.205, 1.0)]
    n = 40
    for zi, (z, rx, ry, fold) in enumerate(spec):
        cy = spine_y(z) - 0.03

        def f(a, i, fold=fold, last=(zi == len(spec) - 1)):
            dr = 0.06 * fold * math.sin(a * 8 + 0.6)
            dz = 0.0
            if last:
                dz = -rng.uniform(0.0, 0.07) if i % 2 == 0 else rng.uniform(0.0, 0.015)
            return dr, dz
        rings.append(ring((0, cy, z), rx, ry, n, f))
    loft("Cowl", rings, M["hood"], body, levels=1, thickness=0.01, lumps=0.004)


def build_tunic():
    spec = [(0.955, 0.13, 0.115), (0.9, 0.152, 0.127), (0.82, 0.142, 0.118), (0.72, 0.122, 0.104),
            (0.64, 0.128, 0.11), (0.57, 0.155, 0.135), (0.5, 0.18, 0.152), (0.44, 0.2, 0.168)]
    n = 44
    rings = []
    for zi, (z, rx, ry) in enumerate(spec):
        cy = spine_y(z) + 0.005
        hem = zi == len(spec) - 1
        lower = max(0.0, (0.62 - z) / 0.18)

        def f(a, i, hem=hem, lower=lower):
            dr = 0.07 * lower * math.sin(a * 7 + 1.0) + 0.03 * lower * math.sin(a * 13)
            dz = 0.0
            if hem:  # torn triangular hem
                dz = -rng.uniform(0.02, 0.09) if i % 3 == 0 else rng.uniform(-0.01, 0.02)
            return dr, dz
        rings.append(ring((0, cy, z), rx, ry, n, f))
    loft("Tunic", rings, M["cloth"], body, levels=1, thickness=0.008, lumps=0.003)


def build_belt():
    z, rx, ry = 0.625, 0.14, 0.118
    cy = spine_y(z) + 0.005
    for strand in range(2):
        pts = []
        for k in range(361):
            t = k / 360
            a = 2 * math.pi * t
            tw = 2 * math.pi * t * 34 + strand * math.pi
            rad = 1 + 0.045 * math.cos(tw)
            pts.append((rx * rad * math.cos(a), cy + ry * rad * math.sin(a), z + 0.006 * math.sin(tw)))
        curve_obj(f"BeltStrand_{strand}", pts, 0.0065, M["rope"], body, cyclic=True)
    # knot + hanging ends at the front
    knot = Vector((0.05, cy - ry * 0.95, z))
    prim('sphere', "BeltKnot", M["rope"], knot, body, scale=(1.2, 0.8, 1), r=0.018, seg=12, rings=8)
    for e, (dx, length) in enumerate(((0.012, 0.13), (-0.01, 0.1))):
        pts = [(knot.x + dx + 0.008 * math.sin(k * 0.9), knot.y - 0.006 - 0.004 * k / 10, knot.z - length * k / 10) for k in range(11)]
        curve_obj(f"BeltEnd_{e}", pts, 0.0055, M["rope"], body)
    # leather pouch on the hip
    pc = Vector((0.135, cy - 0.02, 0.565))
    p = prim('cube', "Pouch", M["leather"], pc, body, rot=(0, 0, math.radians(-25)), scale=(0.075, 0.04, 0.075))
    subsurf(p, 2)
    flap = prim('cube', "PouchFlap", M["leather"], pc + Vector((0.004, -0.012, 0.022)), body, rot=(math.radians(-8), 0, math.radians(-25)), scale=(0.08, 0.028, 0.04))
    subsurf(flap, 2)
    prim('sphere', "PouchButton", M["bone"], pc + Vector((0.012, -0.03, 0.01)), body, r=0.007, seg=8, rings=6)


def build_bracers():
    arms = {'L': (Vector((0.25, -0.2, 0.77)), Vector((0.27, -0.345, 0.672))),
            'R': (Vector((-0.27, -0.12, 0.765)), Vector((-0.237, -0.285, 0.628)))}
    for side, (el, wr) in arms.items():
        d = (wr - el)
        a, b = el + d * 0.28, el + d * 0.92
        ln = (b - a).length
        o = prim('cyl', f"Bracer_{side}", M["leather"], (a + b) / 2, body, rot=along(b - a), r=0.047, d=ln, seg=20)
        # flare toward the wrist
        for v in o.data.vertices:
            k = (v.co.z / ln) + 0.5
            v.co.x *= 1.0 + 0.18 * k
            v.co.y *= 1.0 + 0.18 * k
        solidify(o, 0.004)
        subsurf(o, 1)
        for i, t in enumerate((0.3, 0.7)):
            c = a + (b - a) * t
            prim('torus', f"BracerStrap_{side}{i}", M["leather"], c, body, rot=along(b - a), scale=(1, 1, 1.6),
                 R=0.051 + 0.008 * t, r=0.0045, seg=24, mseg=6)
            prim('cube', f"BracerBuckle_{side}{i}", M["metal"], c + Vector((0, 0, 0.053 + 0.008 * t)), body,
                 rot=along(b - a), scale=(0.016, 0.004, 0.012))


def build_spear():
    G, d = SPEAR_G, SPEAR_D
    butt, front = G - d * 0.72, G + d * 0.5
    shaft = prim('cyl', "Spear", M["wood"], (butt + front) / 2, body, rot=along(d), r=0.015, d=(front - butt).length, seg=12)
    displace(shaft, 0.0015, 0.02)
    prim('cone', "SpearButt", M["metal"], butt - d * 0.015, body, rot=along(-d), r1=0.017, r2=0.006, d=0.035, seg=10)
    prim('cone', "SpearSocket", M["metal"], front + d * 0.03, body, rot=along(d), r1=0.019, r2=0.014, d=0.08, seg=12)
    # leaf blade with a diamond cross-section
    side = d.cross(Vector((0, 0, 1))).normalized()
    up = side.cross(d).normalized()
    base = front + d * 0.065
    Lb, W, T = 0.19, 0.036, 0.007
    bm = bmesh.new()
    rings = []
    steps = 14
    for k in range(steps):
        t = k / steps
        w = W * (math.sin(t / 0.32 * math.pi / 2) if t < 0.32 else math.cos((t - 0.32) / 0.68 * math.pi / 2)) + 0.012 * (1 - t)
        th = T * (1 - 0.7 * t) + 0.004
        c = base + d * (Lb * t)
        rings.append([bm.verts.new(c + side * w), bm.verts.new(c + up * th), bm.verts.new(c - side * w), bm.verts.new(c - up * th)])
    tip = bm.verts.new(base + d * Lb)
    for a, b in zip(rings, rings[1:]):
        for i in range(4):
            bm.faces.new((a[i], a[(i + 1) % 4], b[(i + 1) % 4], b[i]))
    for i in range(4):
        bm.faces.new((rings[-1][i], rings[-1][(i + 1) % 4], tip))
    bm.faces.new(list(reversed(rings[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh_obj("SpearBlade", bm, M["metal"], body, smooth=False)
    # leather binding below the socket
    a = front - d * 0.02
    pts = []
    perp = side
    for k in range(121):
        t = k / 120
        ang = 2 * math.pi * 9 * t
        rot = Matrix.Rotation(ang, 3, d)
        pts.append(tuple(a - d * 0.06 * t + (rot @ perp) * 0.0175))
    curve_obj("SpearBinding", pts, 0.0035, M["leather"], body)
    # a torn cloth strip tied below the blade
    strip = [tuple(a - d * 0.03 + Vector((0.004 * math.sin(k), -0.004 * k / 8, -0.012 * k))) for k in range(9)]
    curve_obj("SpearRag", strip, 0.006, M["cloth"], body)


def build_shield():
    n = SHIELD_N
    ex = Vector((0, 0, 1)).cross(n).normalized()
    ey = n.cross(ex).normalized()
    basis = Matrix((ex, ey, n)).transposed()
    C = SHIELD_C
    R, T = 0.22, 0.018

    def W(x, y, z=0.0):
        return C + basis @ Vector((x, y, z))

    planks = 5
    pw = 2 * R / planks
    for i in range(planks):
        x0, x1 = -R + i * pw + 0.003, -R + (i + 1) * pw - 0.003
        xs = [x0 + (x1 - x0) * k / 6 for k in range(7)]
        outline = [(x, -math.sqrt(max(0.0, R * R - x * x))) for x in xs] + [(x, math.sqrt(max(0.0, R * R - x * x))) for x in reversed(xs)]
        jitter = rng.uniform(-0.002, 0.002)
        bm = bmesh.new()
        front = [bm.verts.new(W(x, y, T + jitter)) for x, y in outline]
        back = [bm.verts.new(W(x, y, 0.0)) for x, y in outline]
        bm.faces.new(front)
        bm.faces.new(list(reversed(back)))
        m = len(outline)
        for k in range(m):
            bm.faces.new((front[k], back[k], back[(k + 1) % m], front[(k + 1) % m]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        o = mesh_obj(f"ShieldPlank_{i}", bm, M["wood"], body, smooth=False)
        bv = o.modifiers.new("Bevel", 'BEVEL')
        bv.width = 0.002
        bv.segments = 1
    rim = prim('torus', "ShieldRim", M["metal"], W(0, 0, T * 0.5), body, rot=n.to_track_quat('Z', 'Y').to_euler(),
               scale=(1, 1, 1.5), R=R, r=0.011, seg=48, mseg=8)
    for k in range(18):
        a = 2 * math.pi * k / 18
        prim('sphere', f"ShieldRivet_{k}", M["metal"], W((R - 0.016) * math.cos(a), (R - 0.016) * math.sin(a), T + 0.003), body, r=0.0055, seg=8, rings=5)
    for j, y in enumerate((-0.085, 0.085)):
        half = math.sqrt(R * R - y * y) - 0.012
        prim('cube', f"ShieldStrap_{j}", M["metal"], W(0, y, T + 0.002), body, rot=n.to_track_quat('Z', 'Y').to_euler(),
             scale=(2 * half, 0.02, 0.004))
        for x in (-half + 0.01, -0.07, 0.07, half - 0.01):
            prim('sphere', f"StrapRivet_{j}_{x:.2f}", M["metal"], W(x, y, T + 0.006), body, r=0.004, seg=6, rings=4)
    boss = prim('sphere', "ShieldBoss", M["metal"], W(0, 0, T), body, rot=n.to_track_quat('Z', 'Y').to_euler(),
                scale=(1, 1, 0.55), r=0.055, seg=20, rings=12)
    # bone horns lashed to the face
    for h, (bx, by, sx) in enumerate(((-0.1, -0.06, -1), (0.1, -0.075, 1))):
        pts = [((bx, by, T + 0.01), 0.02), ((bx + sx * 0.03, by - 0.03, T + 0.06), 0.017),
               ((bx + sx * 0.04, by - 0.075, T + 0.11), 0.011), ((bx + sx * 0.025, by - 0.11, T + 0.15), 0.004)]
        nodes = [(tuple(W(*p)), r) for p, r in pts]
        skin_obj(f"ShieldHorn_{h}", nodes, [(0, 1), (1, 2), (2, 3)], M["bone"], body, levels=2, root=0)


build_torso_arms()
build_legs()
build_head()
build_ears()
build_hood()
build_cowl()
build_tunic()
build_belt()
build_bracers()
build_spear()
build_shield()

# stronger hunch: tip the whole upper body forward at the hips, head tilted back to keep eyeing you
body.rotation_euler = (math.radians(13), 0, 0)
head.rotation_euler = (math.radians(-15), 0, 0)

for me in list(bpy.data.meshes):
    if me.users == 0:
        bpy.data.meshes.remove(me)
for cu in list(bpy.data.curves):
    if cu.users == 0:
        bpy.data.curves.remove(cu)

root.location = DISPLAY_OFFSET
bpy.context.view_layer.update()

# triangle count of the evaluated (modifier-applied) model
dg = bpy.context.evaluated_depsgraph_get()
TRIS = 0
for o in COL.objects:
    if o.type in ('MESH', 'CURVE'):
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        TRIS += len(me.loop_triangles)
        ev.to_mesh_clear()
