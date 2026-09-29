#!/usr/bin/env python3
"""Membership projection and suggestion regressions without modifying artwork."""
from copy import deepcopy
import unittest

from art_pack_edits import effective_catalog, empty_edits, suggest_packs
from art_image_packs import pack_record, stable_id


def image(path, **fields):
    return dict(id=stable_id(path), path=path, title=path.rsplit('/', 1)[-1],
        kind='Images', types=['Images'], collections=[], origin='Project files', role='',
        image=True, missing=False, url='../../' + path, modified_at='', **fields)


class PackEditsTests(unittest.TestCase):
    def setUp(self):
        self.images = [image(f'art_source/review/frame_{number:03}.png') for number in range(3)]
        self.pack = pack_record('art:pack:review', dict(title='Documented images',
            cover=self.images[0]['path'], sources=['art_source/review/README.md']), self.images)
        self.catalog = dict(art=self.images, packs=[self.pack], animation_categories=[dict(id='movement')])
        self.edits = empty_edits()

    def test_unmodified_pack_ids_metadata_and_inputs_are_preserved(self):
        before, edits_before = deepcopy(self.catalog), deepcopy(self.edits)
        result = effective_catalog(self.catalog, self.edits)
        for key, value in self.pack.items():
            self.assertEqual(result['packs'][0][key], value)
        self.assertEqual(result['art'], self.images)
        self.assertEqual(result['animation_categories'], self.catalog['animation_categories'])
        self.assertEqual(self.catalog, before)
        self.assertEqual(self.edits, edits_before)
        self.assertEqual(result['packs'][0]['pack_source'], 'documented')

    def test_exclusion_changes_cover_without_removing_original_file(self):
        self.edits['excluded_members'][self.pack['id']] = [self.images[0]['id']]
        self.pack['thumbnail'] = dict(status='ready', url='old-thumbnail.png')
        result = effective_catalog(self.catalog, self.edits)
        pack = result['packs'][0]
        self.assertEqual(pack['members'], [image['id'] for image in self.images[1:]])
        self.assertEqual(pack['cover'], self.images[1]['id'])
        self.assertEqual(pack['url'], self.images[1]['url'])
        self.assertNotIn('thumbnail', pack)
        self.assertEqual(result['art'], self.images)

    def test_empty_pack_keeps_identity_and_has_no_cover(self):
        self.edits['excluded_members'][self.pack['id']] = [image['id'] for image in self.images]
        result = effective_catalog(self.catalog, self.edits)['packs'][0]
        self.assertEqual(result['id'], self.pack['id'])
        self.assertEqual(result['title'], self.pack['title'])
        self.assertEqual(result['member_count'], 0)
        self.assertFalse(result['image'])
        self.assertFalse(result['missing'])
        self.assertEqual(result['url'], '')

    def test_projection_is_idempotent_and_exclusion_can_be_reversed(self):
        self.edits['excluded_members'][self.pack['id']] = [self.images[0]['id']]
        first = effective_catalog(self.catalog, self.edits)
        self.assertEqual(effective_catalog(first, self.edits), first)
        restored = effective_catalog(first, empty_edits())
        self.assertEqual(restored['packs'][0]['members'], self.pack['members'])
        self.assertEqual(restored['packs'][0]['cover'], self.pack['cover'])

    def test_sequence_changes_disable_only_pack_playback_and_can_restore(self):
        sequence = dict(status='ready', kind='sequence', sequence={'start_frame': 0}, duration=1)
        self.pack['preview'] = deepcopy(sequence)
        self.pack['preview_member'] = self.images[0]['id']
        self.images[0]['preview'] = deepcopy(sequence)
        self.edits['excluded_members'][self.pack['id']] = [self.images[1]['id']]
        result = effective_catalog(self.catalog, self.edits)
        self.assertEqual(result['packs'][0]['preview']['status'], 'unavailable')
        self.assertEqual(result['art'][0]['preview'], sequence)
        restored = effective_catalog(result, empty_edits())['packs'][0]
        self.assertEqual(restored['preview'], sequence)
        self.assertEqual(restored['preview_member'], self.images[0]['id'])

    def test_missing_members_keep_paths_ids_and_choose_existing_cover(self):
        self.catalog['art'] = self.images[1:]
        result = effective_catalog(self.catalog, self.edits)
        restored = next(item for item in result['art'] if item['id'] == self.images[0]['id'])
        self.assertEqual(restored['path'], self.images[0]['path'])
        self.assertTrue(restored['missing'])
        self.assertEqual(result['packs'][0]['missing_count'], 1)
        self.assertEqual(result['packs'][0]['cover'], self.images[1]['id'])

    def test_custom_pack_order_identity_and_membership_are_authoritative(self):
        self.edits['custom_packs'] = [dict(id='art:pack:user-123', title='My choices',
            members=[self.images[2]['id'], self.images[0]['id']], created_at='2026-09-30T00:00:00Z')]
        result = effective_catalog(self.catalog, self.edits)
        custom = result['packs'][1]
        self.assertEqual(custom['pack_source'], 'custom')
        self.assertEqual(custom['members'], self.edits['custom_packs'][0]['members'])
        self.assertEqual(effective_catalog(result, self.edits), result)
        self.edits['custom_packs'][0]['members'] = [self.images[0]['id']]
        updated = effective_catalog(result, self.edits)['packs'][1]
        self.assertEqual(updated['id'], custom['id'])
        self.assertEqual(updated['members'], [self.images[0]['id']])

    def test_numbered_suggestions_are_ordered_stable_and_never_create_packs(self):
        art = [image('art_source/frames/step_10.png'), image('art_source/frames/step_2.png')]
        catalog = dict(art=art, packs=[])
        before = deepcopy(catalog)
        suggestions = suggest_packs(catalog)
        self.assertEqual(len(suggestions), 1)
        self.assertEqual(suggestions[0]['members'], [art[1]['id'], art[0]['id']])
        self.assertIn('Numbered', suggestions[0]['reason'])
        self.assertEqual(suggest_packs(dict(art=list(reversed(art)), packs=[])), suggestions)
        self.assertEqual(catalog, before)

    def test_folder_suggestions_are_separate_and_not_visual_similarity(self):
        art = [image(f'art_source/{folder}/{name}.png') for folder in ['heads', 'shields'] for name in ['front', 'side']]
        suggestions = suggest_packs(dict(art=art, packs=[]))
        self.assertEqual(len(suggestions), 2)
        for suggestion in suggestions:
            members = [entry for entry in art if entry['id'] in suggestion['members']]
            self.assertEqual(len({entry['path'].rsplit('/', 1)[0] for entry in members}), 1)
            self.assertIn('not been assumed', suggestion['reason'])

    def test_suggestions_skip_grouped_excluded_hidden_missing_and_root_files(self):
        extra = [image(f'art_source/leftovers/image_{i}.png') for i in range(5)]
        extra[3]['missing'] = True
        self.catalog['art'] += extra + [image('art_source/a.png'), image('art_source/b.png')]
        self.edits['excluded_members'][self.pack['id']] = [self.images[0]['id'], extra[0]['id']]
        suggestions = suggest_packs(self.catalog, self.edits, hidden_ids=[extra[1]['id']])
        self.assertEqual(len(suggestions), 1)
        self.assertEqual(set(suggestions[0]['members']), {extra[2]['id'], extra[4]['id']})

    def test_numbered_groups_do_not_duplicate_in_folder_candidates(self):
        art = [image(f'art_source/frames/{name}.png') for name in ['run_1', 'run_2', 'front', 'back']]
        suggestions = suggest_packs(dict(art=art, packs=[]))
        members = [member for suggestion in suggestions for member in suggestion['members']]
        self.assertEqual(len(suggestions), 2)
        self.assertEqual(len(members), len(set(members)))


if __name__ == '__main__':
    unittest.main()
