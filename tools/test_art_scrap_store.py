#!/usr/bin/env python3
"""Destructive paths are tested exclusively against disposable project fixtures."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from art_scrap_store import ScrapStore, ScrapError, TRASH
import art_scrap_store
from serve_progress_tracker import TrackerStore


def metadata(label='Scrap'):
    return dict(status='', attention=[], priority='Normal', note='Keep my notes', checklist=[], related=[],
                display_name='', animation_categories=None, animation_tags=None, review_label=label, art_tags=[])


class ScrapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.catalog = dict(art=[], packs=[], animation_clips=[], animation_categories=[], features=[])
        self.state = dict(version=5, revision=7, items={}, history=[])
        self.store = TrackerStore(self.root / 'docs/tracker/tracking.json', self.root)
        self.write_json('docs/tracker/catalog.json', self.catalog)
        self.write_json('docs/tracker/tracking.json', self.state)
        self.scrap = ScrapStore(self.root, self.store)

    def write(self, relative, content='test asset'):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def write_json(self, relative, value):
        return self.write(relative, json.dumps(value))

    def flush(self):
        self.write_json('docs/tracker/catalog.json', self.catalog)
        self.write_json('docs/tracker/tracking.json', self.state)

    def asset(self, identifier='art:a', path='art_source/concept/a.png', label='Scrap'):
        self.write(path)
        entry = dict(id=identifier, path=path, title=identifier)
        self.catalog['art'].append(entry)
        self.state['items'][identifier] = metadata(label)
        self.flush()
        return entry

    def prepare(self, *ids):
        return self.scrap.prepare(dict(version=5, revision=self.state['revision'], ids=list(ids)))

    def delete(self, plan):
        return self.scrap.delete(dict(version=5, revision=self.state['revision'], token=plan['token'], confirmed=True))

    def restore(self, transaction):
        return self.scrap.restore(dict(version=5, revision=self.state['revision'], transaction_id=transaction))

    def test_preparation_is_read_only_and_exact(self):
        entry = self.asset()
        before = self.store.path.read_bytes()
        plan = self.prepare(entry['id'])
        self.assertEqual(plan['items'][0]['kind'], 'file')
        self.assertEqual(plan['items'][0]['path'], entry['path'])
        self.assertTrue((self.root / entry['path']).is_file())
        self.assertFalse((self.root / TRASH).exists())
        self.assertEqual(self.store.path.read_bytes(), before)

    def test_move_restart_restore_preserves_notes_state_and_original_bytes(self):
        entry = self.asset()
        source = self.root / entry['path']
        original = source.read_bytes()
        before = self.store.path.read_bytes()
        result = self.delete(self.prepare(entry['id']))
        self.assertFalse(source.exists())
        self.assertEqual(result['state']['revision'], 7)
        self.assertEqual(result['trash']['hidden_ids'], [entry['id']])
        self.scrap = ScrapStore(self.root, self.store)
        self.assertEqual(self.scrap.trash()['hidden_ids'], [entry['id']])
        restored = self.restore(result['transaction_id'])
        self.assertEqual(source.read_bytes(), original)
        self.assertEqual(restored['trash']['hidden_ids'], [])
        self.assertEqual(self.store.path.read_bytes(), before)
        self.assertEqual(restored['state']['items'][entry['id']]['review_label'], 'Scrap')

    def test_virtual_pack_clip_and_category_never_touch_sources(self):
        entry = self.asset()
        for key, identifier in [('packs','art:pack:test'), ('animation_clips','art:clip:test'), ('animation_categories','art:category:test')]:
            self.catalog[key].append(dict(id=identifier, title=identifier, path=entry['path'], parent_id=entry['id'], members=[entry['id']]))
            self.state['items'][identifier] = metadata()
        self.flush()
        ids = ['art:pack:test','art:clip:test','art:category:test']
        plan = self.prepare(*ids)
        self.assertTrue(all(item['kind'] == 'virtual' and 'source files retained' in item['effect'] for item in plan['items']))
        result = self.delete(plan)
        self.assertTrue((self.root / entry['path']).is_file())
        self.assertEqual(set(result['trash']['hidden_ids']), set(ids))

    def test_approved_or_unlabelled_files_and_dev_ids_rejected(self):
        self.asset(label='Approved')
        with self.assertRaises(ScrapError): self.prepare('art:a')
        self.state['items']['art:a']['review_label'] = ''; self.flush()
        with self.assertRaises(ScrapError): self.prepare('art:a')
        with self.assertRaises(ScrapError): self.prepare('shared-motion')

    def test_source_supporting_approved_clip_or_pack_is_protected(self):
        self.asset()
        for key, extra in [('animation_clips', {'parent_id':'art:a'}), ('packs', {'members':['art:a']})]:
            with self.subTest(key=key):
                self.catalog[key] = [dict(id='art:approved', title='Approved work', **extra)]
                self.state['items']['art:approved'] = metadata('Approved'); self.flush()
                with self.assertRaisesRegex(ScrapError, 'Approved'): self.prepare('art:a')
                self.catalog[key] = []

    def test_runtime_references_block_but_document_mentions_warn(self):
        entry = self.asset()
        self.write('art_source/concept/README.md', 'See a.png for the concept')
        self.assertTrue(self.prepare('art:a')['items'][0]['warnings'])
        self.write('scenes/test.tscn', '[ext_resource path="res://' + entry['path'] + '"]')
        with self.assertRaisesRegex(ScrapError, 'Godot'): self.prepare('art:a')

    def test_feature_checklist_and_pack_evidence_protected(self):
        entry = self.asset()
        for kind in ['feature', 'checklist', 'pack']:
            with self.subTest(kind=kind):
                self.catalog['features'] = []; self.catalog['packs'] = []
                if kind == 'feature': self.catalog['features'] = [dict(id='motion', sources=[entry['path']])]
                elif kind == 'checklist': self.catalog['features'] = [dict(id='motion', checklist=[dict(source=entry['path'])])]
                else: self.catalog['packs'] = [dict(id='art:pack:protected', sources=[entry['path']])]
                self.flush()
                with self.assertRaisesRegex(ScrapError, 'evidence'): self.prepare('art:a')

    def test_restricted_paths_and_symlink_components(self):
        for path in ['docs/narrative.md', 'scenes/arena.tscn', 'DEVELOPMENT_ROADMAP.md', 'assets/.private/a.png']:
            with self.subTest(path=path):
                self.catalog['art'] = []; self.asset(path=path)
                with self.assertRaises(ScrapError): self.prepare('art:a')
        self.catalog['art'] = []; self.asset(path='art_source/real/a.png')
        (self.root / 'art_source/link').symlink_to(self.root / 'art_source/real', target_is_directory=True)
        self.catalog['art'][0]['path'] = 'art_source/link/a.png'; self.flush()
        with self.assertRaisesRegex(ScrapError, 'Symbolic'): self.prepare('art:a')

    def test_changed_files_labels_catalog_and_journal_invalidate_confirmation(self):
        entry = self.asset()
        plan = self.prepare('art:a'); self.write(entry['path'], 'changed')
        with self.assertRaisesRegex(ScrapError, 'changed'): self.delete(plan)
        plan = self.prepare('art:a'); self.catalog['art'][0]['title'] = 'Changed'; self.flush()
        with self.assertRaisesRegex(ScrapError, 'changed'): self.delete(plan)
        plan = self.prepare('art:a'); self.state['items']['art:a']['review_label'] = 'Approved'; self.flush()
        with self.assertRaises(ScrapError): self.delete(plan)
        self.state['items']['art:a']['review_label'] = 'Scrap'; self.asset('art:b', 'art_source/b.png')
        first = self.prepare('art:a'); self.delete(self.prepare('art:b'))
        with self.assertRaisesRegex(ScrapError, 'changed'): self.delete(first)

    def test_revision_and_expired_confirmation_rejected(self):
        self.asset()
        with self.assertRaises(ScrapError): self.scrap.prepare(dict(version=5, revision=6, ids=['art:a']))
        plan = self.prepare('art:a'); self.scrap.pending[plan['token']]['expires'] = 0
        with self.assertRaisesRegex(ScrapError, 'expired'): self.delete(plan)

    def test_batch_move_failure_rolls_back_every_file(self):
        a = self.asset(); b = self.asset('art:b', 'assets/b.png')
        plan = self.prepare(a['id'], b['id'])
        original = self.scrap._move
        def fail_second(source, target):
            if source == self.root / b['path']: raise OSError('disk failure')
            return original(source, target)
        with patch.object(self.scrap, '_move', side_effect=fail_second):
            with self.assertRaisesRegex(ScrapError, 'rolled back'): self.delete(plan)
        self.assertTrue((self.root / a['path']).is_file()); self.assertTrue((self.root / b['path']).is_file())
        self.assertEqual(self.scrap.trash()['hidden_ids'], [])

    def test_restore_conflict_checks_every_target_before_moving(self):
        a = self.asset(); b = self.asset('art:b', 'assets/b.png')
        result = self.delete(self.prepare(a['id'], b['id']))
        self.write(b['path'], 'new work')
        with self.assertRaisesRegex(ScrapError, 'overwrite'): self.restore(result['transaction_id'])
        self.assertFalse((self.root / a['path']).exists())
        self.assertEqual((self.root / b['path']).read_text(), 'new work')
        self.assertEqual(len(self.scrap.trash()['hidden_ids']), 2)

    def test_failed_restore_rolls_back_to_trash(self):
        a = self.asset(); b = self.asset('art:b', 'assets/b.png')
        result = self.delete(self.prepare(a['id'], b['id']))
        original = self.scrap._move
        def fail_second(source, target):
            if target == self.root / b['path']: raise OSError('disk failure')
            return original(source, target)
        with patch.object(self.scrap, '_move', side_effect=fail_second):
            with self.assertRaises(ScrapError): self.restore(result['transaction_id'])
        self.assertFalse((self.root / a['path']).exists()); self.assertFalse((self.root / b['path']).exists())
        self.assertEqual(len(self.scrap.trash()['hidden_ids']), 2)

    def test_restart_rolls_back_interrupted_move(self):
        a = self.asset(); b = self.asset('art:b', 'assets/b.png')
        plan = self.prepare(a['id'], b['id'])
        original = self.scrap._move
        def interrupt(source, target):
            original(source, target)
            raise KeyboardInterrupt('simulated process termination')
        with patch.object(self.scrap, '_move', side_effect=interrupt):
            with self.assertRaises(KeyboardInterrupt): self.delete(plan)
        self.assertFalse((self.root / a['path']).exists())
        self.scrap = ScrapStore(self.root, self.store)
        self.assertTrue((self.root / a['path']).exists()); self.assertTrue((self.root / b['path']).exists())
        self.assertEqual(self.scrap.trash()['hidden_ids'], [])

    def test_restart_rolls_back_interrupted_restore(self):
        a = self.asset(); b = self.asset('art:b', 'assets/b.png')
        result = self.delete(self.prepare(a['id'], b['id']))
        original = self.scrap._move
        def interrupt(source, target):
            original(source, target)
            raise KeyboardInterrupt('simulated process termination')
        with patch.object(self.scrap, '_move', side_effect=interrupt):
            with self.assertRaises(KeyboardInterrupt): self.restore(result['transaction_id'])
        self.scrap = ScrapStore(self.root, self.store)
        self.assertFalse((self.root / a['path']).exists()); self.assertFalse((self.root / b['path']).exists())
        self.assertEqual(len(self.scrap.trash()['hidden_ids']), 2)

    def test_hidden_parent_prevents_child_edits_under_shared_lock(self):
        a = self.asset()
        self.catalog['animation_clips'] = [dict(id='art:clip:child', parent_id=a['id'])]; self.flush()
        self.delete(self.prepare(a['id']))
        with self.store.lock:
            with self.assertRaises(ScrapError): self.scrap.assert_editable_locked(['art:clip:child'])
            self.scrap.assert_editable_locked(['art:unrelated'])
            self.assertEqual(self.scrap.trash_locked()['hidden_ids'], [a['id']])

    def test_journal_write_failure_does_not_move_originals(self):
        a = self.asset()
        plan = self.prepare(a['id'])
        with patch.object(self.store, '_atomic_replace', side_effect=OSError('Disk full')):
            with self.assertRaises(ScrapError): self.delete(plan)
        self.assertTrue((self.root / a['path']).is_file())
        self.assertEqual(self.scrap.trash()['hidden_ids'], [])

    def test_trash_directory_symlink_rejected(self):
        self.asset()
        outside = self.root / 'outside'
        outside.mkdir()
        (self.root / '.artifacts').mkdir()
        (self.root / TRASH).symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ScrapError, 'Symbolic'): self.prepare('art:a')
        self.assertEqual(list(outside.iterdir()), [])

    def test_recovery_conflict_keeps_both_old_and_recreated_file(self):
        a = self.asset()
        plan = self.prepare(a['id'])
        original = self.scrap._move
        def interrupt(source, target):
            original(source, target)
            raise KeyboardInterrupt('process termination')
        with patch.object(self.scrap, '_move', side_effect=interrupt):
            with self.assertRaises(KeyboardInterrupt): self.delete(plan)
        self.write(a['path'], 'new work must survive')
        with self.assertRaisesRegex(ScrapError, 'recovery'): ScrapStore(self.root, self.store)
        self.assertEqual((self.root / a['path']).read_text(), 'new work must survive')
        moved = list((self.root / TRASH).glob('*/files/' + a['path']))
        self.assertEqual(len(moved), 1)
        self.assertEqual(moved[0].read_text(), 'test asset')

    def test_destination_created_after_precheck_is_never_overwritten(self):
        source = self.write('art_source/original.png', 'original work')
        destination = self.root / 'art_source/raced.png'
        rename = art_scrap_store._rename_noreplace
        def race(old, new):
            new.write_text('newly created work')
            rename(old, new)
        with patch('art_scrap_store._rename_noreplace', side_effect=race):
            with self.assertRaisesRegex(ScrapError, 'appeared'): self.scrap._move(source, destination)
        self.assertEqual(source.read_text(), 'original work')
        self.assertEqual(destination.read_text(), 'newly created work')

    def test_missing_atomic_rename_support_has_no_unsafe_fallback(self):
        source = self.write('art_source/original.png', 'original work')
        destination = self.root / 'art_source/moved.png'
        with patch('art_scrap_store.ctypes.CDLL', return_value=object()):
            with self.assertRaisesRegex(OSError, 'unavailable'): self.scrap._move(source, destination)
        self.assertTrue(source.is_file()); self.assertFalse(destination.exists())

    def test_malformed_journal_items_return_storage_errors(self):
        a = self.asset(); result = self.delete(self.prepare(a['id']))
        journal = self.root / TRASH / result['transaction_id'] / 'journal.json'
        original = json.loads(journal.read_text())
        for bad in [None, {}, {'id':'art:bad','kind':'file'}, {**original['items'][0], 'fingerprint':{}}, {**original['items'][0], 'path':'../outside'}]:
            with self.subTest(bad=bad):
                record = deepcopy(original); record['items'] = [bad]
                journal.write_text(json.dumps(record))
                with self.assertRaises(ScrapError) as error: self.scrap.trash()
                self.assertEqual(error.exception.code, 'storage'); self.assertEqual(error.exception.status, 503)
        journal.write_text(json.dumps(original))


if __name__ == '__main__':
    unittest.main()
