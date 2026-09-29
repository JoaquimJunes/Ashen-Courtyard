#!/usr/bin/env python3
"""Stable binding, evidence-based classification and orphan-retention regressions."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest

from art_animation_catalog import build_animation_catalog, clip_id, classify, load_taxonomy


class AnimationCatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, path, content='source fixture'):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)

    def parent(self, names=('Sword_Regular_A', 'Sword_Regular_B'), path='assets/source.glb', identifier='art:source'):
        self.write(path)
        return dict(id=identifier, title='Source', path=path, url='../../' + path,
            types=['Models', 'Animations'], origin='Project files', collections=[], role='', image=False,
            missing=False, modified_at='2026-09-30T00:00:00Z', clip_names=list(names), clip_status='available',
            preview=dict(status='ready', kind='model', url='../../' + path, fingerprint='source-fingerprint', model='Fixture',
                clips=[dict(id=f'source:{i}', index=i, name=name, duration=1 + i, loop=False, export_name=f'Clip{i}') for i, name in enumerate(names)]))

    def manifest(self, **changes):
        self.write('tools/art_animation_classification.json', json.dumps(dict(version=1, identities=[], clip_overrides=[], **changes)))

    def build(self, parents, previous=()):
        return build_animation_catalog(self.root, parents, previous)

    def test_exact_binding_and_parent_unchanged(self):
        parent = self.parent()
        original = deepcopy(parent)
        clips, categories, taxonomy = self.build([parent])
        self.assertEqual(parent, original)
        self.assertEqual(len(clips), 2)
        for clip in clips:
            self.assertEqual(clip['id'], clip_id(parent['id'], clip['source_clip']['name']))
            self.assertEqual(clip['preview']['clips'], [clip['source_clip']])
            self.assertEqual(clip['source_clip'], original['preview']['clips'][clip['source_clip']['index']])
            self.assertTrue(clip['identity_editable'])
        self.assertEqual([category['id'] for category in categories], ['art:category:combat', 'art:category:movement',
            'art:category:interactions', 'art:category:poses-utilities', 'art:category:unclassified'])

    def test_reordering_preserves_name_identity_but_uses_current_index(self):
        parent = self.parent()
        before, _, _ = self.build([parent])
        parent['preview']['clips'].reverse()
        parent['preview']['fingerprint'] = 'changed-order'
        for index, clip in enumerate(parent['preview']['clips']): clip['index'] = index
        after, _, _ = self.build([parent], before)
        self.assertEqual({e['source_clip']['name']: e['id'] for e in before}, {e['source_clip']['name']: e['id'] for e in after})
        self.assertEqual(after[0]['source_clip']['name'], 'Sword_Regular_B')
        self.assertEqual(after[0]['preview']['clips'][0]['index'], 0)
        self.assertFalse(any(c['missing'] for c in after))

    def test_resource_file_rename_preserves_original_synthetic_clip_identity(self):
        original = 'assets/animations/ual/jump_start.tres'
        renamed = 'assets/animations/ual/anim_ual_jump_start_v01.tres'
        parent = self.parent(names=('jump_start',), path=original)
        self.write(original, '[gd_resource type="Animation" format=3]\n[resource]\nlength = 1.0\n')
        before, _, _ = self.build([parent])
        # The exporter pins unnamed-resource fallback names to the registry's
        # original filename. Its exact playback descriptor survives the move.
        (self.root / original).rename(self.root / renamed)
        parent.update(path=renamed, url='../../' + renamed, original_paths=[original])
        parent['preview']['url'] = '../../' + renamed
        after, _, _ = self.build([parent], before)
        self.assertEqual(len(after), 1)
        self.assertEqual(after[0]['id'], before[0]['id'])
        self.assertEqual(after[0]['source_clip'], before[0]['source_clip'])
        self.assertEqual(after[0]['source_clip']['name'], 'jump_start')
        self.assertFalse(after[0]['missing'])
        self.assertEqual(after[0]['original_paths'], [original, renamed])

    def test_duplicate_source_names_and_unnamed_are_readonly_fingerprinted(self):
        parent = self.parent(names=('Idle', 'Idle', ''))
        first, _, _ = self.build([parent])
        self.assertEqual(len({c['id'] for c in first}), 3)
        self.assertTrue(all(not c['identity_editable'] for c in first))
        parent['preview']['fingerprint'] = 'changed-content'
        second, _, _ = self.build([parent])
        self.assertTrue(set(c['id'] for c in first).isdisjoint(c['id'] for c in second))
        self.assertEqual(first[2]['source_clip']['name'], '')

    def test_explicit_identity_requires_matching_content_name_and_index(self):
        parent = self.parent(names=('',))
        self.write('tools/art_animation_classification.json', json.dumps(dict(version=1,
            identities=[dict(path=parent['path'], name='', index=0, fingerprint='source-fingerprint', identity='authored-rest')], clip_overrides=[])))
        first, _, _ = self.build([parent])
        self.assertTrue(first[0]['identity_editable'])
        expected = first[0]['id']
        parent['preview']['fingerprint'] = 'unreviewed-change'
        next_entries, _, _ = self.build([parent], first)
        self.assertTrue(next(e for e in next_entries if e['id'] == expected)['missing'])
        self.assertFalse(next(e for e in next_entries if not e['missing'])['identity_editable'])

    def test_removed_clip_and_missing_asset_preserve_original_record(self):
        parent = self.parent()
        first, _, _ = self.build([parent])
        parent['preview']['clips'] = parent['preview']['clips'][:1]
        parent['clip_names'] = parent['clip_names'][:1]
        result, categories, _ = self.build([parent], first)
        orphan = next(e for e in result if e['source_clip']['name'] == 'Sword_Regular_B')
        self.assertTrue(orphan['missing'])
        self.assertEqual(orphan['id'], first[1]['id'])
        self.assertEqual(categories[0]['clip_count'], 1)
        self.assertEqual(categories[0]['missing_count'], 1)
        parent['missing'] = True
        missing, _, _ = self.build([parent], result)
        self.assertTrue(all(e['missing'] for e in missing))
        self.assertEqual({c['id'] for c in missing}, {c['id'] for c in first})

    def test_unknown_metadata_retains_known_clip_without_claiming_deletion(self):
        parent = self.parent(names=('idle',))
        first, _, _ = self.build([parent])
        parent['preview'] = dict(status='unavailable', kind='model', reason='Import unavailable')
        parent['clip_names'] = []
        result, _, _ = self.build([parent], first)
        self.assertEqual(result[0]['id'], first[0]['id'])
        self.assertFalse(result[0]['missing'])
        self.assertFalse(result[0]['identity_editable'])
        self.assertEqual(result[0]['preview']['status'], 'unavailable')

    def test_unavailable_known_names_are_readonly_and_no_unknown_clips_invented(self):
        parent = self.parent(names=('Hit_A',))
        parent['preview'] = dict(status='unavailable', kind='model', reason='Unsupported source')
        result, _, _ = self.build([parent])
        self.assertEqual(len(result), 1)
        self.assertIsNone(result[0]['source_clip']['index'])
        self.assertFalse(result[0]['identity_editable'])
        self.assertEqual(result[0]['preview']['status'], 'unavailable')
        parent['clip_names'] = []
        self.assertEqual(self.build([parent])[0], [])

    def test_display_name_is_not_a_playback_alias(self):
        parent = self.parent(names=('mixamo_com',), path='assets/animations/Mixamo/Standing Aim Recoil.fbx')
        clip = self.build([parent])[0][0]
        self.assertEqual(clip['title'], 'Standing Aim Recoil')
        self.assertEqual(clip['source_clip']['name'], 'mixamo_com')
        self.assertEqual(clip['source_library'], 'Mixamo')
        self.assertEqual(clip['motion_mode'], 'Unknown')

    def test_taxonomy_defaults_follow_clip_evidence(self):
        taxonomy = load_taxonomy(self.root)
        category, tags = classify('Sword_Regular_A', 'assets/actor.glb', taxonomy)
        self.assertEqual(category, ['Combat'])
        self.assertEqual(tags, ['Sword attack'])
        category, tags = classify('Run With Sword', 'assets/actor.glb', taxonomy)
        self.assertEqual(category, ['Combat', 'Movement'])
        self.assertEqual(tags, ['Sword running', 'Locomotion'])
        self.assertEqual(classify('Consume', 'assets/actor.glb', taxonomy), (['Interactions'], ['Item use']))
        self.assertNotIn('Stunned', classify('Being Strangled', 'assets/actor.glb', taxonomy)[1])
        self.assertEqual(classify('Melee_1H_Attack_Jump_Chop', 'assets/actor.glb', taxonomy)[1], ['Aerial attack', 'Jumping'])
        self.assertEqual(classify('unknown_AppleAction', 'assets/actor.glb', taxonomy), (['Unclassified'], []))
        self.assertEqual(classify('A_TPose', 'assets/actor.glb', taxonomy), (['Poses & utilities'], []))

    def test_clip_source_metadata_resolves_library_without_changing_alias(self):
        parent = self.parent(names=('climb_up_1m_rm',), path='assets/animations/ual/native_actions.tres')
        self.write(parent['path'], '''[gd_resource type="AnimationLibrary" format=3]\n[sub_resource type="Animation" id="Action"]\nmetadata/source_scene = "res://assets/third_party/quaternius/ual2/UAL2_Standard_RM.glb"\nmetadata/source_clip = "ClimbUp_1m"\nmetadata/source_root_motion = true\n[resource]\n_data = {"climb_up_1m_rm": SubResource("Action")}\n''')
        clip = self.build([parent])[0][0]
        self.assertEqual(clip['source_library'], 'UAL 2')
        self.assertEqual(clip['rig'], 'UAL 65-bone')
        self.assertEqual(clip['motion_mode'], 'Root motion')
        self.assertEqual(clip['source_clip']['name'], 'climb_up_1m_rm')

    def test_actual_catalog_does_not_invent_healing_or_horse_mounting(self):
        root = Path(__file__).resolve().parents[1]
        catalog = json.loads((root / 'docs/tracker/catalog.json').read_text())
        original = deepcopy(catalog['art'])
        clips, categories, _ = build_animation_catalog(root, catalog['art'], catalog.get('animation_clips', []))
        self.assertEqual(catalog['art'], original)
        self.assertTrue(clips)
        self.assertFalse(any({'Healing', 'Horse mounting'} & set(c['animation_tags']) for c in clips))
        self.assertTrue(all(c['source_clip']['index'] == c['preview']['clips'][0]['index'] for c in clips if c['preview']['status'] == 'ready'))
        self.assertTrue(any(c['source_clip']['index'] > 0 for c in clips if c['preview']['status'] == 'ready'))


if __name__ == '__main__':
    unittest.main()
