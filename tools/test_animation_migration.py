"""Animation identity/migration tests never rename files in the real project."""
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import art_animation_audit as audit
from art_asset_identity import aliases_for, canonical_path, identity_for_path, legacy_id, load_identities, original_path_for, validate_registry
import migrate_animation_names as migration


def sha(data):
    return hashlib.sha256(data).hexdigest()


def binary_fbx(object_id=1, value=0.0, units=1.0):
    """Tiny valid binary FBX with one animation curve, model, layer and stack."""
    def prop(value):
        if isinstance(value, str):
            raw = value.encode(); return b'S' + struct.pack('<I', len(raw)) + raw
        if isinstance(value, int):
            return b'L' + struct.pack('<q', value)
        return b'D' + struct.pack('<d', value)
    def node(name, properties=(), children=()):
        return name, properties, children
    def encode(spec, position):
        name, properties, children = spec
        raw_name = name.encode(); raw_props = b''.join(prop(v) for v in properties)
        pos = position + 25 + len(raw_name) + len(raw_props)
        content = b''
        for child in children:
            data = encode(child, pos); content += data; pos += len(data)
        tail = bytes(25)
        end = pos + len(tail)
        return struct.pack('<QQQB', end, len(properties), len(raw_props), len(raw_name)) + raw_name + raw_props + content + tail
    nodes = [node('GlobalSettings', children=[node('Properties70', children=[node('P', ['UnitScaleFactor', 'double', 'Number', '', units])])]),
        node('Objects', children=[node('Model', [object_id, 'Hips\x00\x01Model', 'LimbNode']),
            node('AnimationStack', [object_id+1, 'mixamo.com\x00\x01AnimStack', '']),
            node('AnimationLayer', [object_id+2, 'BaseLayer\x00\x01AnimLayer', '']),
            node('AnimationCurveNode', [object_id+3, 'R\x00\x01AnimCurveNode', '']),
            node('AnimationCurve', [object_id+4, '\x00\x01AnimCurve', ''], [node('Default', [value])])]),
        node('Connections', children=[node('C', ['OO', object_id, 0]),node('C', ['OO', object_id+2, object_id+1]),
            node('C', ['OO', object_id+3, object_id+2]),node('C', ['OP', object_id+3, object_id, 'Lcl Rotation']),
            node('C', ['OP', object_id+4, object_id+3, 'd|X'])])]
    data=b'Kaydara FBX Binary  \x00\x1a\x00'+struct.pack('<I',7700)
    for spec in nodes:data += encode(spec, len(data))
    return data + bytes(25)


class IdentityAuditTests(unittest.TestCase):
    def test_identity_aliases_keep_original_id_and_reject_collisions(self):
        old='assets/animations/Mixamo/Jump.fbx';new='assets/animations/Mixamo/anim_jump_v01.fbx'
        registry={'version':1,'entries':[dict(id=legacy_id(old),original_path=old,path=new,aliases=[old],source_sha256='0'*64)]}
        validate_registry(registry)
        for path in (old,new):
            self.assertEqual(identity_for_path('.',path,registry),legacy_id(old))
            self.assertEqual(original_path_for('.',path,registry),old)
            self.assertEqual(canonical_path('.',path,registry),new)
            self.assertEqual(aliases_for('.',path,registry),[old])
        self.assertEqual(identity_for_path('.','unregistered.glb',registry),legacy_id('unregistered.glb'))
        collision=deepcopy(registry);collision['entries'].append({**registry['entries'][0],'id':'art:'+'1'*24})
        with self.assertRaises(ValueError):validate_registry(collision)
        unsafe=deepcopy(registry);unsafe['entries'][0]['path']='../outside.fbx'
        with self.assertRaises(ValueError):validate_registry(unsafe)

    def test_keeper_prioritizes_runtime_references_then_approval_then_clear_name(self):
        clear='assets/animations/Mixamo/Braced Hang Drop.fbx'
        numbered='assets/animations/Mixamo/Braced Hang Drop (1).fbx'
        self.assertEqual(audit.choose_keeper([numbered,clear]),clear)
        self.assertEqual(audit.choose_keeper([numbered,clear],approved={numbered}),numbered)
        self.assertEqual(audit.choose_keeper([numbered,clear],references={clear:['features/player.gd']},approved={numbered}),clear)
        self.assertEqual(audit.choose_keeper([numbered,clear],references={numbered:['features/player.gd']},approved={clear}),numbered)

    def test_fbx_canonicalization_preserves_motion_units_and_route_differences(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);a=root/'a.fbx';b=root/'b.fbx'
            a.write_bytes(binary_fbx(10));b.write_bytes(binary_fbx(500))
            first=audit.inspect(a)
            self.assertEqual(first['signatures'],audit.inspect(b)['signatures'])
            b.write_bytes(binary_fbx(500,value=0.5))
            self.assertNotEqual(first['signatures']['AnimationCurve'],audit.inspect(b)['signatures']['AnimationCurve'])
            b.write_bytes(binary_fbx(500,units=100.0))
            self.assertNotEqual(first['signatures']['GlobalSettings'],audit.inspect(b)['signatures']['GlobalSettings'])

    @unittest.skipUnless((Path(__file__).resolve().parents[1]/'.artifacts/toolchain/godot').is_file(), 'Godot is unavailable')
    def test_godot_builder_output_follows_registry_without_renaming_clip(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'tools').mkdir();(root/'assets/animations').mkdir(parents=True)
            (root/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Identity test"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
            helper=Path(__file__).parent/'animation_asset_paths.gd'
            (root/'tools/animation_asset_paths.gd').write_bytes(helper.read_bytes())
            registry={'version':1,'entries':[dict(id='art:'+'a'*24,original_path='assets/animations/jog.tres',path='assets/animations/anim_jog_v01.tres',aliases=['assets/animations/jog.tres'],source_sha256='0'*64)]}
            (root/'tools/art_asset_identities.json').write_text(json.dumps(registry))
            (root/'test.gd').write_text('''extends SceneTree
func _initialize():
 var helper = load("res://tools/animation_asset_paths.gd")
 var animation = Animation.new()
 animation.resource_name = "jog"
 var result = helper.save(animation, "res://assets/animations/jog.tres")
 if result != OK or FileAccess.file_exists("res://assets/animations/jog.tres"):
  quit(1)
  return
 var saved = load("res://assets/animations/anim_jog_v01.tres")
 if saved == null or saved.resource_name != "jog":
  quit(2)
  return
 quit(0)
''')
            godot=Path(__file__).resolve().parents[1]/'.artifacts/toolchain/godot'
            result=subprocess.run([str(godot),'--headless','--path',str(root),'--script','res://test.gd','--log-file',str(root/'godot.log')],capture_output=True,text=True,timeout=30,env={**os.environ,'XDG_DATA_HOME':str(root/'userdata')})
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertNotIn('SCRIPT ERROR',result.stdout+result.stderr)

    def test_audit_requires_current_pose_hashes_and_preserves_sources(self):
        with tempfile.TemporaryDirectory()as directory:
            root=Path(directory);folder=root/'assets/animations/Mixamo';folder.mkdir(parents=True)
            a=folder/'Jump.fbx';b=folder/'Jump (1).fbx';a.write_bytes(binary_fbx(10));b.write_bytes(binary_fbx(500))
            before={p.name:p.read_bytes()for p in(a,b)}
            report=audit.audit(root);group=report['groups'][0]
            self.assertEqual(group['status'],'candidate');self.assertFalse(group['duplicate_file_eligible'])
            proof=dict(version=1,groups=[dict(members=group['members'],member_sha256=group['member_sha256'],verified=True,evidence=['Godot pose fixture matched'])])
            self.assertEqual(audit.audit(root,proof)['groups'][0]['status'],'verified_duplicate')
            proof['groups'][0]['member_sha256']={key:'0'*64 for key in group['members']}
            self.assertEqual(audit.audit(root,proof)['groups'][0]['status'],'candidate')
            self.assertEqual({p.name:p.read_bytes()for p in(a,b)},before)
            b.write_bytes(binary_fbx(500,value=0.5))
            self.assertEqual(audit.audit(root)['groups'][0]['status'],'distinct_variant')


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory();self.addCleanup(self.directory.cleanup);self.root=Path(self.directory.name)
        self.old='assets/animations/Mixamo/Jump To Hang.fbx';self.new='assets/animations/Mixamo/anim_mixamo_jump_to_free_hang_v01.fbx'
        self.raw=b'original binary\x00data';self.put(self.old,self.raw)
        self.put(self.old+'.import',('[remap]\nuid="uid://keepme"\nsource_file="res://'+self.old+'"\n').encode())
        self.put('features/action.gd',('var file = preload("res://'+self.old+'")\n').encode())
        self.put('docs/reference.md',('Current animation: '+self.old+'\n').encode())
        for path in ('docs/tracker/tracking.json','docs/tracker/previews/provenance.json','assets/third_party/vendor/README.md'):
            self.put(path,('Historical path: '+self.old).encode())
        self.registry={'version':1,'entries':[dict(id=legacy_id(self.old),original_path=self.old,path=self.new,aliases=[self.old],source_sha256=sha(self.raw))]}
        self.put(migration.PLAN,json.dumps(self.registry).encode());self.registry_path=self.root/migration.PLAN

    def put(self,path,data):
        target=self.root/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data);return target

    def plan(self):return migration.plan_migration(self.root,self.registry_path)

    def snapshot(self):return {p.relative_to(self.root).as_posix():p.read_bytes()for p in self.root.rglob('*')if p.is_file()and'.artifacts'not in p.parts}

    def test_dry_run_apply_rollback_preserve_bytes_uids_ids_and_provenance(self):
        before=self.snapshot();plan=self.plan();self.assertEqual(self.snapshot(),before)
        self.assertEqual(len(plan['moves']),2)
        journal=migration.apply_migration(plan)
        self.assertEqual((self.root/self.new).read_bytes(),self.raw);self.assertFalse((self.root/self.old).exists())
        sidecar=(self.root/(self.new+'.import')).read_text()
        self.assertIn('uid://keepme',sidecar);self.assertIn(self.new,sidecar);self.assertNotIn(self.old,sidecar)
        self.assertIn(self.new,(self.root/'features/action.gd').read_text())
        self.assertIn(self.new,(self.root/'docs/reference.md').read_text())
        self.assertEqual(identity_for_path(self.root,self.new),legacy_id(self.old))
        for path in ('docs/tracker/tracking.json','docs/tracker/previews/provenance.json','assets/third_party/vendor/README.md',migration.PLAN):
            self.assertEqual((self.root/path).read_bytes(),before[path])
        relative=journal.relative_to(self.root).as_posix();verified=migration.verify_migration(self.root,relative);self.assertEqual(verified['binary_sources_unchanged'],1);self.assertEqual(verified['import_uids_preserved'],1);migration.rollback(self.root,relative)
        self.assertEqual(self.snapshot(),before)
        migration.rollback(self.root,relative);self.assertEqual(self.snapshot(),before)

    def test_destinations_stale_sources_and_symlinks_are_rejected(self):
        self.put(self.new,b'other')
        with self.assertRaises(ValueError):self.plan()
        (self.root/self.new).unlink();self.put(self.old,b'changed')
        with self.assertRaises(ValueError):self.plan()
        self.put(self.old,self.raw);outside=self.put('elsewhere.fbx',self.raw);(self.root/self.old).unlink();(self.root/self.old).symlink_to(outside)
        with self.assertRaises(ValueError):self.plan()

    def test_failed_apply_rolls_back_moves_without_overwriting(self):
        before=self.snapshot();plan=self.plan();real=migration._rename_noreplace;calls=0
        def fail_once(source,target):
            nonlocal calls;calls+=1
            if calls==2:raise OSError('simulated move failure')
            return real(source,target)
        with patch.object(migration,'_rename_noreplace',side_effect=fail_once),self.assertRaises(OSError):migration.apply_migration(plan)
        self.assertEqual(self.snapshot(),before)
        journals=list((self.root/'.artifacts').rglob('journal.json'))
        self.assertEqual(json.loads(journals[0].read_text())['status'],'rolled_back')

    def test_reference_edit_after_planning_and_after_apply_are_not_lost(self):
        plan=self.plan();self.put('features/action.gd',b'user edits after planning')
        with self.assertRaises(ValueError):migration.apply_migration(plan)
        self.assertTrue((self.root/self.old).exists());self.assertFalse((self.root/self.new).exists())
        plan=self.plan();journal=migration.apply_migration(plan);self.put('docs/reference.md',b'user edits after applying')
        with self.assertRaises(ValueError):migration.rollback(self.root,journal.relative_to(self.root).as_posix())
        self.assertEqual((self.root/'docs/reference.md').read_bytes(),b'user edits after applying')
        self.assertTrue((self.root/self.new).exists())


if __name__=='__main__':unittest.main()
