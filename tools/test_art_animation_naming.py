#!/usr/bin/env python3
"""Readable names and duplicate evidence never alter exact playback identities."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest

from art_animation_naming import apply_duplicate_audit, naming_fields, sha256
from art_asset_identity import legacy_id
from build_animation_identity_plan import build_plan, REDUNDANT
from build_progress_tracker import merge_art


class AnimationNamingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, path, data='source'):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(data)
        return file

    def test_generic_name_uses_original_filename_after_rename(self):
        parent = dict(path='assets/animations/Mixamo/anim_mixamo_fight_idle_v01.fbx',
            original_paths=['assets/animations/Mixamo/Fight Idle.fbx'])
        result = naming_fields('mixamo_com', parent, {'loop': True})
        self.assertEqual(result['title'], 'Fight Idle · Loop')
        self.assertEqual(result['original_names'], ['mixamo_com', 'Fight Idle'])
        self.assertIn(parent['path'], result['original_paths'])
        self.assertEqual(result['start_state'], '')
        self.assertEqual(result['end_state'], '')

    def test_transition_name_does_not_claim_review_or_unknown_hang_type(self):
        parent = dict(path='assets/animations/Mixamo/Jumping To Hanging.fbx')
        result = naming_fields('mixamo_com', parent, {'loop': False})
        self.assertEqual(result['transition_steps'], ['Jumping', 'Hanging'])
        self.assertEqual(result['naming_status'], 'needs_review')
        self.assertNotIn('Free', result['title'])
        self.assertNotIn('Braced', result['title'])

    def test_verified_override_requires_matching_hash_and_preserves_source_search(self):
        parent = dict(path='assets/animations/Mixamo/Climb.fbx')
        override = dict(path=parent['path'], name='mixamo_com', title='Climb → Standing',
            start='Climbing', end='Standing', steps=['Climbing', 'Standing'],
            evidence=['Full source clip reviewed at start, motion and final pose.'],
            naming_status='verified', source_sha256='known')
        result = naming_fields('mixamo_com', parent, {}, [override], 'known')
        self.assertEqual(result['naming_status'], 'verified')
        self.assertEqual(result['end_state'], 'Standing')
        self.assertEqual(result['original_names'], ['mixamo_com', 'Climb'])
        stale = naming_fields('mixamo_com', parent, {}, [override], 'changed')
        self.assertEqual(stale['title'], 'Climb')
        self.assertEqual(stale['naming_status'], 'needs_review')
        self.assertEqual(stale['end_state'], '')

    def test_invalid_review_evidence_cannot_claim_verified(self):
        parent = dict(path='assets/test.glb')
        override = dict(path=parent['path'], name='Idle', source_sha256='same', naming_status='verified')
        with self.assertRaisesRegex(ValueError, 'requires recorded evidence'):
            naming_fields('Idle', parent, {}, [override], 'same')

    def test_sword_names_are_presentation_only(self):
        descriptor = dict(name='Regular_Sword_A', index=7, id='exact:clip', loop=False)
        before = deepcopy(descriptor)
        result = naming_fields(descriptor['name'], {'path': 'assets/library.glb'}, descriptor)
        self.assertEqual(result['title'], 'Sword · Regular attack A')
        self.assertEqual(descriptor, before)

    def duplicate_fixture(self):
        paths = ['assets/animations/Mixamo/A.fbx', 'assets/animations/Mixamo/A (1).fbx']
        entries = []
        for index, path in enumerate(paths):
            self.write(path, 'same sampled motion')
            entries.append(dict(id=f'clip:{index}', parent_id=f'art:{index}', path=path, original_paths=[path],
                source_clip={'name': 'mixamo_com', 'duration': 1.0}))
        group = dict(id='duplicate:1', status='verified_duplicate', members=paths, keeper=paths[0],
            member_sha256={path: sha256(self.root / path) for path in paths},
            evidence=['Same rig, rest pose, tracks, duration and sampled motion.'],
            duplicate_file_eligible=True, reason='Verified whole-file duplicate')
        return entries, dict(version=1, groups=[group])

    def test_duplicate_review_resolves_keeper_and_downgrades_stale_hashes(self):
        entries, audit = self.duplicate_fixture()
        apply_duplicate_audit(self.root, entries, audit)
        self.assertTrue(all(entry['duplicate_file_eligible'] for entry in entries))
        self.assertEqual(entries[1]['duplicate_keeper_id'], entries[0]['id'])
        self.write(entries[1]['path'], 'changed motion')
        apply_duplicate_audit(self.root, entries, audit)
        self.assertTrue(all(entry['duplicate_status'] == 'candidate' for entry in entries))
        self.assertTrue(all(not entry['duplicate_file_eligible'] for entry in entries))

    def test_multi_clip_sources_and_derived_variants_are_not_file_deletion_candidates(self):
        entries, audit = self.duplicate_fixture()
        extra = dict(entries[0], id='clip:extra')
        apply_duplicate_audit(self.root, entries + [extra], audit)
        self.assertFalse(entries[1]['duplicate_file_eligible'])
        self.assertEqual(entries[1]['duplicate_status'], 'candidate')
        audit['groups'][0]['status'] = 'derived'
        apply_duplicate_audit(self.root, entries, audit)
        self.assertFalse(entries[0]['duplicate_file_eligible'])
        self.assertEqual(entries[0]['duplicate_status'], 'derived')

    def test_different_clip_names_or_durations_do_not_collapse_as_verified_duplicates(self):
        entries, audit = self.duplicate_fixture()
        entries[1]['source_clip']['name'] = 'different_action'
        apply_duplicate_audit(self.root, entries, audit)
        self.assertEqual(entries[0]['duplicate_status'], 'candidate')
        entries[1]['source_clip']['name'] = 'mixamo_com'
        entries[1]['source_clip']['duration'] = 2.0
        apply_duplicate_audit(self.root, entries, audit)
        self.assertEqual(entries[0]['duplicate_status'], 'candidate')

    def test_renamed_source_keeps_duplicate_evidence_by_original_path(self):
        entries, audit = self.duplicate_fixture()
        old = entries[0]['path']
        new = 'assets/animations/Mixamo/anim_mixamo_a_v01.fbx'
        (self.root / old).rename(self.root / new)
        entries[0]['path'] = new
        apply_duplicate_audit(self.root, entries, audit)
        self.assertEqual(entries[1]['duplicate_status'], 'verified_duplicate')
        self.assertTrue(entries[1]['duplicate_file_eligible'])

    def test_runtime_references_and_root_motion_variants_block_file_eligibility(self):
        entries, audit = self.duplicate_fixture()
        self.write('scenes/player.tscn', '[ext_resource path="res://' + entries[1]['path'] + '"]')
        apply_duplicate_audit(self.root, entries, audit)
        self.assertEqual(entries[1]['duplicate_references'], ['scenes/player.tscn'])
        self.assertFalse(entries[1]['duplicate_file_eligible'])
        entries[0]['motion_mode'] = 'Root motion'
        entries[1]['motion_mode'] = 'In place'
        apply_duplicate_audit(self.root, entries, audit)
        self.assertFalse(entries[0]['duplicate_file_eligible'])
        self.assertEqual(entries[0]['duplicate_status'], 'distinct_variant')

    def test_catalog_registry_merge_deduplicates_old_paths_and_preserves_identity(self):
        old = 'assets/animations/Mixamo/Fight Idle.fbx'
        new = 'assets/animations/Mixamo/anim_mixamo_fight_idle_v01.fbx'
        file = self.write(new)
        registry = dict(version=1, entries=[dict(id=legacy_id(old), original_path=old, path=new,
            aliases=[old], source_sha256=sha256(file))])
        self.write('tools/art_asset_identities.json', json.dumps(registry))
        original = dict(id=legacy_id(old), path=old, title='Fight Idle', kind='Models', image=False, url='../../' + old)
        current = dict(original, path=new, title='anim mixamo fight idle v01')
        result = merge_art(self.root, [current], [original])
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['id'], original['id'])
        self.assertEqual(result[0]['path'], new)
        self.assertEqual(result[0]['original_paths'], [old])
        self.assertFalse(result[0]['missing'])

    def test_inactive_plan_excludes_redundant_sources_and_vendor_bundles(self):
        self.write('assets/animations/Mixamo/Fight Idle.fbx')
        for name in REDUNDANT:
            self.write('assets/animations/Mixamo/' + name)
        self.write('assets/animations/ual/native_combat.tres', '[gd_resource type="AnimationLibrary" format=3]')
        self.write('assets/third_party/quaternius/UAL1_Standard.glb')
        result = build_plan(self.root)
        self.assertEqual(len(result['entries']), 2)
        self.assertTrue(any(item['path'].endswith('anim_ual_native_combat_library_v01.tres') for item in result['entries']))
        self.assertFalse((self.root / 'tools/art_asset_identities.json').exists())
        self.assertTrue((self.root / 'assets/animations/Mixamo/Fight Idle.fbx').exists())


if __name__ == '__main__':
    unittest.main()
