#!/usr/bin/env python3
"""Read-only source inspection; writes only an explicit derived audit report.

Structural equality is a candidate, never a deletion decision. A matching Godot
pose report is needed before a duplicate can be offered for Trash review.
"""
import argparse
import os
import tempfile
from datetime import datetime, timezone
from art_asset_identity import load_identities, original_path_for, canonical_path, identity_for_path

import struct,zlib,hashlib,json,collections
from pathlib import Path

def parse(p):
 b=p.read_bytes()
 if len(b)<27 or len(b)>128*1024*1024 or b[:23]!=b'Kaydara FBX Binary  \x00\x1a\x00':
  raise ValueError('Unsupported FBX header or file size')
 version=struct.unpack_from('<I',b,23)[0];wide=version>=7500;head=25 if wide else 13
 def prop(pos):
  if pos>=len(b):raise ValueError('Truncated FBX property')
  t=chr(b[pos]);pos+=1;fmts={'Y':'h','C':'?','I':'i','F':'f','D':'d','L':'q'}
  if t in fmts:
   fmt='<'+fmts[t];return struct.unpack_from(fmt,b,pos)[0],pos+struct.calcsize(fmt)
  if t in 'SR':
   n=struct.unpack_from('<I',b,pos)[0];pos+=4
   if pos+n>len(b):raise ValueError('Truncated FBX string')
   v=b[pos:pos+n];return v.decode('utf8','replace')if t=='S'else v.hex(),pos+n
  if t in 'fdlibc':
   n,enc,length=struct.unpack_from('<III',b,pos);pos+=12
   expected=n*{'f':4,'d':8,'l':8,'i':4,'b':1,'c':1}[t]
   if expected>32*1024*1024 or pos+length>len(b) or enc not in (0,1):raise ValueError('Unsupported FBX array size/encoding')
   v=b[pos:pos+length]
   if enc:
    decoder=zlib.decompressobj();v=decoder.decompress(v,expected+1)
    if not decoder.eof or decoder.unconsumed_tail:raise ValueError('FBX array expansion exceeds its declared size')
   if len(v)!=expected:raise ValueError('FBX array size mismatch')
   return (t,n,v.hex()),pos+length
  raise ValueError(t)
 def node(pos,depth=0):
  if depth>128:raise ValueError('FBX nesting limit exceeded')
  start=pos
  end,n,size=struct.unpack_from('<QQQ'if wide else'<III',b,pos);namelen=b[pos+head-1]
  if not end:return None,pos+head
  if end>len(b) or end<=pos+head or n>100000 or pos+head+namelen+size>end:raise ValueError('Invalid FBX node bounds')
  pos+=head;name=b[pos:pos+namelen].decode();pos+=namelen;props=[]
  for _ in range(n):v,pos=prop(pos);props.append(v)
  children=[]
  while pos<end-head:
   previous=pos;child,pos=node(pos,depth+1)
   if pos<=previous:raise ValueError('FBX child does not advance')
   if child is None:break
   children.append(child)
  return (name,props,children),end
 nodes=[];pos=27
 while pos<len(b)-head:
  n,pos=node(pos)
  if n is None:break
  nodes.append(n)
 return version,{x[0]:x for x in nodes}

def digest(x):
 return hashlib.sha256(json.dumps(x,sort_keys=True).encode()).hexdigest()

def inspect(p):
 version,top=parse(p);objects=top.get('Objects',('',[],[]))[2];byid={x[1][0]:x for x in objects if x[1]};connections=[x[1]for x in top.get('Connections',('',[],[]))[2]if x[0]=='C'];edges=collections.defaultdict(list)
 for e in connections:
  if len(e)>=3:edges[e[1]].append(e[2:])
 def name(obj):return obj[1][1].split('\x00')[0]
 models={i:x for i,x in byid.items()if x[0]=='Model'}
 def path(i,seen=None):
  seen=seen or set()
  if i in seen:return'cycle'
  seen.add(i);parents=[e[0]for e in edges[i]if e[0]in models]
  return(path(parents[0],seen)+'/'if parents else'')+name(models[i])
 identities={i:'Model:'+path(i)for i in models}
 for kind in ['AnimationStack','AnimationLayer','AnimationCurveNode','AnimationCurve','NodeAttribute']:
  for i,obj in byid.items():
   if obj[0]!=kind:continue
   if kind in {'AnimationCurveNode','AnimationCurve','NodeAttribute'}:
    routes=sorted([[identities.get(e[0],str(e[0])),*e[1:]]for e in edges[i]])
    identities[i]=kind+':'+json.dumps(routes)
   else:identities[i]=kind+':'+name(obj)+':'+str(obj[1][2:])
 for i,obj in byid.items():
  identities.setdefault(i,obj[0]+':'+name(obj)+':'+str(obj[1][2:]))
 duplicateids=[k for k,n in collections.Counter(identities.values()).items()if n>1]
 objectgroups=collections.defaultdict(list)
 for i,obj in byid.items():
  # Remaining props preserve the authored name, subtype and all values; the
  # first numeric object ID is the only omitted declaration field.
  objectgroups[obj[0]].append([identities[i],obj[1][1:],obj[2]])
 signatures={k:digest(sorted(v))for k,v in objectgroups.items()}
 routing=[]
 for c in connections:
  routing.append([c[0],identities.get(c[1],str(c[1])),identities.get(c[2],str(c[2])),*c[3:]])
 signatures['Connections']=digest(sorted(routing))
 signatures['GlobalSettings']=digest(top.get('GlobalSettings'))
 signatures['Takes']=digest(top.get('Takes'))
 signatures['FBXVersion']=version
 curves=[o for o in objects if o[0]=='AnimationCurve']
 if not curves or not any(o[0]=='AnimationStack'for o in objects):raise ValueError('No playable FBX animation structure')
 fields=collections.Counter(ch[0]for o in curves for ch in o[2])
 globals=[x[1]for ch in top.get('GlobalSettings',('',[],[]))[2]if ch[0]=='Properties70'for x in ch[2]if x[0]=='P']
 stacks=[o[2]for o in objects if o[0]=='AnimationStack'];layers=[o[2]for o in objects if o[0]=='AnimationLayer']
 return dict(signatures=signatures,duplicates=duplicateids,classes=dict(collections.Counter(o[0]for o in objects)),curve_fields=dict(fields),globals=globals,stacks=stacks,layers=layers,routing_count=len(routing))


ROOT = Path(__file__).resolve().parents[1]
MODEL_FORMATS = {'.fbx', '.glb', '.gltf', '.tres'}
AUDIT_VERSION = 1
KNOWN_REDUNDANT = {
 'Braced Hang Drop (1).fbx', 'Braced Hang Hop Left (1).fbx',
 'Braced Hang Hop Right (1).fbx', 'Braced Hang Hop Up (1).fbx',
 'Braced Hang Shimmy.fbx', 'Braced Hang Shimmy(1).fbx',
 'Falling To Landing(1).fbx', 'Jump Braced Hang Wall.fbx',
 'Jumping To Hanging (1).fbx',
}

def sha256(path):
 with Path(path).open('rb') as stream:
  return hashlib.file_digest(stream, 'sha256').hexdigest()

def source_files(root):
 """Discover current project animations plus catalogued model-source libraries."""
 paths=set()
 directory=root/'assets/animations'
 if directory.exists():
  paths.update(p for p in directory.rglob('*') if p.suffix.lower() in MODEL_FORMATS)
 catalog_path=root/'docs/tracker/catalog.json'
 if catalog_path.is_file():
  catalog=json.loads(catalog_path.read_text(encoding='utf-8'))
  for entry in catalog.get('art', []):
   if 'Animations' in entry.get('types',[]) and Path(entry.get('path','')).suffix.lower() in MODEL_FORMATS:
    paths.add(root/entry['path'])
 return sorted(p for p in paths if p.is_file() and not p.is_symlink() and p.resolve().is_relative_to(root)
               and '.artifacts' not in p.parts and 'previews' not in p.parts)

def choose_keeper(members, references=None, approved=None):
 references=references or {};approved=set(approved or ())
 return sorted(members,key=lambda p:(-len(references.get(p,[])),p not in approved,
  Path(p).name in KNOWN_REDUNDANT,bool(__import__('re').search(r'\(\d+\)',p)),p))[0]

def keeper_context(root, records, registry):
 """Prefer explicit runtime references, then saved parent or clip approval."""
 catalog_path=root/'docs/tracker/catalog.json';tracking_path=root/'docs/tracker/tracking.json'
 catalog=json.loads(catalog_path.read_text(encoding='utf-8'))if catalog_path.is_file()else {}
 tracking=json.loads(tracking_path.read_text(encoding='utf-8'))if tracking_path.is_file()else {}
 saved=tracking.get('items',{});approved=set();references={row['path']:[]for row in records}
 for row in records:
  identifier=identity_for_path(root,row['current_path'],registry)
  if saved.get(identifier,{}).get('review_label')=='Approved' or any(
   clip.get('parent_id')==identifier and saved.get(clip['id'],{}).get('review_label')=='Approved'
   for clip in catalog.get('animation_clips',[])):
   approved.add(row['path'])
 runtime=[]
 for directory in ('features','scenes','scripts','assets'):
  folder=root/directory
  if folder.exists():
   runtime.extend(p for p in folder.rglob('*')if p.suffix in {'.gd','.tscn','.tres'}and p.is_file()
    and not p.is_symlink() and 'third_party'not in p.parts)
 if (root/'project.godot').is_file():runtime.append(root/'project.godot')
 for file in runtime:
  text=file.read_text(encoding='utf-8',errors='replace');relative=file.relative_to(root).as_posix()
  for row in records:
   paths={row['path'],row['current_path']}
   if relative in paths:continue
   if any(('"res://'+path+'"')in text or ("'res://"+path+"'")in text for path in paths):
    references[row['path']].append(relative)
 return references,approved,catalog

def unresolved_clip_names(root,catalog,registry):
 names=collections.defaultdict(list)
 for clip in catalog.get('animation_clips',[]):
  name=clip.get('source_clip',{}).get('name','');path=clip.get('path','')
  actual=root/canonical_path(root,path,registry)
  if name and actual.is_file():names[name].append(dict(id=clip['id'],path=original_path_for(root,path,registry),name=name))
 return [dict(name=name,clips=clips,duplicate_file_eligible=False,
  reason='Shared clip name only. No clip-level structural or pose equivalence has been established across these libraries/resources.')
  for name,clips in sorted(names.items())if len({clip['path']for clip in clips})>1]


def pose_match(group, report):
 """Never accept stale hashes, an incomplete group, or a nonboolean verdict."""
 for result in (report or {}).get('groups', []):
  if (set(result.get('members',[]))==set(group['members']) and result.get('verified') is True
      and result.get('member_sha256')==group['member_sha256']
      and isinstance(result.get('evidence'),list) and result['evidence']
      and all(isinstance(v,str) for v in result['evidence'])):
   return result
 return None

def audit(root, pose_report=None):
 root=Path(root).resolve();registry=load_identities(root);records=[];fingerprints=collections.defaultdict(list)
 for path in source_files(root):
  current=path.relative_to(root).as_posix();original=original_path_for(root,current,registry)
  row=dict(path=original,current_path=current,sha256=sha256(path),format=path.suffix.lower())
  if path.suffix.lower()=='.fbx':
   try:
    details=inspect(path)
    connected_ambiguity=[value for value in details['duplicates'] if value!='AnimationCurve:[]']
    if connected_ambiguity:
     raise ValueError('Ambiguous connected object identities')
    row.update(structural_fingerprint=digest(details['signatures']),structure=details)
    fingerprints[row['structural_fingerprint']].append(row)
   except (ValueError,KeyError,IndexError,struct.error,zlib.error,RecursionError,UnicodeError) as error:
    row['audit_error']='Unsupported or malformed FBX: '+str(error)
  records.append(row)
 references,approved,catalog=keeper_context(root,records,registry)
 groups=[];grouped=set()
 for fingerprint,rows in sorted(fingerprints.items()):
  if len(rows)<2:
   continue
  members=sorted(row['path'] for row in rows);grouped.update(members)
  proof=rows[0]['structure']
  evidence=[
   'Exact decoded FBX GlobalSettings match, including coordinate axes, units and time settings.',
   'Complete Model and NodeAttribute properties match, including hierarchy and rest transforms.',
   'AnimationStack timing, AnimationLayer properties and Takes match.',
   'Full animation curve key times, values, default values, interpolation flags, tangent data and reference counts match.',
   f"All {proof['routing_count']} connections match after normalizing file-specific object IDs.",
   'Unconnected unnamed curves are compared as complete multisets; they do not participate in the playback graph.',
  ]
  group=dict(id='animation-duplicate:'+digest(members)[:24],status='candidate',members=members,
    keeper=choose_keeper(members,references,approved),member_sha256={row['path']:row['sha256'] for row in rows},
    structural_fingerprint=fingerprint,evidence=evidence,
    keeper_basis=dict(active_references={member:references.get(member,[])for member in members},approved_members=sorted(set(members)&approved)),
    reason='Matching source animation structure; imported pose verification is still required.',
    duplicate_file_eligible=False)
  checked=pose_match(group,pose_report)
  if checked:
   group.update(status='verified_duplicate',duplicate_file_eligible=True,
     reason='Source structure and imported Godot poses match. Redundant files may be proposed for a separate Trash confirmation.',
     evidence=evidence+checked['evidence'])
   group['pose_verification']={key:value for key,value in checked.items() if key not in {'members','member_sha256','evidence'}}
  groups.append(group)
 # Equal names never establish equal motion. Explicitly retain download suffix
 # variants whose full FBX structure differs, such as left/right shimmy.
 names=collections.defaultdict(list)
 for row in records:
  stem=__import__('re').sub(r'\s*\(\d+\)$','',Path(row['path']).stem).casefold()
  names[(str(Path(row['path']).parent),stem)].append(row)
 for _,rows in sorted(names.items()):
  if len(rows)<2 or not all(row.get('structural_fingerprint') for row in rows):
   continue
  if len({row['structural_fingerprint'] for row in rows})<2:
   continue
  members=sorted(row['path'] for row in rows)
  groups.append(dict(id='animation-variant:'+digest(members)[:24],status='distinct_variant',members=members,
   keeper=choose_keeper(members,references,approved),member_sha256={row['path']:row['sha256']for row in rows},
   evidence=['Similar filenames have different decoded animation structure.'],
   reason='These files must remain separate; a numeric download suffix is not duplicate evidence.',
   duplicate_file_eligible=False))
 # Project animation resources are separate runtime derivatives, even when an
 # exported source uses the same action name.
 for row in records:
  if row['path'].startswith('assets/animations/') and row['format']=='.tres':
   groups.append(dict(id='animation-derived:'+digest(row['path'])[:24],status='derived',members=[row['path']],
    keeper=row['path'],member_sha256={row['path']:row['sha256']},
    evidence=['Project-owned Godot animation resource; source filename equality is not a playback-equivalence test.'],
    reason='Retain runtime animation resources separately from source libraries and browser previews.',
    duplicate_file_eligible=False))
 raw_groups=collections.defaultdict(list)
 for row in records:raw_groups[row['sha256']].append(row['path'])
 return dict(version=AUDIT_VERSION,generated_at=datetime.now(timezone.utc).isoformat(),
   groups=groups,source_count=len(records),fbx_count=sum(row['format']=='.fbx'for row in records),
   exact_file_groups=[dict(sha256=key,members=sorted(paths))for key,paths in raw_groups.items()if len(paths)>1],
   unresolved_clip_name_collisions=unresolved_clip_names(root,catalog,registry),
   coverage='Whole-file hashes cover all listed sources. Structural/pose equivalence applies only to the explicit FBX groups; same-name clips inside GLB/glTF/Godot libraries remain unproven.',
   files=[{key:value for key,value in row.items()if key!='structure'}for row in records],
   policy='Audit only. No files are renamed, deleted or moved to Trash by this tool.')

def write_report(data,path):
 path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
 fd,temp=tempfile.mkstemp(prefix='.'+path.name+'.',dir=path.parent)
 try:
  with os.fdopen(fd,'w',encoding='utf-8')as stream:
   json.dump(data,stream,ensure_ascii=False,indent=2);stream.write('\n');stream.flush();os.fsync(stream.fileno())
  os.replace(temp,path)
 finally:
  if os.path.exists(temp):os.unlink(temp)

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--root',type=Path,default=ROOT)
 parser.add_argument('--output',type=Path,default=Path('docs/tracker/animation_audit.json'))
 parser.add_argument('--pose-report',type=Path)
 parser.add_argument('--print-only',action='store_true')
 args=parser.parse_args()
 proof=json.loads(args.pose_report.read_text(encoding='utf-8'))if args.pose_report else None
 if proof is not None and (proof.get('version')!=1 or not isinstance(proof.get('groups'),list)):
  parser.error('Pose report must contain version 1 and groups.')
 report=audit(args.root,proof)
 if args.print_only:print(json.dumps(report,ensure_ascii=False,indent=2))
 else:
  output=args.output if args.output.is_absolute()else args.root/args.output
  write_report(report,output)
  counts=collections.Counter(group['status']for group in report['groups'])
  print(f"Audited {report['source_count']} source files: {dict(counts)}. No source files changed.")
if __name__=='__main__':main()

