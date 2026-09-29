#!/usr/bin/env python3
"""Catalog regression checks use temporary projects and existing source evidence."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import build_progress_tracker as tracker
import art_catalog_metadata as metadata


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.out = self.root / 'docs/tracker'
        self.out.mkdir(parents=True)
        self.source = self.root / 'docs/ACCEPTANCE.md'
        self.source.write_text('# Acceptance\n\n- The character stops safely.\n', encoding='utf-8')
        self.feature = {
            'id': 'running', 'title': 'Running', 'category': 'Gameplay mechanics',
            'subcategory': 'Ground movement', 'status': 'Implemented',
            'summary': 'Existing movement.', 'attention': 'None recorded',
            'note': 'An existing note.', 'sources': ['docs/ACCEPTANCE.md'],
        }
        self.write_json('features.json', [self.feature])
        self.write_json('checklist_seeds.json', {})

    def write_json(self, filename, data):
        (self.out / filename).write_text(json.dumps(data), encoding='utf-8')

    def asset(self, relative, content='fixture'):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding='utf-8')
        return path

    def gltf(self, relative, **fields):
        document = dict(asset={'version': '2.0'}, **fields)
        path = self.asset(relative)
        if path.suffix == '.glb':
            chunk = json.dumps(document).encode('utf-8')
            chunk += b' ' * (-len(chunk) % 4)
            path.write_bytes(struct.pack('<4sIIII', b'glTF', 2, len(chunk) + 20, len(chunk), 0x4E4F534A) + chunk)
        else:
            path.write_text(json.dumps(document), encoding='utf-8')
        return path

    def build(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return tracker.build(self.root)

    def test_feature_content_is_preserved_and_unassessed_is_empty(self):
        result = self.build()['features'][0]
        for key, value in self.feature.items():
            self.assertEqual(result[key], value)
        self.assertEqual(result['area'], 'Gameplay')
        self.assertEqual(result['topic'], 'Movement')
        self.assertEqual(result['checklist'], [])

    def test_art_id_survives_rebuild_content_change_and_rename_is_new(self):
        path = self.asset('art_source/references/pose.png')
        original = self.build()['art'][0]
        expected_id = 'art:' + hashlib.sha256(b'art_source/references/pose.png').hexdigest()[:24]
        self.assertEqual(original['id'], expected_id)
        self.assertEqual(original['role'], 'Reference')
        self.assertEqual(original['origin'], 'Project files')
        self.assertFalse(original['missing'])
        path.write_text('updated pixels', encoding='utf-8')
        self.assertEqual(self.build()['art'][0]['id'], expected_id)
        path.rename(path.with_name('pose-renamed.png'))
        result = {item['path']: item for item in self.build()['art']}
        self.assertTrue(result['art_source/references/pose.png']['missing'])
        self.assertNotEqual(result['art_source/references/pose-renamed.png']['id'], expected_id)

    def test_missing_art_and_notes_are_retained_and_restored(self):
        path = self.asset('assets/third_party/character.glb')
        original = self.build()['art'][0]
        metadata = {'art': {original['id']: {'notes': 'Keep this fitting note.'}}}
        self.write_json('tracking.json', metadata)
        before = (self.out / 'tracking.json').read_bytes()
        path.unlink()
        result = self.build()['art']
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['id'], original['id'])
        self.assertTrue(result[0]['missing'])
        self.assertEqual(result[0]['origin'], 'Third-party library')
        self.assertEqual((self.out / 'tracking.json').read_bytes(), before)
        self.asset('assets/third_party/character.glb')
        restored = self.build()['art'][0]
        self.assertFalse(restored['missing'])
        self.assertEqual(restored['id'], original['id'])

    def test_first_migration_preserves_art_only_present_in_old_data_js(self):
        original = {'title': 'Previous image', 'path': 'assets/old.png',
                    'kind': 'Images', 'origin': 'Project files',
                    'image': True, 'url': '../../assets/old.png'}
        (self.out / 'data.js').write_text('window.TRACKER_DATA = ' + json.dumps({'art': [original]}) + ';\n', encoding='utf-8')
        migrated = self.build()['art'][0]
        for key, value in original.items():
            self.assertEqual(migrated[key], value)
        self.assertTrue(migrated['missing'])
        self.assertEqual(migrated['role'], '')
        self.assertTrue(migrated['id'].startswith('art:'))
        self.assertEqual(self.build()['art'][0], migrated)

    def test_generated_tracker_files_artifacts_and_caches_are_not_scanned(self):
        for relative in ('art_source/.artifacts/test.png', 'assets/vendor/tool.png',
                         'art_source/cache/copy.png', 'assets/.godot/import.png',
                         'art_source/node_modules/package.png', 'docs/tracker/story.md'):
            self.asset(relative)
        self.asset('art_source/own.png')
        result = self.build()['art']
        self.assertEqual([item['path'] for item in result], ['art_source/own.png'])
        self.assertNotIn('status', result[0])
        self.assertNotIn('approval', result[0])
        self.assertEqual(result[0]['role'], '')

    def test_catalog_matches_browser_data_and_rebuild_is_deterministic(self):
        self.asset('assets/item.glb')
        self.build()
        catalog_bytes = (self.out / 'catalog.json').read_bytes()
        data_bytes = (self.out / 'data.js').read_bytes()
        browser_data = json.loads(data_bytes.decode().removeprefix('window.TRACKER_DATA = ').strip().removesuffix(';'))
        self.assertEqual(json.loads(catalog_bytes), browser_data)
        self.build()
        self.assertEqual((self.out / 'catalog.json').read_bytes(), catalog_bytes)
        self.assertEqual((self.out / 'data.js').read_bytes(), data_bytes)

    def test_pack_edits_survive_rebuild_without_becoming_documented(self):
        from art_pack_edits import empty_edits
        paths = [self.asset('art_source/review/first.png'), self.asset('art_source/review/second.png')]
        initial = self.build()
        ids = [entry['id'] for entry in initial['art']]
        edits = empty_edits()
        edits['custom_packs'] = [dict(id='art:pack:user-test', title='My review', members=ids, created_at='2026-09-30')]
        edits['excluded_members'] = {'art:pack:user-test': [ids[0]]}
        self.write_json('pack_edits.json', edits)
        first = self.build()
        self.assertEqual(first['packs'][0]['members'], [ids[1]])
        self.assertEqual(first['packs'][0]['pack_source'], 'custom')
        self.assertEqual(self.build()['packs'], first['packs'])
        paths[1].unlink()
        rebuilt = self.build()
        self.assertEqual(rebuilt['packs'][0]['members'], [ids[1]])
        self.assertEqual(rebuilt['packs'][0]['missing_count'], 1)
        self.assertEqual(json.loads((self.out / 'pack_edits.json').read_text()), edits)
        raw = tracker.build(self.root, write=False, pack_document=empty_edits())
        self.assertEqual(raw['packs'], [])

    def test_nonwriting_build_does_not_touch_generated_or_tracking_files(self):
        self.build()
        before = {path.name: path.read_bytes() for path in self.out.iterdir() if path.is_file()}
        self.asset('art_source/review/new.png')
        data = tracker.build(self.root, write=False)
        self.assertEqual(len(data['art']), 1)
        self.assertEqual({path.name: path.read_bytes() for path in self.out.iterdir() if path.is_file()}, before)

    def test_output_pair_is_restored_when_second_replace_fails(self):
        self.build()
        before = {name: (self.out / name).read_bytes() for name in ('catalog.json', 'data.js')}
        replace = os.replace
        calls = 0
        def fail_second(source, destination):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError('Test catalog replacement failed')
            replace(source, destination)
        with patch.object(tracker.os, 'replace', side_effect=fail_second):
            with self.assertRaisesRegex(OSError, 'replacement failed'):
                tracker.write_catalog(dict(art=[], features=[], packs=[]), self.out)
        self.assertEqual({name: (self.out / name).read_bytes() for name in before}, before)
        self.assertFalse(list(self.out.glob('.*.tmp')))

    def test_html_description_prefers_authored_metadata_and_decodes_entities(self):
        path = self.asset('art_source/ui/index.html', '''<!doctype html><html><head>
            <title>Old &amp; generic title</title>
            <META NAME="description" CONTENT="Health &amp; stamina\n  HUD &lt;preview&gt;">
            </head><body><script>throw new Error("Must not run");</script></body></html>''')
        item = self.build()['art'][0]
        self.assertEqual(item['description'], 'Health & stamina HUD <preview>')
        path.write_text('<title>Authored &quot;HUD&quot; title</title><body>Unrelated text</body>', encoding='utf-8')
        rebuilt = self.build()['art'][0]
        self.assertEqual(rebuilt['description'], 'Authored "HUD" title')
        self.assertEqual(rebuilt['id'], item['id'])
        path.write_text('<body><h1>No metadata</h1><title>Not head metadata</title></body>', encoding='utf-8')
        self.assertEqual(self.build()['art'][0]['description'], '')

    def test_html_description_ignores_embedded_pages_and_limits_read_and_length(self):
        path = self.asset('art_source/ui/index.html', '''<head><title>Outer preview</title></head>
            <body><iframe srcdoc="&lt;title&gt;Inner page&lt;/title&gt;"></iframe>
            <meta name="description" content="Not head metadata"></body>''')
        self.assertEqual(metadata.html_description(path), 'Outer preview')
        path.write_text('<head>' + ' ' * metadata.HTML_HEAD_LIMIT + '<title>Too late</title></head>', encoding='utf-8')
        self.assertEqual(metadata.html_description(path), '')
        path.write_text('<title>' + 'Long title ' * 100 + '</title>', encoding='utf-8')
        description = metadata.html_description(path)
        self.assertLessEqual(len(description), metadata.HTML_DESCRIPTION_LIMIT)
        self.assertTrue(description.endswith('…'))
        path.unlink()
        self.assertEqual(metadata.html_description(path), '')

    def test_texture_evidence_is_specific_and_overlapping(self):
        relatives = ['assets/pack/Textures/albedo.png', 'assets/pack/texture/normal.png',
                     'assets/pack/render.png', 'assets/pack/preview.png',
                     'assets/pack/texture-study.png', 'assets/pack/surface.png',
                     'art_source/ui/panel.png']
        for relative in relatives:
            self.asset(relative)
        self.gltf('assets/pack/model.gltf',
                  images=[{'uri': 'surface.png'}, {'uri': 'preview.png'}],
                  textures=[{'source': 0}, {'source': 1}],
                  materials=[{'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}}}])
        result = {item['path']: item for item in self.build()['art']}
        for relative in relatives[:2] + ['assets/pack/surface.png']:
            self.assertEqual(result[relative]['types'], ['Images', 'Textures'])
        for relative in relatives[2:5] + ['art_source/ui/panel.png']:
            self.assertEqual(result[relative]['types'], ['Images'])
        self.assertEqual(result['art_source/ui/panel.png']['collections'], ['UI'])
        self.assertEqual(result['assets/pack/surface.png']['collections'], [])

    def test_glb_gltf_clips_are_actual_names_and_models_remain_models(self):
        self.gltf('assets/actor.glb', animations=[{'name': 'Walk/Förward'}, {'name': 'Idle'}, {}])
        self.gltf('assets/object.gltf')
        self.gltf('assets/unnamed.gltf', animations=[{}])
        result = {item['path']: item for item in self.build()['art']}
        actor = result['assets/actor.glb']
        self.assertEqual(actor['kind'], 'Models')
        self.assertEqual(actor['types'], ['Models', 'Animations'])
        self.assertEqual(actor['clip_names'], ['Idle', 'Walk/Förward'])
        self.assertEqual(actor['clip_status'], 'available')
        self.assertEqual(result['assets/object.gltf']['types'], ['Models'])
        self.assertEqual(result['assets/object.gltf']['clip_status'], 'not_applicable')
        self.assertEqual(result['assets/unnamed.gltf']['clip_names'], [])
        self.assertEqual(result['assets/unnamed.gltf']['clip_status'], 'available')

    def test_malformed_model_metadata_never_breaks_catalog_or_invents_clips(self):
        for relative, content in [('assets/bad.glb', 'bad'), ('assets/bad.gltf', '{broken'),
                                  ('assets/list.gltf', '[]'), ('assets/not-gltf.gltf', '{}'),
                                  ('assets/unimported.fbx', 'bad'), ('assets/source.blend', 'bad')]:
            self.asset(relative, content)
        self.gltf('assets/wrong-animations.gltf', animations='walk')
        for item in self.build()['art']:
            self.assertEqual(item['types'], ['Models'])
            self.assertEqual(item['clip_names'], [])
            self.assertEqual(item['clip_status'], 'unavailable')

    def test_godot_only_declared_animation_resources_and_actual_names(self):
        self.asset('assets/idle.tres', '[gd_resource type="Animation" format=3]\n\n[resource]\nresource_name = "Rest Pose"\n')
        self.asset('assets/nameless.tres', '[gd_resource type="Animation" format=3]\n\n[resource]\nlength = 1\n')
        self.asset('assets/library.tres', '[gd_resource type="AnimationLibrary" format=3]\n\n[ext_resource type="Animation" path="res://assets/idle.tres" id="1"]\n\n[resource]\n_data = {&"Walk Backward": ExtResource("1")}\n')
        self.asset('assets/animation_profile.tres', '[gd_resource type="Resource" format=3]\n\n[resource]\nresource_name = "Animation profile"\n')
        self.asset('assets/animation_broken.tres', 'not a Godot resource')
        result = {item['path']: item for item in self.build()['art']}
        self.assertEqual(set(result), {'assets/idle.tres', 'assets/nameless.tres', 'assets/library.tres'})
        self.assertEqual(result['assets/idle.tres']['clip_names'], ['Rest Pose'])
        self.assertEqual(result['assets/library.tres']['clip_names'], ['Walk Backward'])
        self.assertEqual(result['assets/nameless.tres']['clip_names'], [])
        for item in result.values():
            self.assertEqual(item['types'], ['Animations'])
            self.assertEqual(item['clip_status'], 'available')

    def test_godot_material_and_linked_obj_material_provide_texture_evidence(self):
        for filename in ('paint.png', 'unused.png', 'rough surface.png', 'render.png'):
            self.asset('assets/pack/' + filename)
        self.asset('assets/pack/paint.tres', '[gd_resource type="StandardMaterial3D" format=3]\n\n[ext_resource type="Texture2D" path="res://assets/pack/paint.png" id="1"]\n[ext_resource type="Texture2D" path="res://assets/pack/unused.png" id="2"]\n\n[resource]\nalbedo_texture = ExtResource("1")\n')
        self.asset('assets/pack/model.obj', 'mtllib model.mtl\n')
        self.asset('assets/pack/model.mtl', 'newmtl surface\nmap_Kd -s 1 1 1 rough surface.png\n')
        self.asset('assets/pack/unlinked.mtl', 'map_Kd render.png\n')
        result = {item['path']: item for item in self.build()['art']}
        for name in ('paint.png', 'rough surface.png'):
            self.assertIn('Textures', result['assets/pack/' + name]['types'])
        for name in ('unused.png', 'render.png'):
            self.assertNotIn('Textures', result['assets/pack/' + name]['types'])

    def test_ui_sequence_requires_explicit_manifest_and_document_evidence(self):
        frame = self.asset('art_source/ui/demo/frames/0001.png')
        still = self.asset('art_source/ui/demo/frames/screenshot.png')
        atlas = self.asset('art_source/ui/demo/atlas.png')
        evidence = self.asset('art_source/ui/demo/README.md', 'An animation sequence and sampled atlas.')
        manifest = self.root / 'manifest.json'
        entries = [dict(pattern='art_source/ui/demo/frames/000[0-9].png',
                        evidence=[dict(path=str(evidence.relative_to(self.root)), contains='animation sequence')]),
                   dict(pattern='art_source/ui/demo/atlas.png', types=['Textures'],
                        evidence=[dict(path=str(evidence.relative_to(self.root)), contains='sampled atlas')])]
        manifest.write_text(json.dumps(entries), encoding='utf-8')
        members = metadata.sequence_members(self.root, manifest)
        self.assertEqual(members, {frame: {'Animations'}, atlas: {'Animations', 'Textures'}})
        self.assertNotIn(still, members)
        with patch.object(metadata, 'sequence_members', return_value=members):
            result = {item['path']: item for item in self.build()['art']}
        self.assertEqual(result['art_source/ui/demo/atlas.png']['types'], ['Images', 'Textures', 'Animations'])
        self.assertEqual(result['art_source/ui/demo/frames/screenshot.png']['types'], ['Images'])
        evidence.write_text('No evidence remains.', encoding='utf-8')
        self.assertEqual(metadata.sequence_members(self.root, manifest), {})

    def test_fbx_uses_imported_metadata_when_available_and_no_filename_fallback(self):
        self.asset('assets/Walking.fbx')
        self.asset('assets/Unknown.fbx')
        with patch.object(metadata, 'imported_fbx_metadata', return_value={'assets/Walking.fbx': {'clip_names': ['mixamo_com']}}):
            result = {item['path']: item for item in self.build()['art']}
        self.assertEqual(result['assets/Walking.fbx']['types'], ['Models', 'Animations'])
        self.assertEqual(result['assets/Walking.fbx']['clip_names'], ['mixamo_com'])
        self.assertEqual(result['assets/Unknown.fbx']['clip_names'], [])
        self.assertEqual(result['assets/Unknown.fbx']['clip_status'], 'unavailable')

    def test_explicit_animation_folders_work_without_imports_or_engine(self):
        self.asset('assets/animations/Mixamo/Walking.fbx')
        self.asset('assets/third_party/KayKit/Animations/rig.glb')
        self.asset('assets/animation/authoring.blend')
        self.asset('assets/animation/reference.png')
        self.asset('assets/animation/shape.obj')
        self.gltf('assets/animation/static.gltf')
        with patch.object(metadata, 'imported_fbx_metadata', return_value={}):
            result = {item['path']: item for item in self.build()['art']}
        for relative in ('assets/animations/Mixamo/Walking.fbx', 'assets/third_party/KayKit/Animations/rig.glb', 'assets/animation/authoring.blend'):
            self.assertEqual(result[relative]['types'], ['Models', 'Animations'])
            self.assertEqual(result[relative]['clip_names'], [])
            self.assertEqual(result[relative]['clip_status'], 'unavailable')
        self.assertEqual(result['assets/animation/reference.png']['types'], ['Images'])
        self.assertEqual(result['assets/animation/shape.obj']['types'], ['Models'])
        self.assertEqual(result['assets/animation/static.gltf']['types'], ['Models'])

    def test_video_dates_and_missing_metadata_retained_with_legacy_id_and_notes(self):
        path = self.asset('art_source/ui/clip.webm')
        os.utime(path, (1700000000, 1700000000))
        item = self.build()['art'][0]
        self.assertEqual(item['types'], ['Videos'])
        self.assertEqual(item['modified_at'], '2023-11-14T22:13:20.000000Z')
        item.update(id='art:legacy-stable-id', catalog_note='Keep this existing annotation.')
        self.write_json('catalog.json', {'art': [item]})
        rebuilt = self.build()['art'][0]
        self.assertEqual(rebuilt, item)
        path.unlink()
        missing = self.build()['art'][0]
        expected = dict(item, missing=True, preview={'status': 'unavailable', 'kind': 'video', 'reason': 'The original asset is missing'})
        expected['thumbnail'] = {'status': 'unavailable', 'reason': 'The original asset is missing'}
        self.assertEqual(missing, expected)

    def test_actual_imported_fbx_reads_clip_not_filename_when_engine_available(self):
        engine = tracker.ROOT / '.artifacts/toolchain/godot'
        imported = tracker.ROOT / '.godot/imported/Crawling.fbx-93d7e3623f894e1b54e145417dfa20e2.scn'
        if not engine.is_file() or not imported.is_file():
            self.skipTest('Optional existing Godot import not available')
        result = metadata.imported_fbx_metadata(tracker.ROOT, [tracker.ROOT / 'assets/animations/Mixamo/anim_mixamo_crawling_v01.fbx'])
        self.assertEqual(result['assets/animations/Mixamo/anim_mixamo_crawling_v01.fbx']['clip_names'], ['mixamo_com'])

    def test_only_source_backed_unchecked_criteria_are_accepted(self):
        seed = {'id': 'running:stopping', 'text': 'The character stops safely.',
                'done': False, 'source': 'docs/ACCEPTANCE.md'}
        self.write_json('checklist_seeds.json', {'running': [seed]})
        self.assertEqual(self.build()['features'][0]['checklist'], [seed])
        seed['text'] = 'Invented behavior.'
        self.write_json('checklist_seeds.json', {'running': [seed]})
        with self.assertRaisesRegex(ValueError, 'no longer matches'):
            self.build()
        seed['text'] = 'The character stops safely.'
        seed['done'] = True
        self.write_json('checklist_seeds.json', {'running': [seed]})
        with self.assertRaisesRegex(ValueError, 'Invalid acceptance seed'):
            self.build()

    def test_invalid_previous_catalog_is_not_overwritten(self):
        (self.out / 'catalog.json').write_text('{broken', encoding='utf-8')
        with self.assertRaises(json.JSONDecodeError):
            self.build()
        self.assertEqual((self.out / 'catalog.json').read_text(), '{broken')

    def test_actual_project_feature_ids_content_and_seed_sources(self):
        original = json.loads((tracker.OUT / 'features.json').read_text(encoding='utf-8'))
        result = tracker.load_features(tracker.ROOT, tracker.OUT)
        self.assertEqual([item['id'] for item in original], [item['id'] for item in result])
        self.assertGreater(sum(len(item['checklist']) for item in result), 0)
        for before, after in zip(original, result):
            for key, value in before.items():
                self.assertEqual(after[key], value)
            self.assertIn(after['area'], {'Systems', 'Gameplay', 'UI'})
            for criterion in after['checklist']:
                self.assertFalse(criterion['done'])
                self.assertTrue((tracker.ROOT / criterion['source']).is_file())


if __name__ == '__main__':
    unittest.main()
