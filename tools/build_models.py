"""Generate original flat-shaded, node-rigged GLB assets using Python's stdlib.
Run from any directory: python3 tools/build_models.py. Units are meters, +Y up,
-Z forward. GLB assets can be imported into Blender; no runtime Python needed.
"""
from pathlib import Path
import json
import math
import struct

OUT = Path(__file__).resolve().parents[1] / 'assets' / 'models'


def sub(a, b): return tuple(x-y for x,y in zip(a,b))
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def normal(a,b,c):
    v = cross(sub(b,a),sub(c,a))
    length = math.sqrt(sum(x*x for x in v)) or 1
    return tuple(x/length for x in v)


class Model:
    def __init__(self):
        self.data = bytearray()
        self.doc = {'asset':{'version':'2.0','generator':'Ashen Courtyard original mesh builder'},
                    'scene':0,'scenes':[{'nodes':[]}], 'nodes':[], 'meshes':[],
                    'materials':[], 'bufferViews':[], 'accessors':[]}

    def material(self, name, rgb, metal=0.0, glow=False):
        c = [int(rgb[i:i+2],16)/255 for i in (0,2,4)]
        m = {'name':name,'pbrMetallicRoughness':{'baseColorFactor':c+[1],
              'metallicFactor':metal,'roughnessFactor':0.67 if metal else 0.9}}
        if glow: m['emissiveFactor'] = c
        self.doc['materials'].append(m)
        return len(self.doc['materials'])-1

    def node(self, name, parent=None, pos=(0,0,0), mesh=None):
        n = {'name':name,'translation':list(pos)}
        if mesh is not None: n['mesh'] = mesh
        idx = len(self.doc['nodes'])
        self.doc['nodes'].append(n)
        if parent is None: self.doc['scenes'][0]['nodes'].append(idx)
        else: self.doc['nodes'][parent].setdefault('children',[]).append(idx)
        return idx

    def floats(self, values, count, bounds=False):
        while len(self.data)%4: self.data.append(0)
        offset=len(self.data)
        self.data.extend(struct.pack('<'+'f'*len(values),*values))
        vi=len(self.doc['bufferViews'])
        self.doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(values)*4,'target':34962})
        a={'bufferView':vi,'componentType':5126,'count':count,'type':'VEC3'}
        if bounds:
            a['min']=[min(values[i::3]) for i in range(3)]
            a['max']=[max(values[i::3]) for i in range(3)]
        ai=len(self.doc['accessors'])
        self.doc['accessors'].append(a)
        return ai

    def mesh(self, name, vertices, faces, mat, parent, pos=(0,0,0)):
        positions=[]
        normals=[]
        for face in faces:
            for j in range(1,len(face)-1):
                tri=[vertices[face[k]] for k in (0,j,j+1)]
                n=normal(*tri)
                for v in tri: positions.extend(v); normals.extend(n)
        pa=self.floats(positions,len(positions)//3,True)
        na=self.floats(normals,len(normals)//3)
        mi=len(self.doc['meshes'])
        self.doc['meshes'].append({'name':name,'primitives':[{'attributes':{'POSITION':pa,'NORMAL':na},'material':mat}]})
        return self.node(name,parent,pos,mi)

    def rings(self,name,profiles,mat,parent,pos=(0,0,0),sides=8):
        # Profile tuples are (height, half-width, half-depth, depth-center).
        verts=[]
        for y,rx,rz,cz in profiles:
            for i in range(sides):
                angle=2*math.pi*i/sides+math.pi/8
                verts.append((rx*math.cos(angle),y,cz+rz*math.sin(angle)))
        faces=[list(range(sides))]
        for row in range(len(profiles)-1):
            for i in range(sides):
                a=row*sides+i; b=row*sides+(i+1)%sides
                faces.append([a,a+sides,b+sides,b])
        faces.append(list(reversed(range((len(profiles)-1)*sides,len(profiles)*sides))))
        return self.mesh(name,verts,faces,mat,parent,pos)

    def box(self,name,size,mat,parent,pos=(0,0,0)):
        x,y,z=(v/2 for v in size)
        v=[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]
        f=[[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[0,1,5,4],[3,7,6,2]]
        return self.mesh(name,v,f,mat,parent,pos)

    def cloth(self,name,rows,mat,parent):
        # Double-sided solid fabric with alternating creases and pointed hem.
        verts=[]
        for y,w,z in rows:
            verts.extend([(-w,y,z),(0,y-0.035,z+0.055),(w,y,z)])
        faces=[]
        for r in range(len(rows)-1):
            for i in range(2):
                a=r*3+i; b=a+1; c=a+4; d=a+3
                faces.extend([[a,b,c],[a,c,d],[c,b,a],[d,c,a]])
        return self.mesh(name,verts,faces,mat,parent)

    def save(self,filename):
        self.doc['buffers']=[{'byteLength':len(self.data)}]
        js=json.dumps(self.doc,separators=(',',':')).encode()
        js+=b' '*((-len(js))%4)
        data=bytes(self.data)+b'\0'*((-len(self.data))%4)
        length=12+8+len(js)+8+len(data)
        out=struct.pack('<III',0x46546c67,2,length)+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(data),0x004e4942)+data
        (OUT/filename).write_bytes(out)
        triangles=sum(self.doc['accessors'][p['attributes']['POSITION']]['count']//3 for m in self.doc['meshes'] for p in m['primitives'])
        print(f'{filename}: {triangles} triangles, {len(out):,} bytes')


def build(boss=False):
    m=Model()
    steel=m.material('Obsidian iron' if boss else 'Blue steel','35363d' if boss else '678494',.65)
    edge=m.material('Worn armor edges','77706a' if boss else 'b4c8ce',.7)
    shadow=m.material('Chainmail and joints','191c25',.25)
    gold=m.material('Tarnished brass','af7c41' if boss else 'bb9c5a',.65)
    fabric=m.material('Oxblood cape' if boss else 'Teal cape','602c38' if boss else '245065')
    eyes=m.material('Ember visor' if boss else 'Azure visor','ff9f3b' if boss else '77ddeb',glow=True)
    blade=m.material('Sword steel','92929c' if boss else 'cfdee2',.8)
    root=m.node('KnightRig')
    chest=m.node('Chest',root)
    wide=1.15 if boss else 1.0
    m.rings('Gambeson',[(.77,.22,.14,0),(1.34,.29,.17,0)],shadow,chest)
    m.rings('Breastplate',[(.9,.25,.17,0),(1.02,.29,.21,0),(1.30,.35*wide,.22,0),(1.43,.28,.15,0)],steel,chest)
    # Raised central keel and gorget give the plate a strong readable silhouette.
    m.mesh('BreastplateRidge',[(-.21,1.34,-.19),(0,1.39,-.27),(.21,1.34,-.19),(0,.99,-.25)],[[1,3,0],[2,3,1]],edge,chest)
    m.rings('Gorget',[(1.4,.17,.15,0),(1.5,.18,.14,0)],gold,chest)
    m.rings('WaistBelt',[(.84,.27,.18,0),(.91,.27,.18,0)],shadow,chest)
    m.box('BeltBuckle',(.1,.08,.035),gold,chest,(0,.875,-.186))
    for side in [-1,1]:
        m.rings('HipPlateL' if side<0 else 'HipPlateR',[(.65,.16,.15,0),(.85,.135,.13,0)],steel,chest,(side*.205,0,0))
    m.cloth('Tabard',[(.86,.15,-.195),(.64,.17,-.205),(.43,.13,-.19)],fabric,chest)
    m.box('TabardEmblem',(.035,.18,.01),gold,chest,(0,.68,-.223))
    # Separate leg pivots make walking possible without a skeleton dependency.
    for side,name in [(-1,'LeftLeg'),(1,'RightLeg')]:
        leg=m.node(name,root,(side*.175,.78,0))
        m.rings('Thigh', [(-.30,.105,.115,0),(0,.13,.13,0)],shadow,leg)
        m.rings('Cuisses',[(-.25,.11,.12,-.015),(-.02,.135,.135,0)],steel,leg)
        m.rings('KneeGuard',[(-.38,.1,.13,-.025),(-.3,.125,.155,-.035),(-.25,.10,.12,-.025)],edge,leg)
        m.rings('Greave',[(-.66,.09,.09,0),(-.40,.115,.12,0)],steel,leg)
        m.box('ShinRidge',(.035,.22,.026),gold,leg,(0,-.53,-.112))
        m.rings('Sabatons',[(-.77,.115,.18,-.06),(-.66,.12,.18,-.06),(-.62,.08,.09,0)],edge,leg)
    for side in [-1,1]:
        x=side*(.39 if not boss else .45)
        m.rings('PauldronL' if side<0 else 'PauldronR',[(1.22,.19,.20,0),(1.36,.24 if boss else .2,.23,0),(1.49,.15,.16,0),(1.52,.07,.1,0)],steel,chest,(x,0,0))
        m.rings('ShoulderTrim',[(1.22,.19,.20,0),(1.26,.205,.212,0)],gold,chest,(x,0,0))
        if boss:
            for i in range(3):
                m.rings('ShoulderSpike',[(0,.065,.06,0),(.23+abs(i-1)*.06,.003,.003,0)],edge,chest,(x+side*.07,1.43,-.14+i*.14),sides=4)
    # WeaponPivot remains the interface used by the combat animation scripts.
    for side,name in [(-1,'LeftArm'),(1,'WeaponPivot')]:
        arm=m.node(name,root,(side*(.42 if not boss else .47),1.32,0))
        m.rings('UpperArm',[(-.25,.085,.09,0),(-.04,.11,.105,0)],shadow,arm)
        m.rings('Vambrace',[(-.38,.105,.11,-.11),(-.23,.12,.12,-.03)],steel,arm)
        m.rings('Gauntlet',[(-.46,.095,.10,-.16),(-.36,.11,.11,-.12)],edge,arm)
        if side==1:
            weapon=m.node('Sword',arm,(0,-.40,-.21))
            m.box('Grip',(.08,.085,.24),shadow,weapon,(0,0,.015))
            m.rings('Pommel',[(0,.07,.07,0),(.1,.04,.04,0)],gold,weapon,(0,-.05,.15),sides=6)
            m.box('Crossguard',(.49 if boss else .36,.065,.09),gold,weapon,(0,0,-.105))
            length=1.50 if boss else 1.05
            width=.16 if boss else .085
            # Diamond cross-section with a sharp tip, rather than a box blade.
            v=[(-width,0,-.16),(0,.035,-.16),(width,0,-.16),(0,-.035,-.16),
               (-width*.82,0,-length),(0,.025,-length),(width*.82,0,-length),(0,-.025,-length),(0,0,-length-.24)]
            faces=[[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7],[4,5,8],[5,6,8],[6,7,8],[7,4,8],[3,2,1,0]]
            m.mesh('Blade',v,faces,blade,weapon)
            if boss:
                m.box('EmberFuller',(.035,.008,.95),eyes,weapon,(0,.037,-.72))
    head=m.node('Head',root)
    m.rings('Helmet',[(1.49,.14,.15,0),(1.56,.20,.195,0),(1.77,.21,.20,0),(1.88,.135,.145,.015),(1.91,.035,.05,.02)],steel,head)
    m.mesh('Faceplate',[(-.17,1.72,-.17),(.17,1.72,-.17),(-.14,1.51,-.15),(.14,1.51,-.15),(0,1.69,-.25),(0,1.5,-.2)],[[4,5,2,0],[1,3,5,4]],edge,head)
    m.box('VisorRecess',(.34,.07,.023),shadow,head,(0,1.733,-.192))
    for side in [-1,1]:
        m.box('VisorGlow',(.128,.022,.027),eyes,head,(side*.086,1.735,-.207))
        for i in range(3):
            m.box('Vent',(.011,.046,.012),shadow,head,(side*(.047+i*.027),1.605,-.211+i*.011))
    m.box('NasalGuard',(.035,.21,.035),gold,head,(0,1.678,-.242))
    if boss:
        for side in [-1,1]:
            # Swept segmented horns: elliptical rings shift outward as they rise.
            horn=m.node('CrownHorn',head,(side*.17,1.80,.015))
            verts=[]
            for y,x,z,r in [(0,0,0,.075),(.17,side*.10,.045,.058),(.32,side*.09,.10,.035),(.40,side*.02,.11,.002)]:
                for i in range(6):
                    a=math.tau*i/6
                    verts.append((x+r*math.cos(a),y,z+r*math.sin(a)))
            faces=[]
            for row in range(3):
                for i in range(6):
                    a=row*6+i;b=row*6+(i+1)%6
                    faces.append([a,a+6,b+6,b])
            m.mesh('Horn',verts,faces,gold,horn)
        m.rings('CrownCrest',[(1.85,.06,.07,0),(2.07,.005,.02,0)],gold,head)
    else:
        m.box('HelmetCrest',(.035,.11,.25),gold,head,(0,1.875,.02))
    cape=m.node('Cape',root,(0,0,0))
    m.cloth('Mantle',[(1.41,.27,.18),(1.15,.33,.27),(.7,.40,.34),(.22 if boss else .39,.36,.41)],fabric,cape)
    for side in [-1,1]:
        m.box('CapeClasp',(.07,.055,.045),gold,chest,(side*.225,1.38,-.166))
    m.save('cinder_warden.glb' if boss else 'azure_knight.glb')


if __name__ == '__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    build(False)
    build(True)
