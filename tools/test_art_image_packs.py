#!/usr/bin/env python3
"""Source-backed grouping regression tests: identities, evidence and missing files."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest

from art_image_packs import build_packs, stable_id


class ImagePacksTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.doc = 'art_source/ui/README.md'
        self.write(self.doc, 'The ordered review contains first.png and second.png.')
        self.paths = ['art_source/ui/first.png', 'art_source/ui/second.png']
        self.art = [self.asset(path) for path in self.paths]
        self.spec = dict(key='review-v1', title='Review images', description='Existing review files.',
            members=self.paths, cover=self.paths[0], sources=[self.doc],
            evidence=[dict(path=self.doc, contains='first.png and second.png')])
        self.manifest([self.spec])

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def asset(self, relative):
        self.write(relative, 'existing image')
        return dict(id=stable_id(relative), path=relative, title=Path(relative).stem,
            kind='Images', types=['Images'], collections=['UI'], image=True,
            url='../../' + relative, origin='Project files', role='', missing=False,
            modified_at='2026-09-30T10:00:00Z', clip_names=[], clip_status='not_applicable')

    def manifest(self, packs):
        self.write('tools/art_image_packs.json', json.dumps(dict(version=1, packs=packs)))

    def test_original_entries_and_custom_ids_are_unchanged(self):
        self.art[0].update(id='art:existing-custom-id', note='Keep this note', status='Ready for review')
        original = deepcopy(self.art)
        art, packs = build_packs(self.root, self.art)
        self.assertEqual(art, original)
        self.assertEqual(self.art, original)
        self.assertEqual(packs[0]['members'], [e['id'] for e in original])
        self.assertEqual(packs[0]['cover'], 'art:existing-custom-id')
        self.assertEqual(packs[0]['id'], 'art:pack:review-v1')
        for field in ('status', 'approval', 'attention'):
            self.assertNotIn(field, packs[0])

    def test_title_change_keeps_pack_id_and_order_is_explicit(self):
        _, original = build_packs(self.root, self.art)
        self.spec.update(title='Updated review label', members=list(reversed(self.paths)))
        self.manifest([self.spec])
        _, packs = build_packs(self.root, self.art, original)
        self.assertEqual(packs[0]['id'], original[0]['id'])
        self.assertEqual(packs[0]['members'], list(reversed(original[0]['members'])))

    def test_numbered_sequence_is_numeric_and_keeps_expected_missing_member(self):
        self.spec.pop('members')
        prefix = 'art_source/ui/frame-'
        self.spec['numbered_members'] = dict(prefix=prefix, suffix='.png', start=0, count=12, digits=4)
        self.spec['cover'] = prefix + '0000.png'
        self.spec['member_types'] = ['Images', 'Animations']
        art = [self.asset(prefix + f'{i:04d}.png') for i in range(12) if i != 5]
        self.manifest([self.spec])
        output, packs = build_packs(self.root, art)
        pack = packs[0]
        self.assertEqual(pack['member_count'], 12)
        self.assertEqual(pack['missing_count'], 1)
        missing = next(e for e in output if e['path'].endswith('0005.png'))
        self.assertTrue(missing['missing'])
        self.assertEqual(missing['types'], ['Images', 'Animations'])
        self.assertEqual(pack['members'][5], missing['id'])
        self.assertEqual(pack['members'][10], stable_id(prefix + '0010.png'))

    def test_deleted_member_retains_id_and_record(self):
        _, initial = build_packs(self.root, self.art)
        self.art[1]['missing'] = True
        self.art[1]['note'] = 'Original annotation'
        (self.root / self.paths[1]).unlink()
        art, packs = build_packs(self.root, self.art, initial)
        self.assertEqual(packs[0]['members'], initial[0]['members'])
        self.assertEqual(packs[0]['missing_count'], 1)
        self.assertEqual(art[1]['note'], 'Original annotation')
        self.assertFalse(packs[0]['missing'])

    def test_removed_definition_retains_pack_and_members(self):
        _, initial = build_packs(self.root, self.art)
        self.manifest([])
        _, packs = build_packs(self.root, self.art, initial)
        self.assertEqual(packs[0]['id'], initial[0]['id'])
        self.assertEqual(packs[0]['members'], initial[0]['members'])
        self.assertTrue(packs[0]['missing_definition'])
        self.assertIn('evidence', packs[0]['catalog_warning'])

    def test_new_pack_requires_evidence_and_old_pack_is_not_erased(self):
        _, initial = build_packs(self.root, self.art)
        self.write(self.doc, 'Evidence removed')
        _, fresh = build_packs(self.root, self.art)
        self.assertEqual(fresh, [])
        _, preserved = build_packs(self.root, self.art, initial)
        self.assertEqual(preserved[0]['members'], initial[0]['members'])
        self.assertTrue(preserved[0]['missing_definition'])

    def test_sequence_preview_is_reused_and_initial_frame_reset_without_mutation(self):
        preview = dict(status='ready', kind='sequence', duration=10,
            sequence=dict(id='existing', start_frame=17, fps=60, frame_count=600, frames_url='existing.json'))
        self.art[0]['preview'] = deepcopy(preview)
        self.spec['preview_member'] = self.paths[0]
        self.manifest([self.spec])
        _, packs = build_packs(self.root, self.art)
        self.assertEqual(packs[0]['preview']['sequence']['start_frame'], 0)
        self.assertEqual(packs[0]['preview_member'], self.art[0]['id'])
        self.assertEqual(self.art[0]['preview'], preview)

    def test_ordinary_stills_do_not_invent_animation_playback(self):
        _, packs = build_packs(self.root, self.art)
        self.assertNotIn('preview', packs[0])

    def test_missing_cover_is_flagged_instead_of_broken_thumbnail(self):
        self.art[0]['missing'] = True
        _, packs = build_packs(self.root, self.art)
        self.assertTrue(packs[0]['cover_missing'])
        self.assertFalse(packs[0]['image'])
        self.assertFalse(packs[0]['missing'])

    def test_invalid_key_duplicate_member_and_escaping_paths_rejected(self):
        cases = [dict(key='../outside'), dict(members=[self.paths[0], self.paths[0]]),
                 dict(members=['../../outside.png']), dict(cover='art_source/ui/unknown.png')]
        for fields in cases:
            with self.subTest(fields=fields):
                self.manifest([dict(self.spec, **fields)])
                with self.assertRaises(ValueError): build_packs(self.root, self.art)

    def test_non_image_and_excluded_existing_files_rejected(self):
        self.spec['members'] = ['art_source/ui/data.json']
        self.spec['cover'] = self.spec['members'][0]
        self.manifest([self.spec])
        with self.assertRaises(ValueError): build_packs(self.root, self.art)
        self.spec['members'] = ['art_source/ui/.artifacts/hidden.png']
        self.spec['cover'] = self.spec['members'][0]
        self.write(self.spec['cover'], 'ignored artifact')
        self.manifest([self.spec])
        with self.assertRaises(ValueError): build_packs(self.root, self.art)

    def test_manifest_duplicate_pack_keys_rejected(self):
        self.manifest([self.spec, self.spec])
        with self.assertRaises(ValueError): build_packs(self.root, self.art)

    def test_actual_project_packs_are_documented_and_original_entries_preserved(self):
        root = Path(__file__).resolve().parents[1]
        catalog = json.loads((root / 'docs/tracker/catalog.json').read_text())
        previous = deepcopy(catalog['art'])
        # User-created packs are managed separately from source-backed definitions.
        manifest = json.loads((root / 'tools/art_image_packs.json').read_text())
        declared = {'art:pack:' + item['key'] for item in manifest['packs']}
        source_packs = [p for p in catalog.get('packs', []) if p['id'] in declared]
        art, packs = build_packs(root, catalog['art'], source_packs)
        self.assertEqual(art, previous)
        self.assertEqual({p['id']: p['member_count'] for p in packs}, {
            'art:pack:painted-soul-wisps-v1-frames': 600,
            'art:pack:firefly-soul-wisps-v1-keyframes': 5,
            'art:pack:firefly-soul-wisps-v1-review': 10,
            'art:pack:painted-soul-wisps-v1-review': 8,
            'art:pack:mana-evolution-review': 5,
            'art:pack:stone-arm-life-progression-approved-v03': 6,
            'art:pack:protagonist-travelling-clothing-exploration-v01': 3,
            'art:pack:road-pilgrim-palette-style-exploration-v01': 3,
            'art:pack:magic-rune-dictionary-v01': 1,
            'art:pack:magic-rune-style-exploration-v01': 3,
            'art:pack:magic-circle-paired-exploration-v01': 3,
            'art:pack:magic-circle-geometry-exploration-v01': 3})
        self.assertTrue(all(not p['missing_count'] for p in packs))
        self.assertTrue(all(not p.get('missing_definition') for p in packs))


if __name__ == '__main__':
    unittest.main()
