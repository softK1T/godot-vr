#!/usr/bin/env python3
from __future__ import annotations

import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/low_poly_fence"
SCENES = OUT / "scenes"
OUT.mkdir(parents=True, exist_ok=True)
SCENES.mkdir(parents=True, exist_ok=True)

MTL = """# Low-poly fence materials — generated for Godot
newmtl Wood_Dark
Ka 0.12 0.07 0.03
Kd 0.29 0.15 0.065
Ks 0.02 0.02 0.02
Ns 8
d 1.0
illum 2

newmtl Wood_Mid
Ka 0.16 0.09 0.04
Kd 0.43 0.23 0.095
Ks 0.025 0.02 0.015
Ns 8
d 1.0
illum 2

newmtl Wood_Light
Ka 0.20 0.12 0.055
Kd 0.57 0.34 0.15
Ks 0.03 0.025 0.02
Ns 8
d 1.0
illum 2

newmtl Wood_Cut
Ka 0.23 0.15 0.075
Kd 0.68 0.47 0.24
Ks 0.025 0.02 0.015
Ns 6
d 1.0
illum 2

newmtl Iron
Ka 0.025 0.03 0.032
Kd 0.075 0.085 0.088
Ks 0.18 0.18 0.18
Ns 42
d 1.0
illum 2
"""
(OUT / "fence_materials.mtl").write_text(MTL, encoding="utf-8")


def rot_xyz(p, r):
    x, y, z = p
    rx, ry, rz = r
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)
    y, z = y * cx - z * sx, y * sx + z * cx
    x, z = x * cy + z * sy, -x * sy + z * cy
    x, y = x * cz - y * sz, x * sz + y * cz
    return x, y, z


class Obj:
    def __init__(self, name):
        self.name = name
        self.v = []
        self.groups = []

    def add_mesh(self, name, verts, faces, mat="Wood_Mid"):
        start = len(self.v) + 1
        self.v.extend(verts)
        self.groups.append((name, mat, [[start + i for i in f] for f in faces]))

    def box(self, name, center, size, mat="Wood_Mid", rot=(0.0, 0.0, 0.0), skew=(0.0, 0.0)):
        cx, cy, cz = center
        sx, sy, sz = size
        dx, dz = skew
        local = [
            (-sx/2, -sy/2, -sz/2), (sx/2, -sy/2, -sz/2),
            (sx/2, sy/2, -sz/2), (-sx/2, sy/2, -sz/2),
            (-sx/2, -sy/2, sz/2), (sx/2, -sy/2, sz/2),
            (sx/2 + dx, sy/2, sz/2 + dz), (-sx/2 + dx, sy/2, sz/2 + dz),
        ]
        verts = []
        for p in local:
            x, y, z = rot_xyz(p, rot)
            verts.append((x + cx, y + cy, z + cz))
        faces = [(0,3,2,1), (4,5,6,7), (0,1,5,4), (3,7,6,2), (1,2,6,5), (0,4,7,3)]
        self.add_mesh(name, verts, faces, mat)

    def post(self, name, x, z=0.0, height=1.68, mat="Wood_Dark"):
        self.box(name + "_shaft", (x, (height - 0.16)/2, z), (0.20, height - 0.16, 0.20), mat, skew=(0.018, -0.012))
        yb = height - 0.16
        s = 0.215
        verts = [(x-s/2,yb,z-s/2),(x+s/2,yb,z-s/2),(x+s/2,yb,z+s/2),(x-s/2,yb,z+s/2),(x,yb+0.16,z)]
        faces = [(0,3,2,1),(0,1,4),(1,2,4),(2,3,4),(3,0,4)]
        self.add_mesh(name + "_cap", verts, faces, "Wood_Cut")

    def picket(self, name, x, y0=0.12, z=-0.10, height=1.35, width=0.20, lean=0.0, mat="Wood_Mid"):
        body_top = y0 + height - 0.18
        x0, x1 = -width/2, width/2
        points = [(x0,y0),(x1,y0),(x1,body_top),(0.0,y0+height),(x0,body_top)]
        depth = 0.085
        verts = []
        for zz in (-depth/2, depth/2):
            for px, py in points:
                # Rotate in XY around bottom-center to create handmade lean.
                qx = px * math.cos(lean) - (py-y0) * math.sin(lean)
                qy = px * math.sin(lean) + (py-y0) * math.cos(lean) + y0
                verts.append((qx+x,qy,zz+z))
        faces = [(0,4,3,2,1),(5,6,7,8,9)]
        for i in range(5):
            j = (i+1)%5
            faces.append((i,j,j+5,i+5))
        self.add_mesh(name, verts, faces, mat)

    def cylinder(self, name, center, radius, height, mat="Iron", sides=8, axis="z"):
        cx, cy, cz = center
        verts=[]
        for a in range(sides):
            t=2*math.pi*a/sides
            p=(radius*math.cos(t),radius*math.sin(t))
            if axis=="z": verts.append((cx+p[0],cy+p[1],cz-height/2))
            else: verts.append((cx-height/2,cy+p[0],cz+p[1]))
        for a in range(sides):
            t=2*math.pi*a/sides
            p=(radius*math.cos(t),radius*math.sin(t))
            if axis=="z": verts.append((cx+p[0],cy+p[1],cz+height/2))
            else: verts.append((cx+height/2,cy+p[0],cz+p[1]))
        faces=[tuple(range(sides-1,-1,-1)),tuple(range(sides,2*sides))]
        for i in range(sides):
            j=(i+1)%sides
            faces.append((i,j,j+sides,i+sides))
        self.add_mesh(name,verts,faces,mat)

    def save(self):
        p = OUT / f"{self.name}.obj"
        lines = [f"# {self.name} — procedural low-poly modular fence", "mtllib fence_materials.mtl", f"o {self.name}"]
        lines += [f"v {x:.6f} {y:.6f} {z:.6f}" for x,y,z in self.v]
        for group, mat, faces in self.groups:
            lines += [f"g {group}", f"usemtl {mat}", "s off"]
            lines += ["f " + " ".join(map(str, f)) for f in faces]
        p.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return p


def add_straight(o, length=3.0, broken=False):
    o.post("post_left", 0.0)
    o.post("post_right", length, height=1.64)
    if broken:
        o.box("rail_low_left", (0.63,0.58,0.0),(1.16,0.13,0.12),"Wood_Dark",rot=(0,0,math.radians(-2)))
        o.box("rail_low_right", (2.33,0.50,0.0),(1.15,0.13,0.12),"Wood_Dark",rot=(0,0,math.radians(5)))
        o.box("rail_high_left", (0.58,1.08,0.0),(1.07,0.13,0.12),"Wood_Dark",rot=(0,0,math.radians(2)))
        o.box("rail_high_right", (2.33,0.98,0.0),(1.14,0.13,0.12),"Wood_Dark",rot=(0,0,math.radians(-7)))
        picks=[(0.35,1.28,-1.0),(0.78,1.36,1.3),(1.20,0.76,-3.2),(1.85,1.10,4.5),(2.31,1.28,-1.8),(2.67,1.18,2.2)]
    else:
        o.box("rail_low", (length/2,0.57,0.0),(length-0.18,0.13,0.12),"Wood_Dark",rot=(0,0,math.radians(-0.7)))
        o.box("rail_high", (length/2,1.08,0.0),(length-0.18,0.13,0.12),"Wood_Dark",rot=(0,0,math.radians(0.6)))
        count = 6 if length > 2 else 3
        picks=[]
        for i in range(count):
            x=(i+1)*length/(count+1)
            heights=[1.31,1.39,1.34,1.42,1.30,1.37]
            leans=[-1.2,0.8,-0.4,1.4,-0.8,0.5]
            picks.append((x,heights[i],leans[i]))
    mats=["Wood_Mid","Wood_Light","Wood_Mid","Wood_Dark","Wood_Light","Wood_Mid"]
    for i,(x,h,a) in enumerate(picks):
        o.picket(f"picket_{i+1}",x,height=h,lean=math.radians(a),mat=mats[i%len(mats)])


def make_straight(name,length,broken=False):
    o=Obj(name); add_straight(o,length,broken); return o.save()


def make_post():
    o=Obj("fence_post"); o.post("post",0.0); return o.save()


def make_corner():
    o=Obj("fence_corner_3m")
    # +X side
    add_straight(o,3.0,False)
    # +Z side shares the origin post; rotate components manually into Z axis.
    o.post("post_z_end",0.0,3.0,height=1.66)
    for n,y,ang in (("rail_z_low",0.57,-0.5),("rail_z_high",1.08,0.5)):
        o.box(n,(0.0,y,1.5),(2.82,0.13,0.12),"Wood_Dark",rot=(0,math.pi/2,math.radians(ang)))
    hs=[1.36,1.30,1.41,1.33,1.38,1.31]
    for i in range(6):
        z=(i+1)*3/7
        # Build picket at origin then rotate by using a thin box + pyramid-like cap silhouette along Z.
        o.box(f"z_picket_{i+1}_body",(-0.10,0.12+(hs[i]-0.18)/2,z),(0.085,hs[i]-0.18,0.20),["Wood_Light","Wood_Mid","Wood_Dark"][i%3],rot=(0,0,math.radians((i%3-1)*0.8)))
        y=0.12+hs[i]-0.18; w=.20; d=.085
        verts=[(-.10-d/2,y,z-w/2),(-.10+d/2,y,z-w/2),(-.10+d/2,y,z+w/2),(-.10-d/2,y,z+w/2),(-.10,y+.18,z)]
        o.add_mesh(f"z_picket_{i+1}_tip",verts,[(0,3,2,1),(0,1,4),(1,2,4),(2,3,4),(3,0,4)],"Wood_Cut")
    return o.save()


def make_gate():
    o=Obj("fence_gate_3m")
    o.post("post_left",0.0,height=1.76); o.post("post_right",3.0,height=1.74)
    # Gate leaf frame, slightly inset to read clearly as a separate element.
    o.box("gate_top",(1.5,1.27,-0.01),(2.66,.14,.14),"Wood_Dark")
    o.box("gate_bottom",(1.5,.37,-0.01),(2.66,.14,.14),"Wood_Dark")
    o.box("gate_left",(.22,.82,-0.01),(.14,1.04,.14),"Wood_Dark")
    o.box("gate_right",(2.78,.82,-0.01),(.14,1.04,.14),"Wood_Dark")
    o.box("diagonal_brace",(1.5,.82,-.10),(2.70,.12,.09),"Wood_Mid",rot=(0,0,math.radians(19.5)))
    for i,x in enumerate([.45,.86,1.27,1.68,2.09,2.50]):
        o.picket(f"gate_picket_{i+1}",x,y0=.25,z=-.11,height=1.28,width=.19,lean=math.radians([-.5,.7,-.8,.4,-.4,.6][i]),mat=["Wood_Mid","Wood_Light","Wood_Mid"][i%3])
    for i,y in enumerate((.52,1.10)):
        o.box(f"hinge_plate_{i+1}",(.18,y,-.19),(.10,.16,.035),"Iron")
        o.cylinder(f"hinge_pin_{i+1}",(.12,y,-.19),.035,.20,"Iron",8,"z")
    o.box("latch_plate",(2.82,.92,-.19),(.14,.12,.035),"Iron")
    o.box("latch_handle",(2.70,.92,-.23),(.32,.045,.045),"Iron")
    return o.save()


assets = [
    make_straight("fence_straight_3m",3.0),
    make_straight("fence_straight_1_5m",1.5),
    make_straight("fence_broken_3m",3.0,True),
    make_corner(), make_gate(), make_post(),
]

scene_specs = {
    "fence_straight_3m": [("main", (1.5,.82,0), (3.18,1.65,.34))],
    "fence_straight_1_5m": [("main", (.75,.82,0), (1.68,1.65,.34))],
    "fence_broken_3m": [("main", (1.5,.82,0), (3.18,1.65,.34))],
    "fence_gate_3m": [("gate", (1.5,.82,0), (3.18,1.76,.40))],
    "fence_post": [("post", (0,.84,0), (.24,1.72,.24))],
    "fence_corner_3m": [("x_arm", (1.5,.82,0), (3.18,1.65,.34)), ("z_arm", (0,.82,1.5), (.34,1.65,3.18))],
}
for name, cols in scene_specs.items():
    lines=["[gd_scene load_steps=%d format=3]" % (2+len(cols)),"",f'[ext_resource type="Mesh" path="res://assets/models/low_poly_fence/{name}.obj" id="1_mesh"]',""]
    for i,(cn,pos,size) in enumerate(cols,1):
        lines += [f'[sub_resource type="BoxShape3D" id="BoxShape3D_{i}"]',f'size = Vector3({size[0]}, {size[1]}, {size[2]})',""]
    lines += [f'[node name="{name}" type="Node3D"]','', '[node name="Mesh" type="MeshInstance3D" parent="."]','mesh = ExtResource("1_mesh")','', '[node name="StaticBody3D" type="StaticBody3D" parent="."]']
    for i,(cn,pos,size) in enumerate(cols,1):
        lines += ["",f'[node name="Collision_{cn}" type="CollisionShape3D" parent="StaticBody3D"]',f'position = Vector3({pos[0]}, {pos[1]}, {pos[2]})',f'shape = SubResource("BoxShape3D_{i}")']
    (SCENES/f"{name}.tscn").write_text("\n".join(lines)+"\n",encoding="utf-8")

preview = """[gd_scene load_steps=7 format=3]

[ext_resource type="PackedScene" path="res://assets/models/low_poly_fence/scenes/fence_straight_3m.tscn" id="1"]
[ext_resource type="PackedScene" path="res://assets/models/low_poly_fence/scenes/fence_straight_1_5m.tscn" id="2"]
[ext_resource type="PackedScene" path="res://assets/models/low_poly_fence/scenes/fence_corner_3m.tscn" id="3"]
[ext_resource type="PackedScene" path="res://assets/models/low_poly_fence/scenes/fence_gate_3m.tscn" id="4"]
[ext_resource type="PackedScene" path="res://assets/models/low_poly_fence/scenes/fence_broken_3m.tscn" id="5"]
[ext_resource type="PackedScene" path="res://assets/models/low_poly_fence/scenes/fence_post.tscn" id="6"]

[node name="FencePackPreview" type="Node3D"]

[node name="Straight3m" parent="." instance=ExtResource("1")]

[node name="Straight1_5m" parent="." instance=ExtResource("2")]
position = Vector3(0, 0, 3)

[node name="Corner3m" parent="." instance=ExtResource("3")]
position = Vector3(5, 0, 0)

[node name="Gate3m" parent="." instance=ExtResource("4")]
position = Vector3(0, 0, 6)

[node name="Broken3m" parent="." instance=ExtResource("5")]
position = Vector3(5, 0, 6)

[node name="Post" parent="." instance=ExtResource("6")]
position = Vector3(5, 0, 3)
"""
(SCENES/"fence_pack_preview.tscn").write_text(preview,encoding="utf-8")

readme = """# Low-poly modular fence pack

Procedurally generated rustic wooden fence set for Godot 4.

## Included pieces

- `fence_straight_3m.obj` — full 3 m segment
- `fence_straight_1_5m.obj` — half segment
- `fence_corner_3m.obj` — L corner with two 3 m arms
- `fence_gate_3m.obj` — closed gate with iron hinges and latch
- `fence_broken_3m.obj` — damaged variant
- `fence_post.obj` — standalone snap/end post
- `scenes/*.tscn` — ready-to-instance Godot scenes with simple static collisions
- `scenes/fence_pack_preview.tscn` — all elements laid out for inspection

## Scale and snapping

- Units are metres; Y is up.
- Straight modules run from X=0 to X=3 (or X=1.5 for the half piece).
- The corner extends toward +X and +Z.
- Pivots sit at ground level on the left/corner post, so modular placement is easy on a 1.5 m grid.
- Materials are embedded through `fence_materials.mtl`; no textures are required.

## Regenerate

Run `python3 tools/generate_fence_pack.py` from the project root.
"""
(OUT/"README.md").write_text(readme,encoding="utf-8")

print(f"Generated {len(assets)} OBJ models, {len(scene_specs)+1} Godot scenes, materials and README in {OUT}")
