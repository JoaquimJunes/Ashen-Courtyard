"""Repair confirmed mesh defects and reuse the existing protagonist atlas."""
import bpy,bmesh,json,hashlib,math,os,shutil
from pathlib import Path
from collections import defaultdict,Counter
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

OUT=Path(__file__).resolve().parent
OLD=OUT.parent/'protagonist_texture_preview'
body=bpy.data.objects['Mannequin'];arm=bpy.data.objects['Armature']
if body.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
mesh=body.data
source_path=Path(bpy.data.filepath)
source_hash=hashlib.sha256(source_path.read_bytes()).hexdigest()
def rig_signature():
    return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else '',[list(r) for r in b.matrix_local]) for b in arm.data.bones]).encode()).hexdigest()
rig_before=rig_signature()
def poskey(p):return tuple(round(float(c),7) for c in p)
original_positions={poskey(v.co) for v in mesh.vertices}
original_faces={tuple(sorted(poskey(mesh.vertices[i].co) for i in p.vertices)):tuple(p.vertices) for p in mesh.polygons}
original_weights={v.index:{body.vertex_groups[g.group].name:g.weight for g in v.groups if g.weight>0} for v in mesh.vertices}
report={'source_path':str(source_path),'source_sha256':source_hash,'before':{'vertices':len(mesh.vertices),'polygons':len(mesh.polygons),'triangles':sum(len(p.vertices)-2 for p in mesh.polygons)},'game_integrated':False}

data_kinds=['objects','meshes','armatures','actions','materials','images']
before_append={kind:set(getattr(bpy.data,kind)) for kind in data_kinds}
with bpy.data.libraries.load(str(OLD/'Protagonist_texture_preview.blend'),link=False) as (src,dst):
    dst.objects=['Mannequin']
appended={kind:set(getattr(bpy.data,kind))-before_append[kind] for kind in data_kinds}
reference=dst.objects[0]
ref=reference.data;ref.calc_loop_triangles()
ref_triangles=[tuple(t.vertices) for t in ref.loop_triangles]
ref_uvs=[[ref.uv_layers['CharacterPaint'].data[i].uv.copy() for i in t.loops] for t in ref.loop_triangles]
tree=BVHTree.FromPolygons([v.co for v in ref.vertices],ref_triangles,all_triangles=True)

def baryweights(point,coords):
    q=barycentric_transform(point,*coords,Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1)))
    values=[max(0.0,x) for x in q];total=sum(values)
    return [v/total for v in values] if total else [1,0,0]

weight_repairs=[];weight_normalizations=0
for vertex in mesh.vertices:
    weights={g.group:g.weight for g in vertex.groups if g.weight>0}
    total=sum(weights.values())
    if total<.0001:
        location,normal,tid,distance=tree.find_nearest(vertex.co)
        tri=ref_triangles[tid];ws=baryweights(location,[ref.vertices[i].co for i in tri])
        transferred=defaultdict(float)
        for factor,index in zip(ws,tri):
            for group in ref.vertices[index].groups:
                transferred[reference.vertex_groups[group.group].name]+=factor*group.weight
        chosen=sorted(transferred.items(),key=lambda item:item[1],reverse=True)[:4]
        total=sum(w for _,w in chosen)
        assert total>.0001,'No skin weights on transfer source'
        for name,weight in chosen:
            body.vertex_groups[name].add([vertex.index],weight/total,'REPLACE')
        weight_repairs.append({'vertex':vertex.index,'position':list(vertex.co),'weights':{n:w/total for n,w in chosen}})
    elif abs(total-1)>1e-5:
        for index,weight in weights.items():body.vertex_groups[index].add([vertex.index],weight/total,'REPLACE')
        weight_normalizations+=1
report['weight_repairs']=weight_repairs
report['existing_weight_totals_normalized']=weight_normalizations

# Welding only identical positions and identical normalized skin weights retains
# the silhouette and deformation. Per-corner attributes remain per-corner.
bm=bmesh.new();bm.from_mesh(mesh);bm.verts.ensure_lookup_table();bm.faces.ensure_lookup_table()
deform=bm.verts.layers.deform.active
buckets=defaultdict(list)
for vertex in bm.verts:
    weights=tuple(sorted((int(k),round(w,6)) for k,w in vertex[deform].items() if w>1e-8))
    buckets[(poskey(vertex.co),weights)].append(vertex)
merge_map={v:verts[0] for verts in buckets.values() for v in verts[1:]}
bmesh.ops.weld_verts(bm,targetmap=merge_map)
report['duplicate_vertices_welded']=len(merge_map)
bm.verts.ensure_lookup_table();bm.edges.ensure_lookup_table();bm.faces.ensure_lookup_table()

# A pre-existing dangling neck triangle is attached by just one edge. Removing
# this extra face closes the intended underlying manifold surface.
strays=[f for f in bm.faces if sum(e.is_boundary for e in f.edges)==2 and any(len(e.link_faces)>2 for e in f.edges)]
assert len(strays)<=1,'Unexpected extra faces need inspection'
report['stray_faces_removed']=[[[float(c) for c in v.co] for v in f.verts] for f in strays]
if strays:bmesh.ops.delete(bm,geom=strays,context='FACES_ONLY')
loose_edges=[e for e in bm.edges if not e.link_faces]
if loose_edges:bmesh.ops.delete(bm,geom=loose_edges,context='EDGES')
loose_vertices=[v for v in bm.verts if not v.link_faces]
if loose_vertices:bmesh.ops.delete(bm,geom=loose_vertices,context='VERTS')
bm.faces.ensure_lookup_table();bm.normal_update()
old_normals={f:f.normal.copy() for f in bm.faces}
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bm.normal_update()
report['reversed_faces_corrected']=sum(old_normals[f].dot(f.normal)<-.5 for f in bm.faces)
assert not any(not e.is_manifold for e in bm.edges),'Unresolved nonmanifold geometry'
assert not any(e.is_manifold and not e.is_contiguous for e in bm.edges),'Unresolved face winding'
assert not any(f.calc_area()<1e-12 for f in bm.faces),'Degenerate polygons'
bm.to_mesh(mesh);bm.free();mesh.update()
if mesh.attributes.get('custom_normal'):
    mesh.attributes.remove(mesh.attributes['custom_normal'])
mesh.update()
# Preserve the faceted shading chosen in the user file. Do not smooth its shape.
assert all(not p.use_smooth for p in mesh.polygons)

# UV islands on the previous painting mesh make transfer seam-aware.
parent=list(range(len(ref_triangles)))
def find(x):
    while parent[x]!=x:parent[x]=parent[parent[x]];x=parent[x]
    return x
def union(a,b):parent[find(b)]=find(a)
edges={}
for i,(tri,uvs) in enumerate(zip(ref_triangles,ref_uvs)):
    for a,b in [(0,1),(1,2),(2,0)]:
        endpoint=[(tri[k],tuple(round(float(v),6) for v in uvs[k])) for k in [a,b]]
        key=tuple(sorted(endpoint))
        if key in edges:union(i,edges[key])
        else:edges[key]=i
islands=[find(i) for i in range(len(parent))]
island_triangles=defaultdict(list)
for i,island in enumerate(islands):island_triangles[island].append(i)
uv_at_position=defaultdict(list)
for tid,tri in enumerate(ref_triangles):
    for corner,index in enumerate(tri):uv_at_position[poskey(ref.vertices[index].co)].append((islands[tid],ref_uvs[tid][corner]))
island_trees={}
def project_uv(point,island):
    if island not in island_trees:
        ids=island_triangles[island]
        island_trees[island]=(BVHTree.FromPolygons([v.co for v in ref.vertices],[ref_triangles[i] for i in ids],all_triangles=True),ids)
    local_tree,ids=island_trees[island]
    co,normal,local_tid,distance=local_tree.find_nearest(point)
    tid=ids[local_tid]
    ws=baryweights(co,[ref.vertices[i].co for i in ref_triangles[tid]])
    return sum((uv*w for uv,w in zip(ref_uvs[tid],ws)),Vector((0,0)))

# A joined polygon cannot carry two UVs at the same corner. Split only polygons
# crossing an old atlas seam along their existing render triangulation.
triangle_lookup={}
for tid,tri in enumerate(ref_triangles):
    keys=[poskey(ref.vertices[i].co) for i in tri]
    triangle_lookup[tuple(sorted(keys))]=dict(zip(keys,ref_uvs[tid]))
mesh.calc_loop_triangles()
per_polygon=defaultdict(list)
for t in mesh.loop_triangles:per_polygon[t.polygon_index].append(tuple(t.vertices))
seam_polygons=[]
for polygon in mesh.polygons:
    if len(polygon.vertices)==3:continue
    choices={};conflict=False
    for tri in per_polygon[polygon.index]:
        keys=[poskey(mesh.vertices[i].co) for i in tri]
        match=triangle_lookup.get(tuple(sorted(keys)))
        if not match:continue
        for k in keys:
            if k in choices and (choices[k]-match[k]).length>1e-5:conflict=True
            choices[k]=match[k]
    if conflict:seam_polygons.append(polygon.index)
report['uv_seam_polygons_split']=len(seam_polygons)
report['uv_seam_split_face_positions']=[[[float(c) for c in mesh.vertices[i].co] for i in mesh.polygons[pid].vertices] for pid in seam_polygons]
if seam_polygons:
    bm=bmesh.new();bm.from_mesh(mesh);bm.faces.ensure_lookup_table();bm.verts.ensure_lookup_table()
    targets=[(bm.faces[pid],per_polygon[pid]) for pid in seam_polygons]
    for face,tris in targets:
        material_index=face.material_index;smooth=face.smooth
        uv_layers=list(bm.loops.layers.uv.values())
        old_uv={l.vert.index:[l[layer].uv.copy() for layer in uv_layers] for l in face.loops}
        bm.faces.remove(face)
        for tri in tris:
            new_face=bm.faces.new([bm.verts[i] for i in tri]);new_face.material_index=material_index;new_face.smooth=smooth
            for loop in new_face.loops:
                for layer,value in zip(uv_layers,old_uv[loop.vert.index]):loop[layer].uv=value
    bm.normal_update();bm.to_mesh(mesh);bm.free();mesh.update()
layer=mesh.uv_layers.new(name='CharacterPaint')
exact=projected=0
for polygon in mesh.polygons:
    co,normal,tid,distance=tree.find_nearest(polygon.center)
    island=islands[tid]
    for li in polygon.loop_indices:
        p=mesh.vertices[mesh.loops[li].vertex_index].co
        candidates=[uv for sid,uv in uv_at_position.get(poskey(p),[]) if sid==island]
        if candidates:
            layer.data[li].uv=candidates[0];exact+=1
        else:
            layer.data[li].uv=project_uv(p,island);projected+=1
layer.active_render=True;mesh.uv_layers.active=layer
report['uv_transfer']={'exact_corners':exact,'projected_corners':projected,'source':str(OLD/'Protagonist_texture_preview.blend')}

# Exact triangle correspondence disambiguates UV seams on unchanged surfaces.
# A spatial nearest lookup alone can choose the other side of a packed island.
triangle_lookup={}
for tid,tri in enumerate(ref_triangles):
    keys=[poskey(ref.vertices[i].co) for i in tri]
    triangle_lookup[tuple(sorted(keys))]=dict(zip(keys,ref_uvs[tid]))
mesh.calc_loop_triangles()
exact_triangle_corners=0
for triangle in mesh.loop_triangles:
    keys=[poskey(mesh.vertices[i].co) for i in triangle.vertices]
    match=triangle_lookup.get(tuple(sorted(keys)))
    if match:
        for li,k in zip(triangle.loops,keys):
            layer.data[li].uv=match[k];exact_triangle_corners+=1
report['uv_transfer']['matched_triangle_corners']=exact_triangle_corners

# Register the existing painted eyes, nose and mouth to the new facial features.
# This changes only UV coordinates. Ray projection avoids pinching at the new
# protruding nose, where nearest-surface lookup alone is not sufficient.
def smoothstep(value):
    value=max(0.0,min(1.0,value));return value*value*(3-2*value)
face_registered=0
for polygon in mesh.polygons:
    if polygon.center.z<1.54 or polygon.center.y>.045:continue
    for li in polygon.loop_indices:
        p=mesh.vertices[mesh.loops[li].vertex_index].co
        amount=smoothstep((p.z-1.555)/.04)*smoothstep((1.79-p.z)/.035)*smoothstep((-.015-p.y)/.035)*smoothstep((.085-abs(p.x))/.02)
        if amount<1e-5:continue
        angle=.03;z=p.z-1.67
        qx=math.cos(angle)*p.x-math.sin(angle)*z-.003
        qz=math.sin(angle)*p.x+math.cos(angle)*z+1.687
        co,normal,tid,distance=tree.ray_cast(Vector((qx,-1,qz)),Vector((0,1,0)))
        if tid is None:continue
        weights=baryweights(co,[ref.vertices[i].co for i in ref_triangles[tid]])
        registered=sum((uv*w for uv,w in zip(ref_uvs[tid],weights)),Vector((0,0)))
        # Blend within the same UV island; never interpolate across a seam.
        _,_,base_tid,_=tree.find_nearest(polygon.center)
        if islands[tid]!=islands[base_tid]:continue
        layer.data[li].uv=layer.data[li].uv.lerp(registered,amount)
        face_registered+=1
report['uv_transfer']['facial_corners_registered']=face_registered

shutil.copy2(OLD/'Protagonist_BaseColor_512.png',OUT/'Protagonist_BaseColor_512.png')
image=bpy.data.images.load(str(OUT/'Protagonist_BaseColor_512.png'),check_existing=False)
image.name='Protagonist_Face_BaseColor_512';image.colorspace_settings.name='sRGB';image.pack()
for material in mesh.materials:
    material.use_nodes=True;nodes=material.node_tree.nodes;links=material.node_tree.links
    bsdf=nodes.get('Principled BSDF')
    tex=nodes.new('ShaderNodeTexImage');tex.name='Player Base Color';tex.image=image;tex.interpolation='Closest';tex.extension='EXTEND'
    uv=nodes.new('ShaderNodeUVMap');uv.uv_map='CharacterPaint';uv.location=(-600,0);tex.location=(-400,0)
    links.new(uv.outputs['UV'],tex.inputs['Vector']);links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    bsdf.inputs['Metallic'].default_value=0;bsdf.inputs['Roughness'].default_value=.88;bsdf.inputs['Specular IOR Level'].default_value=.15
    nodes.active=tex;tex.select=True

# Remove the appended reference object, not the original assets on disk.
for kind in data_kinds:
    collection=getattr(bpy.data,kind)
    for block in appended[kind]:collection.remove(block,do_unlink=True)
for ob in bpy.context.scene.objects:ob.hide_render=ob.type=='MESH' and ob!=body
arm.data.pose_position='REST'
assert rig_signature()==rig_before
new_positions={poskey(v.co) for v in mesh.vertices}
assert new_positions.issubset(original_positions),'Repair moved or introduced vertices'
report['surface_vertices_moved']=0
report['rig_preserved']=True
report['after']={'vertices':len(mesh.vertices),'polygons':len(mesh.polygons),'triangles':sum(len(p.vertices)-2 for p in mesh.polygons),'bones':len(arm.data.bones),'unweighted_vertices':sum(sum(g.weight for g in v.groups)<.0001 for v in mesh.vertices),'custom_normals':mesh.has_custom_normals,'uv_layers':[u.name for u in mesh.uv_layers]}
report['after']['actions']=len(bpy.data.actions)
report['after']['armature_objects']=sum(ob.type=='ARMATURE' for ob in bpy.data.objects)
assert report['after']['unweighted_vertices']==0
report['texture_sha256']=hashlib.sha256((OUT/'Protagonist_BaseColor_512.png').read_bytes()).hexdigest()
report['texture_pixels_reused_exactly']=report['texture_sha256']==hashlib.sha256((OLD/'Protagonist_BaseColor_512.png').read_bytes()).hexdigest()
(OUT/'repair_report.json').write_text(json.dumps(report,indent=2))

for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='IMAGE_EDITOR':area.spaces.active.image=image
        elif area.type=='VIEW_3D':
            area.spaces.active.shading.type='MATERIAL'
            area.spaces.active.overlay.show_overlays=False
bpy.context.view_layer.objects.active=body
for ob in bpy.context.view_layer.objects:ob.select_set(ob==body)
bpy.context.scene.tool_settings.image_paint.mode='MATERIAL';bpy.context.scene.tool_settings.image_paint.canvas=image
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'UAL_face_textured_repaired.blend'))
assert hashlib.sha256(source_path.read_bytes()).hexdigest()==source_hash
print('REPAIR_COMPLETE',json.dumps({k:v for k,v in report.items() if k not in ['weight_repairs','uv_seam_split_face_positions']}),flush=True)
os._exit(0)
