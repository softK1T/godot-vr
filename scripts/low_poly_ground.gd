@tool
extends StaticBody3D
class_name LowPolyGround

@export var rebuild := false:
	set(value):
		rebuild = false
		if value: build()
@export_range(60.0, 240.0, 2.0) var ground_size := 180.0
@export_range(0.65, 3.0, 0.05) var polygon_size := 1.1
@export_range(0.0, 0.35, 0.005) var relief_depth := 0.18
@export var seed_value := 7351
@onready var mesh_instance: MeshInstance3D = $Mesh

func _ready() -> void: build()
func build() -> void:
	if not is_instance_valid(mesh_instance): mesh_instance = get_node_or_null("Mesh") as MeshInstance3D
	if mesh_instance: mesh_instance.mesh = _create_ground_mesh()

func _create_ground_mesh() -> ArrayMesh:
	var vertices:=PackedVector3Array(); var normals:=PackedVector3Array(); var colors:=PackedColorArray(); var indices:=PackedInt32Array()
	var cells:=int(ceil(ground_size/polygon_size)); var half:=cells*polygon_size*.5
	var points:=PackedVector3Array(); points.resize((cells+1)*(cells+1))
	# Shared vertices are strongly jittered in X/Z. This removes the visible
	# square grid while keeping neighbouring triangles welded without cracks.
	for z in range(cells+1):
		for x in range(cells+1):
			var edge:=x==0 or z==0 or x==cells or z==cells
			var jitter_x:=0.0 if edge else (_hash(Vector2(x*7+13,z*11-5))-.5)*polygon_size*.78
			var jitter_z:=0.0 if edge else (_hash(Vector2(x*17-8,z*5+29))-.5)*polygon_size*.78
			# Offset alternating rows so long straight lines no longer continue.
			var stagger:=0.0 if edge else (polygon_size*.22 if z%2==1 else -polygon_size*.22)
			var px:=-half+x*polygon_size+jitter_x+stagger
			var pz:=-half+z*polygon_size+jitter_z
			points[z*(cells+1)+x]=Vector3(px,_height_at(Vector2(px,pz)),pz)
	for z in range(cells):
		for x in range(cells):
			var p00:=points[z*(cells+1)+x]; var p10:=points[z*(cells+1)+x+1]
			var p01:=points[(z+1)*(cells+1)+x]; var p11:=points[(z+1)*(cells+1)+x+1]
			var pattern:=_hash(Vector2(x*23+3,z*19-7))
			# Some cells receive an off-centre fifth vertex. Combined with random
			# diagonals this creates triangles of many sizes and silhouettes.
			if pattern>.70:
				var center:=(p00+p10+p01+p11)*.25
				center.x+=(_hash(Vector2(x*31,z*37))-.5)*polygon_size*.28
				center.z+=(_hash(Vector2(x*41,z*43))-.5)*polygon_size*.28
				center.y=_height_at(Vector2(center.x,center.z))
				_add_face(vertices,normals,colors,indices,p00,center,p10,x,z,0)
				_add_face(vertices,normals,colors,indices,p10,center,p11,x,z,1)
				_add_face(vertices,normals,colors,indices,p11,center,p01,x,z,2)
				_add_face(vertices,normals,colors,indices,p01,center,p00,x,z,3)
			elif pattern>.35:
				_add_face(vertices,normals,colors,indices,p00,p11,p10,x,z,0); _add_face(vertices,normals,colors,indices,p00,p01,p11,x,z,1)
			else:
				_add_face(vertices,normals,colors,indices,p00,p01,p10,x,z,0); _add_face(vertices,normals,colors,indices,p10,p01,p11,x,z,1)
	var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); return mesh

func _add_face(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,idx: PackedInt32Array,a: Vector3,b: Vector3,d: Vector3,x: int,z: int,t: int)->void:
	var normal:=(b-a).cross(d-a).normalized()
	# Godot treats the opposite winding as the visible front face. Keep the
	# vertices clockwise when viewed from above, but preserve upward normals.
	if normal.y>0: var swap:=b; b=d; d=swap
	normal=(b-a).cross(d-a).normalized()
	if normal.y<0: normal=-normal
	var center:=(a+b+d)/3.0; var color:=_face_color(Vector2(center.x,center.z),x,z,t,normal.y); var start:=v.size()
	v.append(a);v.append(b);v.append(d);n.append(normal);n.append(normal);n.append(normal);c.append(color);c.append(color);c.append(color);idx.append(start);idx.append(start+1);idx.append(start+2)

func _height_at(p: Vector2)->float:
	var broad:=sin(p.x*.115+seed_value)*cos(p.y*.097-seed_value)*.45
	var medium:=sin((p.x+p.y)*.31)*.22+cos((p.x-p.y)*.27)*.18
	var stepped:=(_hash(floor(p/polygon_size))-.5)*.42
	var height:=minf((broad+medium+stepped)*relief_depth,0.0)
	return lerpf(height,-.004,_protected_flatten(p))

func _face_color(p: Vector2,x: int,z: int,t: int,upward: float)->Color:
	var coarse:=_hash(Vector2(floor(p.x/7.0),floor(p.y/7.0))); var face:=_hash(Vector2(x*2+t,z*3-t))
	var result:=Color(.035,.085,.024).lerp(Color(.065,.135,.035),smoothstep(.18,.72,coarse))
	if face>.72: result=result.lerp(Color(.105,.185,.045),.38)
	elif face<.17: result=result.lerp(Color(.075,.125,.027),.46)
	var soil:=Color(.075,.043,.022).lerp(Color(.13,.073,.031),face); result=result.lerp(soil,_wear_mask(p)*(.35+face*.18))
	var light:=remap(clampf(upward,.94,1.0),.94,1.0,.82,1.06); return Color(result.r*light,result.g*light,result.b*light,1)

func _wear_mask(p: Vector2)->float:
	var cabin:=_ellipse(p,Vector2(0,-2),Vector2(8.5,8),.32); var garden:=_ellipse(p,Vector2(-8,-4),Vector2(6.2,5.2),.34)
	return maxf(cabin,garden)*smoothstep(.32,.62,_hash(floor((p+Vector2(13,5))/2.5)))
func _protected_flatten(p: Vector2)->float:
	var house:=_rect_mask(p,Vector2(.2,-3),Vector2(5.7,5.4),1.5); var garden:=_rect_mask(p,Vector2(-8.2,-4.1),Vector2(4.7,4.3),1.25)
	var route:=1.0-smoothstep(.75,2.0,minf(_distance(p,_main_route()),_distance(p,_garden_route()))); return maxf(maxf(house,garden),route)
func _ellipse(p:Vector2,center:Vector2,radius:Vector2,soft:float)->float: return 1.0-smoothstep(1.0-soft,1.0,((p-center)/radius).length())
func _rect_mask(p:Vector2,center:Vector2,half_size:Vector2,fade:float)->float:
	var q: Vector2 = abs(p-center)-half_size; return 1.0-smoothstep(0.0,fade,Vector2(maxf(q.x,0),maxf(q.y,0)).length())
func _hash(p:Vector2)->float: return fposmod(sin(p.dot(Vector2(127.1,311.7))+seed_value*.013)*43758.5453,1.0)
func _main_route()->PackedVector2Array: return PackedVector2Array([Vector2(-.15,14.8),Vector2(-.55,11.8),Vector2(.15,8.6),Vector2(.75,6.1),Vector2(1.55,4.15),Vector2(2.75,2.1),Vector2(3.78,.05)])
func _garden_route()->PackedVector2Array: return PackedVector2Array([Vector2(.15,8.6),Vector2(-1.7,7.35),Vector2(-3.9,5.75),Vector2(-5.8,3.85),Vector2(-6.85,1.75),Vector2(-6.45,-.72)])
func _distance(point:Vector2,route:PackedVector2Array)->float:
	var best:=INF
	for i in range(route.size()-1): var start:=route[i];var segment:=route[i+1]-start;var ratio:=clampf((point-start).dot(segment)/maxf(segment.length_squared(),.0001),0,1);best=minf(best,point.distance_to(start+segment*ratio))
	return best
