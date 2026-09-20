#!/usr/bin/env python3
from __future__ import annotations
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/low_poly_farm_beds"
SCENES = OUT / "scenes"
OUT.mkdir(parents=True, exist_ok=True)
SCENES.mkdir(parents=True, exist_ok=True)

(OUT / "farm_beds_materials.mtl").write_text("""# Texture-free low-poly farm materials
newmtl Soil_Dark
Kd 0.18 0.085 0.035
Ns 4
newmtl Soil_Mid
Kd 0.29 0.135 0.055
Ns 4
newmtl Soil_Light
Kd 0.40 0.205 0.085
Ns 4
newmtl Wood_Dark
Kd 0.27 0.135 0.055
Ns 6
newmtl Wood_Light
Kd 0.48 0.275 0.105
Ns 6
newmtl Leaf_Dark
Kd 0.12 0.31 0.09
Ns 5
newmtl Leaf_Mid
Kd 0.22 0.49 0.13
Ns 5
newmtl Leaf_Light
Kd 0.39 0.66 0.18
Ns 5
newmtl Carrot
Kd 0.92 0.33 0.045
Ns 7
newmtl Stone
Kd 0.34 0.32 0.28
Ns 5
""", encoding="utf-8")

class Obj:
    def __init__(self, name):
        self.name=name; self.vertices=[]; self.groups=[]
    def mesh(self,name,verts,faces,mat):
        k=len(self.vertices)+1; self.vertices += verts
        self.groups.append((name,mat,[[k+i for i in f] for f in faces]))
    def box(self,name,c,s,mat="Soil_Mid",yaw=0.0):
        cx,cy,cz=c; x,y,z=s[0]/2,s[1]/2,s[2]/2
        q=[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]
        co,si=math.cos(yaw),math.sin(yaw); v=[]
        for a,b,d in q:v.append((cx+a*co+d*si,cy+b,cz-a*si+d*co))
        self.mesh(name,v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(1,2,6,5),(0,4,7,3)],mat)
    def mound(self,name,x0,z0,w,d,height=.16,mat="Soil_Mid"):
        # Chamfered, slightly irregular 12-vertex soil mound with a broad plantable top.
        inset=.10
        bottom=[(x0,0,z0),(x0+w,0,z0),(x0+w,0,z0+d),(x0,0,z0+d)]
        top=[(x0+inset,.11,z0+inset),(x0+w-inset,.14,z0+inset*.85),(x0+w-inset*.8,.12,z0+d-inset),(x0+inset*.9,.15,z0+d-inset*.85)]
        ridge=[(x0+w*.25,height,z0+d*.50),(x0+w*.50,height+.025,z0+d*.48),(x0+w*.75,height*.95,z0+d*.51),(x0+w*.50,height+.01,z0+d*.72)]
        v=bottom+top+ridge
        f=[(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,9,8),(5,6,10,9),(6,7,11,10),(7,4,8,11),(8,9,10,11),(0,3,2,1)]
        self.mesh(name,v,f,mat)
    def ridge(self,name,x1,z1,x2,z2,width=.22,h=.11,mat="Soil_Light"):
        dx,dz=x2-x1,z2-z1; L=(dx*dx+dz*dz)**.5; yaw=math.atan2(dx,dz)
        cx,cz=(x1+x2)/2,(z1+z2)/2
        # Triangular prism furrow ridge.
        local=[(-width/2,0,-L/2),(width/2,0,-L/2),(0,h,-L/2),(-width/2,0,L/2),(width/2,0,L/2),(0,h,L/2)]
        co,si=math.cos(yaw),math.sin(yaw)
        v=[(cx+a*co+d*si,.13+b,cz-a*si+d*co) for a,b,d in local]
        self.mesh(name,v,[(0,1,2),(3,5,4),(0,3,4,1),(1,4,5,2),(2,5,3,0)],mat)
    def leaf(self,name,c,size,mat="Leaf_Mid",yaw=0.0,tilt=.35):
        cx,cy,cz=c; co,si=math.cos(yaw),math.sin(yaw)
        # Folded low-poly diamond leaf.
        pts=[(0,0,0),(size*.48,size*.12,0),(0,size*.07,size),( -size*.48,size*.12,0),(0,size*.20,size*.42)]
        v=[]
        for x,y,z in pts:
            z2=z*math.cos(tilt); y2=y+z*math.sin(tilt)
            v.append((cx+x*co+z2*si,cy+y2,cz-x*si+z2*co))
        self.mesh(name,v,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],mat)
    def seedling(self,name,x,z,scale=.12):
        self.leaf(name+"_a",(x,.17,z),scale,"Leaf_Mid",-.65,.55)
        self.leaf(name+"_b",(x,.17,z),scale*.92,"Leaf_Light",2.45,.55)
    def carrot(self,name,x,z,scale=1.0):
        # Small visible carrot shoulder and a radial low-poly leaf tuft.
        sides=6; r=.045*scale; h=.16*scale; v=[]
        for i in range(sides):
            a=2*math.pi*i/sides; v.append((x+r*math.cos(a),.145,z+r*math.sin(a)))
        v.append((x,.145-h,z)); tip=sides
        self.mesh(name+"_root",v,[tuple(range(sides-1,-1,-1))]+[(i,(i+1)%sides,tip) for i in range(sides)],"Carrot")
        for i in range(5):self.leaf(name+f"_leaf{i}",(x,.17,z),.13*scale,["Leaf_Dark","Leaf_Mid","Leaf_Light"][i%3],i*1.257,.75)
    def rock(self,name,x,z,s=.16):
        v=[(x-s,.02,z),(x+s*.8,.015,z-s*.45),(x+s,.02,z+s*.5),(x-s*.55,.01,z+s*.7),(x-s*.25,s*.55,z-s*.15),(x+s*.35,s*.48,z+s*.12)]
        self.mesh(name,v,[(0,1,4),(1,5,4),(1,2,5),(2,3,5),(3,4,5),(3,0,4),(0,3,2,1)],"Stone")
    def save(self):
        lines=[f"# {self.name} modular low-poly farm bed","mtllib farm_beds_materials.mtl",f"o {self.name}"]
        lines += [f"v {x:.6f} {y:.6f} {z:.6f}" for x,y,z in self.vertices]
        for name,mat,faces in self.groups:
            lines += [f"g {name}",f"usemtl {mat}","s off"]
            lines += ["f "+" ".join(map(str,f)) for f in faces]
        (OUT/f"{self.name}.obj").write_text("\n".join(lines)+"\n",encoding="utf-8")

def base(name,w,d):
    o=Obj(name); o.mound("soil",.04,.04,w-.08,d-.08); return o

def make_bare(name,w,d):
    o=base(name,w,d)
    if w>=2:o.rock("small_stone",w-.28,.24,.07)
    o.save()

def make_furrows(name,w=2,d=1):
    o=base(name,w,d)
    for i,z in enumerate((.25,.50,.75)):o.ridge(f"ridge_{i+1}",.14,z,w-.14,z,.17,.10,"Soil_Light" if i%2 else "Soil_Dark")
    o.save()

def make_seedlings():
    o=base("farm_bed_2x1_seedlings",2,1)
    for row,z in enumerate((.28,.52,.76)):
        for col,x in enumerate((.28,.64,1.0,1.36,1.72)):o.seedling(f"seedling_{row}_{col}",x,z,.105+(col%2)*.012)
    o.save()

def make_carrots():
    o=base("farm_bed_2x1_carrots",2,1)
    for row,z in enumerate((.27,.51,.75)):
        for col,x in enumerate((.25,.62,.99,1.36,1.73)):o.carrot(f"carrot_{row}_{col}",x,z,.85+(row+col)%3*.08)
    o.save()

def make_raised():
    o=Obj("raised_bed_2x1")
    o.box("soil",(1,.18,.5),(1.76,.25,.76),"Soil_Mid")
    o.box("frame_front",(1,.20,.06),(2,.34,.12),"Wood_Light")
    o.box("frame_back",(1,.20,.94),(2,.34,.12),"Wood_Dark")
    o.box("frame_left",(.06,.20,.5),(.12,.34,.76),"Wood_Dark")
    o.box("frame_right",(1.94,.20,.5),(.12,.34,.76),"Wood_Light")
    for x,z in ((.14,.14),(1.86,.14),(.14,.86),(1.86,.86)):o.box("corner_post",(x,.25,z),(.13,.50,.13),"Wood_Dark")
    o.save()

def make_path():
    o=Obj("farm_path_1x1")
    for i,(x,z,s,yaw) in enumerate(((.26,.27,.34,.1),(.68,.22,.30,-.15),(.45,.58,.36,.05),(.79,.72,.27,.2),(.17,.79,.25,-.1))):
        o.box(f"stone_{i}",(x,.035,z),(s,.07,s*.72),"Stone",yaw)
    o.save()

make_bare("farm_bed_1x1_bare",1,1)
make_bare("farm_bed_2x1_bare",2,1)
make_bare("farm_bed_2x2_bare",2,2)
make_furrows("farm_bed_2x1_furrows")
make_seedlings(); make_carrots(); make_raised(); make_path()

sizes={
 "farm_bed_1x1_bare":(1,.18,1), "farm_bed_2x1_bare":(2,.18,1), "farm_bed_2x2_bare":(2,.18,2),
 "farm_bed_2x1_furrows":(2,.26,1), "farm_bed_2x1_seedlings":(2,.42,1), "farm_bed_2x1_carrots":(2,.55,1),
 "raised_bed_2x1":(2,.50,1), "farm_path_1x1":(1,.10,1),
}
for name,(w,h,d) in sizes.items():
    scene=f'''[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Mesh" path="res://assets/models/low_poly_farm_beds/{name}.obj" id="1_mesh"]\n\n[sub_resource type="BoxShape3D" id="BoxShape3D_main"]\nsize = Vector3({w}, {h}, {d})\n\n[node name="{name}" type="Node3D"]\n\n[node name="Mesh" type="MeshInstance3D" parent="."]\nmesh = ExtResource("1_mesh")\n\n[node name="StaticBody3D" type="StaticBody3D" parent="."]\n\n[node name="CollisionShape3D" type="CollisionShape3D" parent="StaticBody3D"]\nposition = Vector3({w/2}, {h/2}, {d/2})\nshape = SubResource("BoxShape3D_main")\n'''
    (SCENES/f"{name}.tscn").write_text(scene,encoding="utf-8")

names=list(sizes)
lines=[f"[gd_scene load_steps={len(names)+1} format=3]",""]
for i,n in enumerate(names,1):lines.append(f'[ext_resource type="PackedScene" path="res://assets/models/low_poly_farm_beds/scenes/{n}.tscn" id="{i}_{n}"]')
lines += ["",'[node name="FarmBedsPackPreview" type="Node3D"]']
positions=[(0,0,0),(2,0,0),(5,0,0),(0,0,3),(3,0,3),(6,0,3),(0,0,6),(3,0,6)]
for i,(n,p) in enumerate(zip(names,positions),1):
    lines += ["",f'[node name="{n}" parent="." instance=ExtResource("{i}_{n}")]',f'position = Vector3({p[0]}, {p[1]}, {p[2]})']
(SCENES/"farm_beds_pack_preview.tscn").write_text("\n".join(lines)+"\n",encoding="utf-8")

(OUT/"README.md").write_text("""# Low-poly modular farm beds

Texture-free modular farm set for Godot 4, generated on a 1 metre grid.

## Included
- 1x1, 2x1 and 2x2 bare soil beds
- 2x1 furrow bed
- 2x1 seedlings bed
- 2x1 mature carrot bed
- 2x1 raised wooden bed
- 1x1 stone path tile
- Ready-to-instance Godot scenes with static collisions
- `scenes/farm_beds_pack_preview.tscn` overview scene

Pivots are at the lower-left grid corner (X=0, Z=0), making pieces easy to snap at 1 m intervals. Run `python3 tools/generate_farm_beds_pack.py` to rebuild the pack.
""",encoding="utf-8")
print(f"Generated {len(sizes)} models and {len(sizes)+1} Godot scenes in {OUT}")
