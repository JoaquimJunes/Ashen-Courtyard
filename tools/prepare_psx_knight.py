"""Repair the CC0 knight's half-mesh GLB; keep its original file untouched.
Mirrors geometry, winding and left/right skin joint indices, then changes the
emission-only photo texture into diffuse albedo for the game's lighting.
"""
from pathlib import Path
import copy,json,struct
ROOT=Path(__file__).resolve().parents[1]/'assets/third_party/fullplate_knight'
b=(ROOT/'knight.glb').read_bytes()
size=struct.unpack_from('<I',b,12)[0]
doc=json.loads(b[20:20+size]);offset=20+size
bin_size=struct.unpack_from('<I',b,offset)[0]
data=bytearray(b[offset+8:offset+8+bin_size])
formats={5126:'f',5123:'H',5121:'B',5125:'I'}
components={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def read(index):
 a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
 fmt='<'+formats[a['componentType']]*components[a['type']]
 start=v.get('byteOffset',0)+a.get('byteOffset',0)
 stride=v.get('byteStride',struct.calcsize(fmt))
 return [list(struct.unpack_from(fmt,data,start+i*stride)) for i in range(a['count'])]
def append(values, source):
 a=copy.deepcopy(doc['accessors'][source]);a.pop('byteOffset',None)
 while len(data)%4:data.append(0)
 start=len(data);fmt='<'+formats[a['componentType']]*components[a['type']]
 for v in values:data.extend(struct.pack(fmt,*v))
 view={'buffer':0,'byteOffset':start,'byteLength':len(data)-start}
 doc['bufferViews'].append(view);a['bufferView']=len(doc['bufferViews'])-1
 if 'min' in a:a['min']=[min(v[i] for v in values) for i in range(len(values[0]))]
 if 'max' in a:a['max']=[max(v[i] for v in values) for i in range(len(values[0]))]
 doc['accessors'].append(a);return len(doc['accessors'])-1
skin=doc['skins'][0];names=[doc['nodes'][i]['name'] for i in skin['joints']]
swap={i:names.index(n[:-2]+('.r' if n.endswith('.l') else '.l')) if n.endswith(('.l','.r')) else i for i,n in enumerate(names)}
for mesh in doc['meshes']:
 for p in list(mesh['primitives']):
  assert min(v[0] for v in read(p['attributes']['POSITION'])) >= -0.001, 'Source no longer needs mirroring'
  mirror=copy.deepcopy(p)
  for key,idx in p['attributes'].items():
   values=read(idx)
   if key in ('POSITION','NORMAL'):
    for v in values:v[0]=-v[0]
   elif key=='JOINTS_0':values=[[swap[x] for x in v] for v in values]
   mirror['attributes'][key]=append(values,idx)
  indices=read(p['indices'])
  for i in range(0,len(indices),3):indices[i+1],indices[i+2]=indices[i+2],indices[i+1]
  mirror['indices']=append(indices,p['indices'])
  mesh['primitives'].append(mirror)
for mat in doc['materials']:
 mat['pbrMetallicRoughness']={'baseColorTexture':mat.pop('emissiveTexture'),'metallicFactor':0,'roughnessFactor':1}
 mat.pop('emissiveFactor',None)
doc['buffers']=[{'byteLength':len(data)}]
doc['asset']['generator']='Ashen Courtyard mirror repair of Luana Coppio CC0 knight'
j=json.dumps(doc,separators=(',',':')).encode();j+=b' '*((-len(j))%4)
data.extend(b'\0'*((-len(data))%4))
out=struct.pack('<III',0x46546c67,2,28+len(j)+len(data))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(data),0x004e4942)+data
(ROOT/'knight_complete.glb').write_bytes(out)
print('Saved complete mirrored knight:',len(out),'bytes')
