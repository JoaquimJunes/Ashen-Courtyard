#!/usr/bin/env python3
"""Metadata and preparation regressions, using isolated source/preview fixtures."""
import base64
import contextlib
import copy
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

from art_preview_metadata import (CONVERTERS, MANIFEST, VERSION, Fingerprints,
    PreviewMetadata, direct_model, gltf_dependencies, local_path, source_dependencies)
from prepare_art_previews import atomic_json, prepare, rig_dependencies


class PreviewMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in CONVERTERS:
            self.write(name, '[]' if name.endswith('.json') else '# converter fixture')

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def json(self, name, value):
        return self.write(name, json.dumps(value))

    def gltf(self, name='assets/actor.gltf', names=('attack B', 'attack A'), times=(0, 1.5)):
        payload = struct.pack('<' + 'f' * len(times), *times)
        doc = dict(asset={'version': '2.0'}, meshes=[{'primitives': []}], nodes=[{'mesh': 0}],
            buffers=[{'uri': 'data:application/octet-stream;base64,' + base64.b64encode(payload).decode(), 'byteLength': len(payload)}],
            bufferViews=[{'buffer': 0, 'byteLength': len(payload)}],
            accessors=[{'bufferView': 0, 'componentType': 5126, 'type': 'SCALAR', 'count': len(times)}],
            animations=[{'name': n, 'samplers': [{'input': 0, 'output': 0}], 'channels': [{'sampler': 0, 'target': {'node': 0, 'path': 'translation'}}]} for n in names])
        return self.json(name, doc), doc

    def entry(self, relative, **kwargs):
        return dict(path=relative, types=['Animations'], **kwargs)

    def test_exact_clip_order_names_and_duration(self):
        path, doc = self.gltf()
        result = direct_model(self.root, path, Fingerprints(self.root))
        self.assertEqual(result['status'], 'ready')
        self.assertEqual([c['name'] for c in result['clips']], ['attack B', 'attack A'])
        self.assertEqual([c['id'] for c in result['clips']], ['gltf:0', 'gltf:1'])
        self.assertEqual(result['clips'][0]['duration'], 1.5)
        self.assertTrue(result['url'].startswith('../../'))

    def test_single_key_static_pose_and_unnamed_clip_preserved(self):
        path, doc = self.gltf(names=('',), times=(0,))
        descriptor = direct_model(self.root, path, Fingerprints(self.root))
        self.assertEqual(descriptor['status'], 'ready')
        self.assertEqual(descriptor['clips'][0]['name'], '')
        self.assertEqual(descriptor['clips'][0]['duration'], 0)

    def test_external_and_outside_dependencies_rejected(self):
        path, doc = self.gltf()
        for uri in ('https://example.com/image.png', '//example.com/mesh.bin', '../../outside.bin', 'file:///tmp/private', 'buffer.bin?key=secret'):
            with self.subTest(uri=uri):
                doc['images'] = [{'uri': uri}]
                path.write_text(json.dumps(doc))
                result = direct_model(self.root, path, Fingerprints(self.root))
                self.assertEqual(result['status'], 'unavailable')

    def test_local_dependency_affects_fingerprint(self):
        path, doc = self.gltf()
        self.write('assets/texture.png', 'one')
        doc['images'] = [{'uri': 'texture.png'}]
        path.write_text(json.dumps(doc))
        first = direct_model(self.root, path, Fingerprints(self.root))
        self.write('assets/texture.png', 'two')
        second = direct_model(self.root, path, Fingerprints(self.root))
        self.assertNotEqual(first['fingerprint'], second['fingerprint'])

    def test_missing_model_unsupported_target_and_bad_times_fail(self):
        path, original = self.gltf()
        for mutation in ('model', 'target', 'timeline'):
            doc = copy.deepcopy(original)
            if mutation == 'model': doc['meshes'] = []
            elif mutation == 'target': doc['animations'][0]['channels'][0]['target']['path'] = 'visibility'
            else: doc['accessors'][0]['count'] = 99
            path.write_text(json.dumps(doc))
            self.assertEqual(direct_model(self.root, path, Fingerprints(self.root))['status'], 'unavailable')

    def test_animation_extension_is_not_silently_dropped(self):
        path, doc = self.gltf()
        doc['animations'][0]['channels'][0]['target']['extensions'] = {'KHR_animation_pointer': {'pointer': '/materials/0'}}
        path.write_text(json.dumps(doc))
        result = direct_model(self.root, path, Fingerprints(self.root))
        self.assertEqual(result['status'], 'unavailable')
        self.assertIn('unsupported animation extensions', result['reason'])

    def test_resource_dependencies_include_missing_remap(self):
        self.write('assets/actor.fbx', 'source')
        self.write('assets/actor.fbx.import', 'path="res://.godot/imported/actor.scn"')
        self.assertEqual(source_dependencies(self.root, 'assets/actor.fbx'),
                         ['.godot/imported/actor.scn', 'assets/actor.fbx', 'assets/actor.fbx.import'])

    def test_path_restrictions_and_symlink_escape(self):
        for path in ('../outside', '/tmp/private', 'res://../private', 'file\\private'):
            with self.assertRaises(ValueError): local_path(self.root, path)
        (self.root / 'escape').symlink_to('/tmp')
        with self.assertRaises(ValueError): local_path(self.root, 'escape/private')

    def prepare_fixture(self):
        path, doc = self.gltf('assets/input.gltf', names=('actual selected resource',))
        self.write('assets/attack.tres', '[gd_resource type="Animation"]')
        def export(root, jobs, engine):
            results = {}
            for job in jobs:
                chunk = json.dumps(doc).encode(); chunk += b' ' * (-len(chunk) % 4)
                Path(job['output']).write_bytes(struct.pack('<4sIIII', b'glTF', 2, len(chunk) + 20, len(chunk), 0x4E4F534A) + chunk)
                results[job['source']] = dict(status='ready', source=job['source'], model='Fixture', model_path='assets/input.gltf',
                    clips=[dict(id='resource:0', index=0, name='actual selected resource', duration=1.5, loop=False)], dependencies=['assets/input.gltf'])
            return results, ''
        with patch('prepare_art_previews.run_exporter', side_effect=export), contextlib.redirect_stdout(io.StringIO()):
            manifest = prepare(self.root, entries=[self.entry('assets/attack.tres')], engine='/usr/bin/python3')
        return manifest, export

    def test_prepared_cache_source_and_converter_invalidation(self):
        manifest, export = self.prepare_fixture()
        item = self.entry('assets/attack.tres')
        self.assertEqual(PreviewMetadata(self.root).descriptor(item)['status'], 'ready')
        with patch('prepare_art_previews.run_exporter') as runner, contextlib.redirect_stdout(io.StringIO()):
            prepare(self.root, entries=[item], engine='/usr/bin/python3')
            runner.assert_not_called()
        self.write('tools/export_art_previews.gd', '# changed converter')
        self.assertEqual(PreviewMetadata(self.root).descriptor(item)['status'], 'stale')
        self.prepare_fixture()
        self.write('assets/attack.tres', 'changed actual clip')
        self.assertEqual(PreviewMetadata(self.root).descriptor(item)['status'], 'stale')

    def test_converted_clip_name_must_match_exact_export_binding(self):
        manifest, export = self.prepare_fixture()
        def wrong_binding(root, jobs, engine):
            results, error = export(root, jobs, engine)
            for result in results.values():
                result['clips'][0]['export_name'] = 'different-clip-same-duration'
            return results, error
        with patch('prepare_art_previews.run_exporter', side_effect=wrong_binding), contextlib.redirect_stdout(io.StringIO()):
            prepare(self.root, entries=[self.entry('assets/attack.tres')], engine='/usr/bin/python3', force=True)
        result = PreviewMetadata(self.root).descriptor(self.entry('assets/attack.tres'))
        self.assertEqual(result['status'], 'unavailable')
        self.assertIn('identity', result['reason'])

    def test_retarget_provenance_survives_preparation_and_profile_changes_stale_it(self):
        _, export = self.prepare_fixture()
        profile = 'tools/art_preview_retarget_profiles/mixamo_common_v1.json'
        self.json(profile, {'version': 1})
        def retarget_export(root, jobs, engine):
            results, error = export(root, jobs, engine)
            for result in results.values():
                result['dependencies'].append(profile)
                result['provenance'] = dict(kind='retargeted_preview', profile_id='mixamo_common_v1',
                    profile_version=1, source_clips=[{'name': 'actual selected resource', 'duration': 1.5}],
                    label='Retargeted mannequin preview · visual review pending')
            return results, error
        with patch('prepare_art_previews.run_exporter', side_effect=retarget_export), contextlib.redirect_stdout(io.StringIO()):
            prepare(self.root, entries=[self.entry('assets/attack.tres')], engine='/usr/bin/python3', force=True)
        descriptor = PreviewMetadata(self.root).descriptor(self.entry('assets/attack.tres'))
        self.assertEqual(descriptor['provenance']['source_clips'][0]['name'], descriptor['clips'][0]['name'])
        self.assertEqual(descriptor['provenance']['dependency_fingerprint'], descriptor['fingerprint'])
        self.assertNotIn('attention', descriptor)
        self.json(profile, {'version': 2})
        self.assertEqual(PreviewMetadata(self.root).descriptor(self.entry('assets/attack.tres'))['status'], 'stale')

    def test_mixamo_dependencies_track_both_profiles_and_unchanged_reference(self):
        dependencies = rig_dependencies('assets/animations/Mixamo/anim_mixamo_run_with_sword_v01.fbx')
        self.assertIn('assets/models/ual/runtime_rig.tscn', dependencies)
        self.assertIn('assets/models/ual/mannequin_body.res', dependencies)
        self.assertIn('tools/art_preview_retarget_profiles/mixamo_common_v1.json', dependencies)
        self.assertIn('tools/art_preview_retarget_profiles/mixamo_crawl_v1.json', dependencies)
        self.assertEqual(rig_dependencies('assets/unknown.fbx'), [])

    def test_reviewed_crawl_remains_separate_from_generic_retarget(self):
        relative = 'art_source/mixamo/anim_ual_crawl_retarget_reviewed_v01.glb'
        # The authored variant label is descriptive, never an editable approval.
        self.write(relative, 'missing geometry fixture')
        entries = [self.entry(relative, id='original-crawl-id', attention=['Bug found'])]
        PreviewMetadata(self.root).apply(entries)
        self.assertEqual(entries[0]['id'], 'original-crawl-id')
        self.assertEqual(entries[0]['attention'], ['Bug found'])
        self.assertEqual(entries[0]['preview']['provenance']['kind'], 'authored_crawl')
        self.assertNotIn('profile_id', entries[0]['preview']['provenance'])

    def test_atomic_failure_retains_existing_record(self):
        target = self.json('docs/tracker/previews/manifest.json', {'previous': 'working'})
        before = target.read_bytes()
        with patch('prepare_art_previews.os.replace', side_effect=OSError('Disk failure')):
            with self.assertRaises(OSError): atomic_json(target, {'new': 'incomplete'})
        self.assertEqual(target.read_bytes(), before)
        self.assertEqual(list(target.parent.iterdir()), [target])

    def test_missing_or_modified_prepared_output_is_stale(self):
        manifest, _ = self.prepare_fixture()
        output = self.root / manifest['entries']['assets/attack.tres']['output']
        output.write_text('corrupted')
        self.assertEqual(PreviewMetadata(self.root).descriptor(self.entry('assets/attack.tres'))['status'], 'stale')
        output.unlink()
        self.assertEqual(PreviewMetadata(self.root).descriptor(self.entry('assets/attack.tres'))['status'], 'stale')

    def sequence_fixture(self):
        base = 'art_source/ui/concept'
        self.write(base + '/README.md', 'Frames 0 and 1; 60fps; atlas used in sequence')
        self.json(base + '/timing.json', dict(frames=2, fps=60, duration=2 / 60))
        self.write(base + '/frame-0000.png', 'frame0')
        self.write(base + '/frame-0001.png', 'frame1')
        self.write(base + '/atlas.png', 'atlas')
        evidence = [dict(path=base + '/README.md', contains='Frames 0 and 1; 60fps')]
        self.json('tools/art_catalog_sequences.json', [
            dict(pattern=base + '/frame-*.png', evidence=evidence,
                 preview=dict(kind='sequence', sequence='test', frame_from_filename=True,
                 definition=dict(frames_pattern=base + '/frame-*.png', metadata=base + '/timing.json', loop=False))),
            dict(pattern=base + '/atlas.png', evidence=evidence, preview=dict(kind='sequence', sequence='test'))])
        with contextlib.redirect_stdout(io.StringIO()): prepare(self.root, entries=[])
        return base

    def test_sequence_shared_urls_start_frame_and_documented_timing(self):
        base = self.sequence_fixture()
        metadata = PreviewMetadata(self.root)
        frame = metadata.descriptor(self.entry(base + '/frame-0001.png'))
        atlas = metadata.descriptor(self.entry(base + '/atlas.png'))
        self.assertEqual(frame['status'], 'ready')
        self.assertEqual(frame['sequence']['start_frame'], 1)
        self.assertEqual(atlas['sequence']['start_frame'], 0)
        self.assertEqual(frame['sequence']['fps'], 60)
        self.assertEqual(frame['duration'], 2 / 60)
        self.assertNotIn('frames', frame['sequence'])
        manifest = json.loads((self.root / MANIFEST).read_text())
        self.assertEqual(len(manifest['sequences']), 1)
        self.assertEqual(len(manifest['entries']), 3)
        self.assertLess((self.root / MANIFEST).stat().st_size, 5000)

    def test_missing_frame_stales_existing_and_rebuild_marks_incomplete(self):
        base = self.sequence_fixture()
        (self.root / base / 'frame-0001.png').unlink()
        entry = self.entry(base + '/frame-0000.png')
        self.assertEqual(PreviewMetadata(self.root).descriptor(entry)['status'], 'stale')
        with contextlib.redirect_stdout(io.StringIO()): prepare(self.root, entries=[])
        result = PreviewMetadata(self.root).descriptor(entry)
        self.assertEqual(result['status'], 'unavailable')
        self.assertIn('incomplete', result['reason'])
        self.assertEqual(result['sequence']['id'], 'test')

    def test_sequence_identity_survives_missing_first_frame_and_stale_atlas(self):
        base = self.sequence_fixture()
        (self.root / base / 'frame-0000.png').unlink()
        metadata = PreviewMetadata(self.root)
        for filename, status in [('frame-0000.png', 'unavailable'), ('frame-0001.png', 'stale'), ('atlas.png', 'stale')]:
            descriptor = metadata.descriptor(self.entry(base + '/' + filename))
            self.assertEqual(descriptor['status'], status)
            self.assertEqual(descriptor['kind'], 'sequence')
            self.assertEqual(descriptor['sequence']['id'], 'test')
        self.assertEqual(metadata.descriptor(self.entry(base + '/frame-0001.png'))['sequence']['start_frame'], 1)

    def test_missing_original_and_unknown_rig_are_explicit(self):
        metadata = PreviewMetadata(self.root)
        self.assertIn('missing', metadata.descriptor(self.entry('assets/none.glb'))['reason'])
        self.write('assets/unknown.tres', 'unknown rig')
        self.assertIn('prepared', metadata.descriptor(self.entry('assets/unknown.tres'))['reason'])

    def test_apply_changes_only_preview_metadata(self):
        path, _ = self.gltf()
        entry = self.entry('assets/actor.gltf', id='existing-id', note='saved note', status='Ready for review')
        original = copy.deepcopy(entry)
        PreviewMetadata(self.root).apply([entry])
        for key in original: self.assertEqual(original[key], entry[key])
        self.assertEqual(entry['preview']['status'], 'ready')


if __name__ == '__main__':
    unittest.main()
