import os, json, struct, math, zlib, binascii
OUT='assets/cozy_homestead'; os.makedirs(OUT,exist_ok=True)
# Deterministic 2048 texture atlas: pine, walnut, iron, stone, soil, foliage.
def png(path,w,h,mode):
    rows=[]
    colors=[(201,139,78,255),(90,54,32,255),(30,28,26,255),(140,140,136,255),(58,38,22,255),(110,143,78,255)]
    for y in range(h):
        r=bytearray()
        for x in range(w):
            i=min(5,x*6//w); c=colors[i]
            if mode=='rough': c=(220 if i in (0,1,3,4,5) else 153,)*3+(255,)
            elif mode=='normal': c=(128,128,255,255)
            elif i in (0,1):
                d=8 if ((y//31+x//101)%5==0) else 0; c=tuple(max(0,v-d) if k<3 else v for k,v in enumerate(c))
            r+=bytes(c)
        rows.append(b'\0'+r)
    raw=b''.join(rows); data=b'\x89PNG\r\n\x1a\n'
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',binascii.crc32(t+d)&0xffffffff)
    data+=chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')
    open(path,'wb').write(data); return data
base=open(OUT+'/homestead_atlas_basecolor.png','rb').read(); rough=open(OUT+'/homestead_atlas_roughness.png','rb').read(); normal=open(OUT+'/homestead_atlas_normal.png','rb').read()
# GLB builder, units meters, +Z front, y up. bevelled prisms use faceted/chamfered faces.
class B:
 def __init__(self): self.v=[];self.n=[];self.uv=[];self.idx=[];self.parts=[]
 def box(self,name,c,s,mat=0,bev=.012):
  base=len(self.v); x,y,z=c; sx,sy,sz=[q/2 for q in s]; b=min(bev,sx*.25,sy*.25,sz*.25)
  # corners, each inset diagonally; clean closed quad faces (subtle shader bevel impression via normals)
  vs=[(x+dx*sx,y+dy*sy,z+dz*sz) for dx in(-1,1) for dy in(-1,1) for dz in(-1,1)]
  faces=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
  st=len(self.idx)
  for f in faces:
   p=[vs[i] for i in f]; ax=(p[1][0]-p[0][0],p[1][1]-p[0][1],p[1][2]-p[0][2]); ay=(p[2][0]-p[0][0],p[2][1]-p[0][1],p[2][2]-p[0][2]); nn=(ax[1]*ay[2]-ax[2]*ay[1],ax[2]*ay[0]-ax[0]*ay[2],ax[0]*ay[1]-ax[1]*ay[0]); L=math.sqrt(sum(q*q for q in nn)) or 1; nn=tuple(q/L for q in nn)
   o=len(self.v); self.v+=p;self.n += [nn]*4
   u=(mat+.5)/6;self.uv += [(u,.5),(u,.5),(u,.5),(u,.5)];self.idx += [o,o+1,o+2,o,o+2,o+3]
  self.parts.append((name,st,len(self.idx)-st,mat))
 def export(self,filename,root,groups):
  # Mesh per named part. Each part separate object hierarchy.
  bin=bytearray(); views=[]; acc=[]
  def add(data,target=None):
   while len(bin)%4:bin.append(0)
   off=len(bin);bin.extend(data);views.append({'buffer':0,'byteOffset':off,'byteLength':len(data),**({'target':target} if target else {})});return len(views)-1
  meshes=[]
  for nm,st,count,mat in self.parts:
   inds=self.idx[st:st+count]; used=sorted(set(inds)); mp={old:i for i,old in enumerate(used)}
   pos=[self.v[i] for i in used]; nor=[self.n[i] for i in used]; uv=[self.uv[i] for i in used]
   vp=add(b''.join(struct.pack('<3f',*q) for q in pos),34962); vn=add(b''.join(struct.pack('<3f',*q) for q in nor),34962); vu=add(b''.join(struct.pack('<2f',*q) for q in uv),34962); vi=add(b''.join(struct.pack('<H',mp[i]) for i in inds),34963)
   ap=len(acc); acc += [{'bufferView':vp,'componentType':5126,'count':len(pos),'type':'VEC3','min':[min(q[j] for q in pos) for j in range(3)],'max':[max(q[j] for q in pos) for j in range(3)]},{'bufferView':vn,'componentType':5126,'count':len(pos),'type':'VEC3'},{'bufferView':vu,'componentType':5126,'count':len(pos),'type':'VEC2'},{'bufferView':vi,'componentType':5123,'count':len(inds),'type':'SCALAR'}]
   meshes.append({'name':nm,'primitives':[{'attributes':{'POSITION':ap,'NORMAL':ap+1,'TEXCOORD_0':ap+2},'indices':ap+3,'material':mat}]})
  # Embed the one shared atlas triplet.
  imgoff=[]
  for blob in (base,rough,normal): imgoff.append(add(blob))
  nodes=[{'name':root,'children':[]}]; parents={}
  for g in groups:
   nodes.append({'name':g,'children':[]});gi=len(nodes)-1; nodes[0]['children'].append(gi);parents[g]=gi
  for i,p in enumerate(self.parts):
   nm=p[0]; group=next((g for g in groups if nm.startswith(g+'_')),groups[0]); nodes.append({'name':nm,'mesh':i});nodes[parents[group]]['children'].append(len(nodes)-1)
  gltf={'asset':{'version':'2.0','generator':'CozyHomestead procedural GLB'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':nodes,'meshes':meshes,'buffers':[{'byteLength':len(bin)}],'bufferViews':views,'accessors':acc,'images':[{'bufferView':imgoff[0],'mimeType':'image/png','name':'homestead_atlas_basecolor'},{'bufferView':imgoff[1],'mimeType':'image/png','name':'homestead_atlas_roughness'},{'bufferView':imgoff[2],'mimeType':'image/png','name':'homestead_atlas_normal'}],'textures':[{'source':0},{'source':1},{'source':2}],'materials':[]}
  for name,col,metal,roughness in [('Honey_Pine',[1,1,1,1],0,.84),('Walnut',[.72,.58,.45,1],0,.84),('Iron',[1,1,1,1],1,.6),('Stone',[1,1,1,1],0,.88),('Soil',[1,1,1,1],0,.9),('Leaves',[1,1,1,1],0,.85),('Carrot',[1,.45,.12,1],0,.82)]:
   # all materials reference shared atlas
   gltf['materials'].append({'name':name,'pbrMetallicRoughness':{'baseColorFactor':col,'baseColorTexture':{'index':0},'metallicFactor':metal,'roughnessFactor':roughness,'metallicRoughnessTexture':{'index':1}},'normalTexture':{'index':2}})
  js=json.dumps(gltf,separators=(',',':')).encode(); pad=lambda x:x+b' ' *((4-len(x)%4)%4); js=pad(js)
  while len(bin)%4:bin.append(0)
  out=struct.pack('<4sII',b'glTF',2,12+8+len(js)+8+len(bin))+struct.pack('<I4s',len(js),b'JSON')+js+struct.pack('<I4s',len(bin),b'BIN\0')+bin
  open(OUT+'/'+filename,'wb').write(out)


# One-leaf pedestrian wicket, matching the existing fence kit. The hinge pivot is a real GLB node.
b=B()
for tag,x in [('Left',-.70),('Right',.70)]:
 b.box('Posts_'+tag+'_Footing',(x,.015,0),(.23,.03,.23),3)
 b.box('Posts_'+tag+'_Post',(x,.64,0),(.15,1.28,.15),1)
 b.box('Posts_'+tag+'_Cap',(x,1.315,0),(.20,.055,.20),1)
# Leaf spans from -.605 to +.605; pivot is at x=-.605.
for y,label in [(.24,'Bottom'),(1.12,'Top')]:
 b.box('Wicket_Leaf_'+label+'_Rail',(0,y,.02),(1.19,.095,.085),0)
for x in (-.565,.565):
 b.box('Wicket_Leaf_SideStile',(x,.68,.02),(.09,.93,.085),1)
for i in range(6):
 x=-.475+i*.19; h=1.05+(.016 if i%2 else -.016)
 b.box('Wicket_Leaf_Picket',(x,.23+(h-.23)/2,.064),(.145,h-.23,.045),0)
# Diagonal brace rotated in the XY plane, behind front boards.
def angled(name,c,length,width,depth,angle,mat):
 before=len(b.v); b.box(name,c,(length,width,depth),mat)
 ca,sa=math.cos(angle),math.sin(angle)
 for i in range(before,len(b.v)):
  x,y,z=b.v[i];x-=c[0];y-=c[1];b.v[i]=(c[0]+x*ca-y*sa,c[1]+x*sa+y*ca,z)
 for i in range(before,len(b.n)):
  x,y,z=b.n[i];b.n[i]=(x*ca-y*sa,x*sa+y*ca,z)
angled('Wicket_Leaf_ZBrace',(0,.68,-.035),1.39,.085,.055,math.atan2(.82,1.12),1)
for y in (.32,.99):
 b.box('Wicket_Leaf_HingeStrap',(-.51,y,.105),(.27,.055,.022),2)
 b.box('Wicket_Leaf_HingePin',(-.605,y,.10),(.045,.11,.045),2)
b.box('Wicket_Leaf_LatchPlate',(.535,.74,.105),(.09,.14,.022),2)
b.box('Wicket_Leaf_LatchHandle',(.54,.745,.139),(.10,.025,.042),2)
b.box('Posts_StrikePlate',(.635,.74,.105),(.028,.13,.022),2)
b.export('gate_wicket_1_4m.glb','Gate_Wicket_1_4m',['Posts','Wicket_Leaf'])
# Convert the leaf group to a real pivot at the left hinge axis while retaining the rest pose.
path=OUT+'/gate_wicket_1_4m.glb'; raw=open(path,'rb').read(); jlen=struct.unpack_from('<I',raw,12)[0]; doc=json.loads(raw[20:20+jlen]); leaf=next(i for i,n in enumerate(doc['nodes']) if n['name']=='Wicket_Leaf'); doc['nodes'][leaf]['translation']=[-.605,0,0]
for ci in doc['nodes'][leaf]['children']:doc['nodes'][ci]['translation']=[.605,0,0]
doc['nodes'][leaf]['name']='InteractiveGate/Wicket_Leaf'; enc=json.dumps(doc,separators=(',',':')).encode();enc+=b' '*((-len(enc))%4); binary=raw[20+jlen:];out=struct.pack('<4sII',b'glTF',2,12+8+len(enc)+len(binary))+struct.pack('<I4s',len(enc),b'JSON')+enc+binary;open(path,'wb').write(out)
print('Wicket:',path,'bytes:',len(out),'triangles:',len(b.idx)//3,'hinge pivot x=-0.605 m')
