#!/usr/bin/env python3
from __future__ import annotations
import json, math, random, struct, zlib, binascii
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/detailed_forest_cabin"
TEX = OUT / "textures"
OUT.mkdir(parents=True, exist_ok=True)
TEX.mkdir(parents=True, exist_ok=True)
RNG = random.Random(20260920)

# ---------- PNG texture generation (stdlib only) ----------
def png(path: Path, w: int, h: int, pixels: bytes, channels: int = 3):
    color_type = 2 if channels == 3 else 6
    raw = b"".join(b"\x00" + pixels[y*w*channels:(y+1)*w*channels] for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", binascii.crc32(t+d) & 0xffffffff)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w,h,8,color_type,0,0,0))
    data += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(data)

def clamp(v): return max(0, min(255, int(v)))
def hash2(x,y,s=0):
    n=(x*374761393+y*668265263+s*1442695041)&0xffffffff
    n=(n^(n>>13))*1274126177&0xffffffff
    return ((n^(n>>16))&0xffff)/65535.0

def normal_from_height(height, w, h, strength=3.0):
    out=bytearray()
    for y in range(h):
        for x in range(w):
            l=height[y*w+(x-1)%w]; r=height[y*w+(x+1)%w]
            u=height[((y-1)%h)*w+x]; d=height[((y+1)%h)*w+x]
            nx=(l-r)*strength; ny=(u-d)*strength; nz=1.0
            q=math.sqrt(nx*nx+ny*ny+nz*nz); nx/=q; ny/=q; nz/=q
            out += bytes((clamp((nx*.5+.5)*255),clamp((ny*.5+.5)*255),clamp((nz*.5+.5)*255)))
    return out

def make_wood(prefix, base, plank=False):
    w=h=512; heights=[]; rgb=bytearray(); mr=bytearray()
    knots=[(RNG.randrange(w),RNG.randrange(h),RNG.randrange(12,34)) for _ in range(14 if plank else 9)]
    for y in range(h):
        for x in range(w):
            grain=math.sin(x*.095+math.sin(y*.018)*4.0)+.45*math.sin(x*.31+y*.012)
            grain += (hash2(x//3,y//3,11)-.5)*.48
            if plank:
                seam=min(y%128,127-y%128)
                grain -= 2.5*max(0,1-seam/4)
            knot=0.0
            for kx,ky,kr in knots:
                dx=min(abs(x-kx),w-abs(x-kx)); dy=min(abs(y-ky),h-abs(y-ky))
                dist=math.sqrt((dx*1.5)**2+dy*dy)
                if dist<kr: knot += math.cos(dist/kr*math.pi)*1.5
            val=grain*7-knot*18
            heights.append((grain-knot*.7)*.035)
            rgb += bytes(tuple(clamp(c+val) for c in base))
            rough=clamp(196+(hash2(x,y,31)-.5)*22+knot*10)
            mr += bytes((0,rough,0))
    png(TEX/f"{prefix}_albedo.png",w,h,bytes(rgb)); png(TEX/f"{prefix}_normal.png",w,h,normal_from_height(heights,w,h,4.6)); png(TEX/f"{prefix}_mr.png",w,h,bytes(mr))

def make_roof():
    w=h=512; height=[]; rgb=bytearray(); mr=bytearray()
    for y in range(h):
        row=y//64; yy=y%64; shift=32 if row%2 else 0
        xx=(x:=0)
        for x in range(w):
            xx=(x+shift)%96
            edge=min(xx,95-xx,yy,63-yy)
            mortar=max(0,1-edge/3)
            n=(hash2(x//4,y//4,9)-.5)*18
            c=(62+n-25*mortar,47+n*.7-20*mortar,35+n*.5-14*mortar)
            rgb += bytes(clamp(q) for q in c)
            height.append((1-mortar)*.06+(hash2(x,y,4)-.5)*.006)
            mr += bytes((0,clamp(215+n*.4),0))
    png(TEX/"roof_albedo.png",w,h,bytes(rgb)); png(TEX/"roof_normal.png",w,h,normal_from_height(height,w,h,6)); png(TEX/"roof_mr.png",w,h,bytes(mr))

def make_stone():
    w=h=512; height=[]; rgb=bytearray(); mr=bytearray()
    for y in range(h):
        row=y//72; shift=48 if row%2 else 0
        for x in range(w):
            xx=(x+shift)%112; yy=y%72; edge=min(xx,111-xx,yy,71-yy)
            mortar=max(0,1-edge/5); n=(hash2(x//5,y//5,14)-.5)*25
            base=(103+n,96+n,82+n*.85)
            rgb += bytes(clamp(q*(1-.48*mortar)) for q in base)
            height.append(.075*(1-mortar)+(hash2(x,y,7)-.5)*.012)
            mr += bytes((0,clamp(225+n*.25),0))
    png(TEX/"stone_albedo.png",w,h,bytes(rgb)); png(TEX/"stone_normal.png",w,h,normal_from_height(height,w,h,7)); png(TEX/"stone_mr.png",w,h,bytes(mr))

def make_metal():
    w=h=256; rgb=bytearray(); mr=bytearray()
    for y in range(h):
        for x in range(w):
            n=(hash2(x,y,23)-.5)*16; rust=max(0,math.sin(x*.06+y*.025)-.82)*35
            rgb += bytes((clamp(43+n+rust),clamp(46+n*.8+rust*.35),clamp(44+n*.7)))
            mr += bytes((0,clamp(95+(hash2(x,y,2)-.5)*18),235))
    png(TEX/"metal_albedo.png",w,h,bytes(rgb)); png(TEX/"metal_mr.png",w,h,bytes(mr))

make_wood("log",(104,55,27),False)
make_wood("plank",(126,72,35),True)
make_roof(); make_stone(); make_metal()
png(TEX/"glass.png",4,4,bytes([96,150,170,82]*16),4)

# ---------- Geometry ----------
class Mesh:
    def __init__(self): self.p=[]; self.n=[]; self.uv=[]; self.i=[]
    def quad(self, a,b,c,d,n,uv=(0,0,1,1)):
        k=len(self.p); self.p += [a,b,c,d]; self.n += [n]*4
        u0,v0,u1,v1=uv; self.uv += [(u0,v0),(u1,v0),(u1,v1),(u0,v1)]; self.i += [k,k+1,k+2,k,k+2,k+3]
    def box(self,c,s,uvscale=(1,1),rot_x=0.0,rot_y=0.0):
        cx,cy,cz=c; sx,sy,sz=(q/2 for q in s)
        def tx(p):
            x,y,z=p
            cyy,syy=math.cos(rot_y),math.sin(rot_y); x,z=x*cyy+z*syy,-x*syy+z*cyy
            cxx,sxx=math.cos(rot_x),math.sin(rot_x); y,z=y*cxx-z*sxx,y*sxx+z*cxx
            return (x+cx,y+cy,z+cz)
        faces=[(((-sx,-sy,-sz),(sx,-sy,-sz),(sx,sy,-sz),(-sx,sy,-sz)),(0,0,-1)),(((sx,-sy,sz),(-sx,-sy,sz),(-sx,sy,sz),(sx,sy,sz)),(0,0,1)),(((-sx,-sy,sz),(-sx,-sy,-sz),(-sx,sy,-sz),(-sx,sy,sz)),(-1,0,0)),(((sx,-sy,-sz),(sx,-sy,sz),(sx,sy,sz),(sx,sy,-sz)),(1,0,0)),(((-sx,sy,-sz),(sx,sy,-sz),(sx,sy,sz),(-sx,sy,sz)),(0,1,0)),(((-sx,-sy,sz),(sx,-sy,sz),(sx,-sy,-sz),(-sx,-sy,-sz)),(0,-1,0))]
        for pts,n in faces:
            p=[tx(q) for q in pts]; nn=tx(n); nn=(nn[0]-cx,nn[1]-cy,nn[2]-cz); l=math.sqrt(sum(q*q for q in nn)); nn=tuple(q/l for q in nn)
            self.quad(*p,nn,(0,0,uvscale[0],uvscale[1]))
    def cylinder(self,a,b,r,sides=10,uv_len=2.0,caps=True):
        ax,ay,az=a; bx,by,bz=b; dx,dy,dz=bx-ax,by-ay,bz-az; L=math.sqrt(dx*dx+dy*dy+dz*dz); t=(dx/L,dy/L,dz/L)
        helper=(0,1,0) if abs(t[1])<.9 else (1,0,0)
        n1=(t[1]*helper[2]-t[2]*helper[1],t[2]*helper[0]-t[0]*helper[2],t[0]*helper[1]-t[1]*helper[0]); q=math.sqrt(sum(v*v for v in n1)); n1=tuple(v/q for v in n1)
        n2=(t[1]*n1[2]-t[2]*n1[1],t[2]*n1[0]-t[0]*n1[2],t[0]*n1[1]-t[1]*n1[0])
        base=len(self.p)
        for j,P in enumerate((a,b)):
            for i in range(sides+1):
                ang=2*math.pi*i/sides; normal=tuple(n1[k]*math.cos(ang)+n2[k]*math.sin(ang) for k in range(3)); self.p.append(tuple(P[k]+normal[k]*r for k in range(3))); self.n.append(normal); self.uv.append((j*L/uv_len,i/sides))
        for i in range(sides):
            k=base+i; self.i += [k,k+sides+1,k+1,k+1,k+sides+1,k+sides+2]
        if caps:
            for P,N,rev in ((a,tuple(-v for v in t),True),(b,t,False)):
                center=len(self.p); self.p.append(P); self.n.append(N); self.uv.append((.5,.5))
                ring=[]
                for i in range(sides):
                    ang=2*math.pi*i/sides; normal=tuple(n1[k]*math.cos(ang)+n2[k]*math.sin(ang) for k in range(3)); ring.append(len(self.p)); self.p.append(tuple(P[k]+normal[k]*r for k in range(3))); self.n.append(N); self.uv.append((.5+.5*math.cos(ang),.5+.5*math.sin(ang)))
                for i in range(sides): self.i += ([center,ring[(i+1)%sides],ring[i]] if rev else [center,ring[i],ring[(i+1)%sides]])

meshes={k:Mesh() for k in ("logs","planks","roof","stone","metal","glass")}
log=meshes["logs"]; plank=meshes["planks"]; roof=meshes["roof"]; stone=meshes["stone"]; metal=meshes["metal"]; glass=meshes["glass"]
# Foundation blocks and floor
for z in (-2.75,2.75):
    for x in [i*.75-2.625 for i in range(8)]: stone.box((x,.22,z),(.7,.44,.48),(1,1))
for x in (-2.75,2.75):
    for z in [i*.75-2.0 for i in range(6)]: stone.box((x,.22,z),(.48,.44,.7),(1,1))
for i in range(12): plank.box((0,.48,-2.75+i*.5),(5.45,.14,.46),(4,1))
# Log courses with front door/window and side/rear windows
for course in range(11):
    y=.67+course*.255
    # rear, split for rear window x -.8..8 at y 1.2..2.2
    intervals=[(-3.15,3.15)]
    if 2<=course<=6: intervals=[(-3.15,-.8),(.8,3.15)]
    for x0,x1 in intervals: log.cylinder((x0,y,-2.92),(x1,y,-2.92),.17,10,2.2)
    # front: door right and window left
    cuts=[]
    if course<=7: cuts.append((1.15,2.35))
    if 2<=course<=6: cuts.append((-2.25,-.75))
    intervals=[(-3.15,3.15)]
    for c0,c1 in cuts:
        new=[]
        for a,b in intervals:
            if c0>a:new.append((a,min(c0,b)))
            if c1<b:new.append((max(c1,a),b))
        intervals=[q for q in new if q[1]-q[0]>.08]
    for x0,x1 in intervals: log.cylinder((x0,y,2.92),(x1,y,2.92),.17,10,2.2)
    # Side walls: left has a window; right has the full-height door opening
    # aligned to the existing sloped staircase on the cabin's east side.
    left_intervals=[(-3.15,-.8),(.8,3.15)] if 2<=course<=6 else [(-3.15,3.15)]
    right_intervals=[(-3.15,1.55)] if course<=7 else [(-3.15,3.15)]
    for z0,z1 in left_intervals: log.cylinder((-2.92,y,z0),(-2.92,y,z1),.17,10,2.2)
    for z0,z1 in right_intervals: log.cylinder((2.92,y,z0),(2.92,y,z1),.17,10,2.2)
# stepped gables
for j in range(7):
    y=3.46+j*.255; half=2.75*(1-j/7)+.15
    log.cylinder((-half,y,-2.92),(half,y,-2.92),.17,10,2.2); log.cylinder((-half,y,2.92),(half,y,2.92),.17,10,2.2)
# Roof panels and ridge, fascia
pitch=math.atan2(2.05,3.65); slope=math.sqrt(2.05**2+3.65**2)
roof.box((0,4.13,1.82),(6.8,.20,slope),(3,3),rot_x=pitch)
roof.box((0,4.13,-1.82),(6.8,.20,slope),(3,3),rot_x=-pitch)
log.cylinder((-3.5,5.18,0),(3.5,5.18,0),.16,10,2.0)
for x in (-3.22,3.22): plank.box((x,4.12,1.82),(.16,.26,slope),(1,3),rot_x=pitch); plank.box((x,4.12,-1.82),(.16,.26,slope),(1,3),rot_x=-pitch)
# Interior rafters and ceiling beams
for x in (-2.55,-1.3,0,1.3,2.55):
    plank.box((x,4.02,1.55),(.16,.18,3.65),(1,3),rot_x=pitch); plank.box((x,4.02,-1.55),(.16,.18,3.65),(1,3),rot_x=-pitch)
for z in (-2.2,-.75,.75,2.2): log.cylinder((-2.75,3.18,z),(2.75,3.18,z),.13,8,2.0)
# Window frames and glass: front, rear, and left wall. The right wall contains
# the main entrance and stairs instead of a window.
windows=[(( -1.5,1.7,3.03),(1.5,1.25,.05),0),((0,1.7,-3.03),(1.5,1.25,.05),0),((-3.03,1.7,0),(.05,1.25,1.5),1)]
for idx,(c,s,side) in enumerate(windows):
    glass.box(c,s,(1,1))
    if side==0:
        for dx in (-s[0]/2,s[0]/2,0): plank.box((c[0]+dx,c[1],c[2]),(.10,s[1]+.18,.14),(1,2))
        for dy in (-s[1]/2,s[1]/2,0): plank.box((c[0],c[1]+dy,c[2]),(s[0]+.18,.10,.14),(2,1))
    else:
        for dz in (-s[2]/2,s[2]/2,0): plank.box((c[0],c[1],c[2]+dz),(.14,s[1]+.18,.10),(1,2))
        for dy in (-s[1]/2,s[1]/2,0): plank.box((c[0],c[1]+dy,c[2]),(.14,.10,s[2]+.18),(2,1))
# Porch deck and posts/rails
for i in range(13): plank.box((-2.7+i*.45,.64,3.45),(.40,.13,1.0),(1,2))
for x in (-2.7,0,2.7): log.cylinder((x,.65,3.75),(x,3.15,3.75),.12,8,2)
for x in (-2.7,2.7): plank.box((x,1.35,3.76),(.12,.12,1.0),(1,2))
plank.box((0,1.35,3.92),(5.35,.12,.12),(4,1))
# Right-side wide steps aligned with existing stair ramp
for i,(z,y,w) in enumerate(((4.02,.48,1.0),(4.42,.31,1.35),(4.84,.15,1.7))): plank.box((3.76,y,z),(2.75,.22,w),(3,2))
# Chimney
for y in (1.0,1.7,2.4,3.1,3.8,4.5): stone.box((-1.75,y,-1.25),(.72,.62,.72),(1,1))
stone.box((-1.75,4.88,-1.25),(.92,.18,.92),(1,1))
# Decorative braces and iron corner straps
for x in (-2.72,2.72):
    plank.box((x,2.15,3.08),(.14,2.45,.18),(1,3))
for x in (-2.82,2.82):
    for y in (.85,2.85): metal.box((x,y,3.09),(.22,.11,.035),(1,1))

# Door mesh is local around hinge at origin; multiple materials in one named glTF node.
door_wood=Mesh(); door_metal=Mesh()
door_wood.box((.56,1.28,0),(1.08,2.48,.12),(2,4))
for x in (.18,.55,.92): door_wood.box((x,1.28,-.075),(.055,2.34,.055),(1,4))
door_wood.box((.55,.55,-.11),(1.0,.11,.08),(3,1),rot_y=-.28); door_wood.box((.55,1.98,-.11),(1.0,.11,.08),(3,1),rot_y=.28)
for y in (.35,2.15): door_metal.box((.08,y,-.13),(.34,.09,.04),(1,1))
door_metal.cylinder((.88,1.22,-.17),(.88,1.22,-.28),.06,8,.2)

# ---------- glTF writer ----------
materials=[]; images=[]; textures=[]
def tex(name):
    images.append({"uri":"textures/"+name}); textures.append({"sampler":0,"source":len(images)-1}); return len(textures)-1
def mat(name,base,normal=None,mr=None,rough=.9,metallic=0.0,alpha=False):
    p={"baseColorFactor":[1,1,1,1],"roughnessFactor":rough,"metallicFactor":metallic,"baseColorTexture":{"index":tex(base)}}
    if mr:p["metallicRoughnessTexture"]={"index":tex(mr)}
    m={"name":name,"pbrMetallicRoughness":p}
    if normal:m["normalTexture"]={"index":tex(normal),"scale":.75}
    if alpha:m.update({"alphaMode":"BLEND","doubleSided":True,"pbrMetallicRoughness":{"baseColorFactor":[.55,.8,.9,.35],"roughnessFactor":.16,"metallicFactor":0,"baseColorTexture":{"index":tex(base)}}})
    materials.append(m); return len(materials)-1
M={
 "logs":mat("Hand Hewn Logs","log_albedo.png","log_normal.png","log_mr.png",.88),
 "planks":mat("Oiled Timber","plank_albedo.png","plank_normal.png","plank_mr.png",.82),
 "roof":mat("Wood Shingles","roof_albedo.png","roof_normal.png","roof_mr.png",.94),
 "stone":mat("Fieldstone","stone_albedo.png","stone_normal.png","stone_mr.png",.97),
 "metal":mat("Forged Iron","metal_albedo.png",None,"metal_mr.png",.42,.85),
 "glass":mat("Old Window Glass","glass.png",alpha=True),
}
buf=bytearray(); views=[]; access=[]
def align():
    while len(buf)%4:buf.append(0)
def accessor(data,component,count,typ,target,mins=None,maxs=None):
    align(); off=len(buf)
    if component==5126: raw=b''.join(struct.pack('<f',float(v)) for v in data)
    else: raw=b''.join(struct.pack('<I',int(v)) for v in data)
    buf.extend(raw); views.append({"buffer":0,"byteOffset":off,"byteLength":len(raw),"target":target}); a={"bufferView":len(views)-1,"componentType":component,"count":count,"type":typ}
    if mins is not None:a["min"]=mins;a["max"]=maxs
    access.append(a);return len(access)-1
def primitive(m:Mesh,material):
    flatp=[q for p in m.p for q in p]; flatn=[q for p in m.n for q in p]; flatuv=[q for p in m.uv for q in p]
    mn=[min(p[j] for p in m.p) for j in range(3)]; mx=[max(p[j] for p in m.p) for j in range(3)]
    return {"attributes":{"POSITION":accessor(flatp,5126,len(m.p),"VEC3",34962,mn,mx),"NORMAL":accessor(flatn,5126,len(m.n),"VEC3",34962),"TEXCOORD_0":accessor(flatuv,5126,len(m.uv),"VEC2",34962)},"indices":accessor(m.i,5125,len(m.i),"SCALAR",34963),"material":material,"mode":4}

gmeshes=[]; nodes=[]; children=[]
for key,label in (("stone","Foundation_Stone"),("logs","Log_Walls"),("planks","Timber_Details"),("roof","Shingle_Roof"),("metal","Forged_Iron_Details"),("glass","window_glass_all")):
    gm={"name":label,"primitives":[primitive(meshes[key],M[key])]}; gmeshes.append(gm); nodes.append({"name":label,"mesh":len(gmeshes)-1}); children.append(len(nodes)-1)
# Interactive door with wood + metal primitives and hinge transform.
gmeshes.append({"name":"Cabin_Door_3","primitives":[primitive(door_wood,M["planks"]),primitive(door_metal,M["metal"])]})
nodes.append({"name":"Cabin_Door_3","mesh":len(gmeshes)-1,"translation":[3.08,.52,-.62],"rotation":[0,.70710678,0,.70710678]}); children.append(len(nodes)-1)
root_index=len(nodes); nodes.append({"name":"DetailedForestCabin","children":children})

gltf={"asset":{"version":"2.0","generator":"Perplexity procedural detailed cabin generator"},"scene":0,"scenes":[{"name":"Detailed Forest Cabin","nodes":[root_index]}],"nodes":nodes,"meshes":gmeshes,"materials":materials,"samplers":[{"magFilter":9729,"minFilter":9987,"wrapS":10497,"wrapT":10497}],"textures":textures,"images":images,"buffers":[{"uri":"detailed_forest_cabin.bin","byteLength":len(buf)}],"bufferViews":views,"accessors":access}
(OUT/"detailed_forest_cabin.bin").write_bytes(buf)
(OUT/"detailed_forest_cabin.gltf").write_text(json.dumps(gltf,separators=(',',':')),encoding='utf-8')
(OUT/"README.md").write_text("""# Detailed Forest Cabin

Procedurally authored textured log cabin for Godot 4.

Features: accessible interior, opening named door compatible with `cabin_collision.gd`, hand-hewn log walls, UV-mapped PBR wood/stone/shingle/iron materials, normal and roughness maps, four framed windows, interior rafters and beams, porch, right-side stairs aligned to the existing ramp, chimney and foundation.

Run `python3 tools/generate_detailed_cabin.py` to rebuild the model and textures.
""",encoding='utf-8')
print(f"Generated {OUT}")
print(f"vertices={sum(len(m.p) for m in meshes.values())+len(door_wood.p)+len(door_metal.p)} triangles={(sum(len(m.i) for m in meshes.values())+len(door_wood.i)+len(door_metal.i))//3} nodes={len(nodes)} materials={len(materials)} textures={len(list(TEX.glob('*.png')))}")
