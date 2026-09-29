"""Persistence, validation, concurrency, and local HTTP boundaries for the tracker."""

from concurrent.futures import ThreadPoolExecutor
import http.client
import io
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

import serve_progress_tracker as service


def metadata(**changes):
    value = {'status': 'In progress', 'attention': [], 'priority': 'Normal', 'note': '',
             'checklist': [{'id': 'verify', 'text': 'Verify movement in game', 'done': False,
                            'source': 'features/movement.gd'}], 'related': [],
             'display_name': '', 'animation_categories': None, 'animation_tags': None, 'review_label': '', 'art_tags': []}
    value.update(changes)
    return value


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.path = self.root / 'docs/tracker/tracking.json'
        self.store = service.TrackerStore(self.path, self.root)

    def save(self, changes, revision=0):
        return self.store.update({'version': service.VERSION, 'revision': revision, 'changes': changes})

    def test_missing_storage_stays_absent_until_a_real_change(self):
        self.assertEqual(self.store.read(), service.empty_state())
        self.assertEqual(self.save({}), service.empty_state())
        self.assertFalse(self.path.exists())
        self.assertFalse(self.path.parent.exists())

    def test_persistence_restart_sparse_records_and_dated_history(self):
        first = self.save({'movement': metadata(note='Check the stairs')})
        restarted = service.TrackerStore(self.path, self.root)
        self.assertEqual(restarted.read(), first)
        self.assertEqual(set(first['items']), {'movement'})
        self.assertEqual(first['revision'], 1)
        event = first['history'][0]
        self.assertIsNone(event['before'])
        self.assertEqual(event['after'], first['items']['movement'])
        self.assertEqual(set(event['fields']), set(service.METADATA_FIELDS))
        self.assertTrue(event['at'].endswith('Z'))
        second = restarted.update({'version': service.VERSION, 'revision': 1, 'changes': {'movement': metadata(note='Now tested')}})
        self.assertEqual(second['history'][-1]['fields'], ['note'])
        self.assertEqual(second['history'][-1]['before']['note'], 'Check the stairs')
        self.assertEqual(second['history'][-1]['after']['note'], 'Now tested')

    def test_backup_is_previous_valid_state_and_noop_does_not_replace_it(self):
        first = self.save({'movement': metadata()})
        first_bytes = self.path.read_bytes()
        second = self.save({'movement': metadata(priority='High')}, revision=1)
        self.assertEqual(self.store.backup_path.read_bytes(), first_bytes)
        self.assertEqual(json.loads(self.store.backup_path.read_text()), first)
        self.assertEqual(self.save({'movement': metadata(priority='High')}, revision=2), second)
        self.assertEqual(self.store.backup_path.read_bytes(), first_bytes)

    def test_unknown_records_are_retained_across_unrelated_updates(self):
        orphan = metadata(note='Retained migrated record', related=['future-feature'])
        self.save({'legacy/art:knight.png': orphan})
        state = self.save({'movement': metadata()}, revision=1)
        self.assertEqual(state['items']['legacy/art:knight.png'], orphan)
        with self.assertRaises(service.ValidationError):
            self.save({'legacy/art:knight.png': None}, revision=2)
        self.assertEqual(self.store.read(), state)

    def test_conflict_preserves_file_and_returns_latest_state(self):
        first = self.save({'movement': metadata()})
        raw = self.path.read_bytes()
        with self.assertRaises(service.ConflictError) as caught:
            self.save({'movement': metadata(note='stale')})
        self.assertEqual(caught.exception.state, first)
        self.assertEqual(self.path.read_bytes(), raw)

    def test_concurrent_writes_use_one_revision_check_and_save_lock(self):
        barrier = threading.Barrier(2)

        def update(name):
            barrier.wait()
            try:
                return self.save({name: metadata()})
            except service.ConflictError:
                return 'conflict'

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(update, ('first', 'second')))
        self.assertEqual(results.count('conflict'), 1)
        self.assertEqual(self.store.read()['revision'], 1)
        self.assertEqual(len(self.store.read()['items']), 1)

    def test_completed_requires_nonempty_fully_checked_checklist(self):
        for checklist in ([], metadata()['checklist']):
            with self.subTest(checklist=checklist), self.assertRaises(service.ValidationError):
                self.save({'movement': metadata(status='Completed', checklist=checklist)})
        checklist = metadata()['checklist']
        checklist[0]['done'] = True
        saved = self.save({'movement': metadata(status='Completed', checklist=checklist)})
        self.assertEqual(saved['items']['movement']['status'], 'Completed')

    def test_invalid_types_lengths_and_duplicate_ids_never_write(self):
        broken = [metadata(status='Implemented'), metadata(priority='Urgent'), metadata(note='x' * 10001),
                  metadata(note=17), metadata(attention=['Bug found', 'Bug found']),
                  metadata(attention=[{}]), metadata(related=['one', 'one']), metadata(related=[17]),
                  metadata(checklist=[metadata()['checklist'][0]] * 2), metadata(checklist={}),
                  metadata(note='\ud800')]
        for field, value in (('done', 1), ('text', ''), ('id', ''), ('source', 4)):
            check = metadata()['checklist']
            check[0][field] = value
            broken.append(metadata(checklist=check))
        missing = metadata()
        del missing['note']
        broken.extend((missing, metadata(extra='field')))
        for value in broken:
            with self.subTest(value=str(value)[:100]), self.assertRaises(service.ValidationError):
                self.save({'movement': value})
        for request in ({'version': service.VERSION, 'revision': True, 'changes': {}}, {'version': service.VERSION, 'revision': 0, 'changes': []},
                        {'version': service.VERSION, 'revision': 0, 'changes': {'': metadata()}}, {'version': service.VERSION, 'changes': {}}, []):
            with self.subTest(request=request), self.assertRaises(service.ValidationError):
                self.store.update(request)
        self.assertFalse(self.path.exists())

    def test_reserved_and_oversize_identifiers_cannot_enter_saved_state(self):
        for identifier in ('__proto__', 'constructor', 'prototype', 'x' * 201, 'id\ncontrol'):
            with self.subTest(identifier=identifier), self.assertRaises(service.ValidationError):
                self.save({identifier: metadata()})
        value = metadata()
        value['checklist'][0]['id'] = 'x' * 129
        with self.assertRaises(service.ValidationError):
            self.save({'movement': value})
        self.assertFalse(self.path.exists())

    def test_source_paths_cannot_traverse_or_follow_symlinks_outside_root(self):
        (self.root / 'escape').symlink_to(self.root.parent, target_is_directory=True)
        (self.root / '.git').mkdir()
        (self.root / 'private-link').symlink_to(self.root / '.git', target_is_directory=True)
        for source in ('../secret', '/etc/passwd', 'features/../secret', 'file:///etc/passwd',
                       'features\\secret', '.git/config', '.codex/config', '.artifacts/log',
                       'escape/secret', 'private-link/config', 'features//secret', 'a\x00b'):
            value = metadata()
            value['checklist'][0]['source'] = source
            with self.subTest(source=source), self.assertRaises(service.ValidationError):
                self.save({'movement': value})
        value['checklist'][0]['source'] = ''
        self.assertEqual(self.save({'movement': value})['revision'], 1)

    def test_corrupt_storage_is_not_replaced_and_backup_is_available(self):
        first = self.save({'movement': metadata()})
        self.save({'movement': metadata(note='new')}, revision=1)
        backup = self.store.backup_path.read_bytes()
        self.path.write_text('{broken')
        with self.assertRaises(service.StorageError):
            self.store.read()
        with self.assertRaises(service.StorageError):
            self.save({'movement': metadata(note='cannot replace')}, revision=2)
        self.assertEqual(self.path.read_text(), '{broken')
        self.assertEqual(self.store.backup_path.read_bytes(), backup)
        self.path.write_bytes(backup)
        self.assertEqual(service.TrackerStore(self.path, self.root).read(), first)

    def test_missing_primary_with_backup_requires_recovery(self):
        self.save({'movement': metadata()})
        self.save({'movement': metadata(note='new')}, revision=1)
        self.path.unlink()
        with self.assertRaises(service.StorageError):
            self.save({'movement': metadata()})
        self.assertFalse(self.path.exists())

    def test_save_failure_keeps_valid_primary_and_cleans_temporary_files(self):
        first = self.save({'movement': metadata()})
        original_replace = service.os.replace

        def fail_primary(source, destination):
            if destination == self.path:
                raise OSError('simulated full disk')
            return original_replace(source, destination)

        with patch.object(service.os, 'replace', side_effect=fail_primary):
            with self.assertRaises(service.StorageError):
                self.save({'movement': metadata(note='unsaved')}, revision=1)
        self.assertEqual(self.store.read(), first)
        self.assertEqual(json.loads(self.store.backup_path.read_text()), first)
        self.assertEqual({p.name for p in self.path.parent.iterdir()}, {'tracking.json', 'tracking.json.bak'})

    def test_duplicate_json_keys_and_nonstandard_numbers_are_rejected(self):
        for raw in (b'{"revision":0,"revision":1}', b'{"value":NaN}', b'{"value":Infinity}',
                    b'\xff', b'[' * 2000):
            with self.subTest(raw=raw[:50]), self.assertRaises(service.ValidationError):
                service.decode_json(raw)

    def write_legacy_state(self):
        legacy = {key: value for key, value in metadata(note='Prior notes').items()
                  if key in service.LEGACY_METADATA_FIELDS}
        state = {'version': 2, 'revision': 1, 'items': {'movement': legacy},
                 'history': [{'at': '2026-09-29T13:00:00Z', 'id': 'movement',
                              'fields': ['note'], 'before': None, 'after': legacy, 'revision': 1}]}
        self.path.parent.mkdir(parents=True)
        raw = (json.dumps(state, indent=1) + '\n').encode()
        self.path.write_bytes(raw)
        return state, raw

    def test_v2_read_is_in_memory_and_preserves_history_and_file_bytes(self):
        legacy, raw = self.write_legacy_state()
        state = self.store.read()
        self.assertEqual(state['version'], service.VERSION)
        self.assertEqual(state['history'], legacy['history'])
        self.assertEqual(state['items']['movement'], metadata(note='Prior notes'))
        self.assertEqual(self.path.read_bytes(), raw)
        self.assertEqual(self.save({}, revision=1), state)
        self.assertFalse(self.store.backup_path.exists())
        self.assertFalse(self.store.legacy_backup_path.exists())

    def test_first_v4_save_keeps_immutable_v2_copy_and_rotating_backup(self):
        legacy, raw = self.write_legacy_state()
        first = self.save({'movement': metadata(note='New notes', display_name='My movement')}, revision=1)
        self.assertEqual(first['version'], service.VERSION)
        self.assertEqual(first['history'][0], legacy['history'][0])
        self.assertEqual(self.store.legacy_backup_path.read_bytes(), raw)
        self.assertEqual(self.store.backup_path.read_bytes(), raw)
        first_bytes = self.path.read_bytes()
        second = self.save({'movement': metadata(note='Again', display_name='My movement')}, revision=2)
        self.assertEqual(self.store.legacy_backup_path.read_bytes(), raw)
        self.assertEqual(self.store.backup_path.read_bytes(), first_bytes)
        self.assertEqual(service.TrackerStore(self.path, self.root).read(), second)

    def test_v3_migration_retains_names_classification_history_and_both_recovery_copies(self):
        legacy, v2_bytes = self.write_legacy_state()
        self.store.legacy_backup_path.write_bytes(v2_bytes)
        v3_item = {key: value for key, value in metadata(display_name='My name', animation_categories=[],
                                                        animation_tags=['Blocking']).items() if key not in ('review_label', 'art_tags')}
        legacy['version'] = 3
        legacy['items'] = {'art:clip': v3_item}
        legacy['history'].append({'id': 'art:clip', 'at': '2026-09-29T14:00:00Z', 'fields': ['display_name'],
                                  'before': None, 'after': v3_item, 'revision': 1})
        v3_bytes = (json.dumps(legacy, indent=1) + '\n').encode()
        self.path.write_bytes(v3_bytes)
        migrated = self.store.read()
        self.assertEqual(migrated['version'], service.VERSION)
        self.assertEqual(migrated['items']['art:clip'], {**v3_item, 'review_label': '', 'art_tags': []})
        self.assertEqual(migrated['history'], legacy['history'])
        self.assertEqual(self.path.read_bytes(), v3_bytes)
        self.assertFalse(self.store.version_backup_paths[3].exists())
        first = self.save({'art:clip': {**v3_item, 'review_label': 'Approved', 'art_tags': []}}, revision=1)
        self.assertEqual(first['history'][-1]['fields'], ['review_label'])
        self.assertEqual(self.store.legacy_backup_path.read_bytes(), v2_bytes)
        self.assertEqual(self.store.version_backup_paths[3].read_bytes(), v3_bytes)
        first_bytes = self.path.read_bytes()
        second = self.save({'art:clip': {**v3_item, 'review_label': 'Scrap', 'art_tags': []}}, revision=2)
        self.assertEqual(self.store.version_backup_paths[3].read_bytes(), v3_bytes)
        self.assertEqual(self.store.backup_path.read_bytes(), first_bytes)
        self.assertEqual(service.TrackerStore(self.path, self.root).read(), second)

    def test_review_label_is_art_only_exclusive_and_independent_of_completion(self):
        first = self.save({'art:item': metadata(status='Planned', review_label='Approved', attention=['Bug found'])})
        self.assertEqual(first['items']['art:item']['status'], 'Planned')
        second = self.save({'art:item': metadata(status='Planned', review_label='Scrap', attention=['Bug found'])}, revision=1)
        self.assertEqual(second['history'][-1]['fields'], ['review_label'])
        for label in ('approved', 'Scrapped', ['Approved', 'Scrap'], None, True):
            with self.subTest(label=label), self.assertRaises(service.ValidationError):
                self.save({'art:item': metadata(review_label=label)}, revision=2)
        for label in ('Approved', 'Scrap'):
            with self.subTest(label=label), self.assertRaisesRegex(service.ValidationError, 'only in Art Book'):
                self.save({'movement': metadata(review_label=label)}, revision=2)
        self.assertEqual(self.store.read(), second)
        self.assertEqual(self.save({'art:item': metadata(review_label='')}, revision=2)['items']['art:item']['review_label'], '')

    def test_missing_primary_with_only_v3_backup_requires_recovery(self):
        self.path.parent.mkdir(parents=True)
        self.store.version_backup_paths[3].write_text('recovery bytes')
        with self.assertRaises(service.StorageError):
            self.store.read()
        self.assertFalse(self.path.exists())

    def test_trash_snapshot_blocks_archived_edits_under_same_lock_without_persisting_summary(self):
        original = self.save({'art:parent': metadata(review_label='Scrap'), 'art:clip:child': metadata()})
        raw = self.path.read_bytes()

        def trash_snapshot():
            self.assertTrue(self.store.lock.locked())
            return {'transactions': [{'id': 'archive'}], 'hidden_ids': ['art:parent', 'art:clip:child']}

        self.store.trash_snapshot_locked = trash_snapshot
        public = self.store.read(include_trash=True)
        self.assertEqual(public['trash']['hidden_ids'], ['art:parent', 'art:clip:child'])
        self.assertEqual(self.store.read(), original)
        for identifier in ('art:parent', 'art:clip:child'):
            with self.subTest(identifier=identifier), self.assertRaisesRegex(service.ValidationError, 'in Trash'):
                self.save({identifier: metadata(review_label='Approved')}, revision=1)
        self.assertEqual(self.path.read_bytes(), raw)
        self.assertEqual(self.store.update({'version': service.VERSION, 'revision': 1, 'changes': {}}, include_trash=True), public)
        next_state = self.store.update({'version': service.VERSION, 'revision': 1, 'changes': {'art:other': metadata()}}, include_trash=True)
        self.assertIn('trash', next_state)
        self.assertNotIn('trash', json.loads(self.path.read_text()))

    def test_old_clients_rejected_before_reading_or_writing_state(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_text('Deliberately invalid state')
        for version in (None, 1, 2, 3, 4, '5', True, 6):
            request = {'revision': 0, 'changes': {}}
            if version is not None:
                request['version'] = version
            with self.subTest(version=version), self.assertRaises(service.ReloadRequiredError):
                self.store.update(request)
        self.assertEqual(self.path.read_text(), 'Deliberately invalid state')
        self.assertFalse(self.store.backup_path.exists())

    def test_v4_tags_migration_preserves_history_and_original_backup(self):
        item = {k: v for k, v in metadata(review_label='Approved').items() if k != 'art_tags'}
        legacy = {'version': 4, 'revision': 1, 'items': {'art:image': item},
                  'history': [{'at': '2026-09-29T13:00:00Z', 'id': 'art:image', 'fields': ['review_label'],
                               'before': None, 'after': item, 'revision': 1}]}
        self.path.parent.mkdir(parents=True)
        raw = json.dumps(legacy).encode()
        self.path.write_bytes(raw)
        migrated = self.store.read()
        self.assertEqual(migrated['items']['art:image']['art_tags'], [])
        self.assertEqual(migrated['history'], legacy['history'])
        self.assertEqual(self.path.read_bytes(), raw)
        saved = self.save({'art:image': {**migrated['items']['art:image'], 'art_tags': [' combat ', 'Stone  knights']}}, revision=1)
        self.assertEqual(saved['items']['art:image']['art_tags'], ['Combat', 'Stone knights'])
        self.assertEqual(saved['items']['art:image']['review_label'], 'Approved')
        self.assertEqual(saved['history'][-1]['fields'], ['art_tags'])
        self.assertEqual(self.store.version_backup_paths[4].read_bytes(), raw)
        self.assertEqual(service.TrackerStore(self.path, self.root).read(), saved)
        with self.assertRaises(service.ReloadRequiredError):
            self.store.update({'version': 4, 'revision': 2, 'changes': {'art:image': item}})
        with self.assertRaises(service.ConflictError):
            self.save({'art:image': metadata(art_tags=['Magic'])}, revision=1)
        self.assertEqual(self.store.read(), saved)

    def test_art_tags_validation_and_independent_records(self):
        for tags in (None, 'Combat', [''], ['a\nline'], ['a\x7fb'], ['\ud800'], ['x' * 61],
                     ['Combat', ' combat '], ['Ａrmor', 'Armor'], [str(i) for i in range(33)]):
            with self.subTest(tags=repr(tags)), self.assertRaises(service.ValidationError):
                self.save({'art:image': metadata(art_tags=tags)})
        with self.assertRaises(service.ValidationError):
            self.save({'movement': metadata(art_tags=['Combat'])})
        first = self.save({'art:a': metadata(art_tags=['Magic']), 'art:b': metadata(art_tags=['Weapons'])})
        second = self.save({'art:a': metadata(art_tags=[])}, revision=1)
        self.assertEqual(second['items']['art:b'], first['items']['art:b'])
        self.assertEqual(second['items']['art:a']['art_tags'], [])

    def test_display_names_labels_null_and_clear_persist_with_specific_history(self):
        saved = self.save({'art:clip': metadata(display_name='  Étude 🗡  ', animation_categories=['Combat'],
                                              animation_tags=['Sword attack'])})
        self.assertEqual(saved['items']['art:clip']['display_name'], 'Étude 🗡')
        second = self.save({'art:clip': metadata(display_name='New name', animation_categories=[],
                                               animation_tags=None)}, revision=1)
        self.assertEqual(second['history'][-1]['fields'], ['display_name', 'animation_categories', 'animation_tags'])
        self.assertEqual(service.TrackerStore(self.path, self.root).read(), second)
        self.assertEqual(second['items']['art:clip']['animation_categories'], [])
        self.assertIsNone(second['items']['art:clip']['animation_tags'])
        self.assertEqual(self.save({'art:clip': metadata(display_name='🗡' * 200)}, revision=2)['revision'], 3)

    def test_invalid_names_and_animation_labels_never_write(self):
        broken = [metadata(display_name=value) for value in ('x' * 201, '\ud800', 'line\nbreak', 4, None)]
        for field, values in [('animation_categories', ['Combat', 'Combat']),
                              ('animation_categories', ['Unknown']), ('animation_categories', 'Combat'),
                              ('animation_tags', ['Flying']), ('animation_tags', ['Sword attack', 'Sword attack']),
                              ('animation_tags', [{}])]:
            broken.append(metadata(**{field: values}))
        for value in broken:
            with self.subTest(value=repr(value)), self.assertRaises(service.ValidationError):
                self.save({'movement': value})
        self.assertFalse(self.path.exists())

    def test_failed_migration_save_preserves_v2_primary_and_recovery(self):
        _, raw = self.write_legacy_state()
        original_replace = service.os.replace

        def fail_primary(source, destination):
            if destination == self.path:
                raise OSError('simulated full disk')
            return original_replace(source, destination)

        with patch.object(service.os, 'replace', side_effect=fail_primary):
            with self.assertRaises(service.StorageError):
                self.save({'movement': metadata(display_name='Unsaved')}, revision=1)
        self.assertEqual(self.path.read_bytes(), raw)
        self.assertEqual(self.store.legacy_backup_path.read_bytes(), raw)
        self.assertEqual(self.store.backup_path.read_bytes(), raw)
        self.assertEqual({p.name for p in self.path.parent.iterdir()},
                         {'tracking.json', 'tracking.json.bak', 'tracking.json.v2.bak'})

    def test_new_field_conflict_does_not_overwrite_winning_labels(self):
        first = self.save({'art:clip': metadata(display_name='Winner', animation_tags=['Blocking'])})
        with self.assertRaises(service.ConflictError):
            self.save({'art:clip': metadata(display_name='Stale', animation_tags=[])})
        self.assertEqual(self.store.read(), first)

    def test_malformed_legacy_history_fails_with_storage_error(self):
        legacy, _ = self.write_legacy_state()
        legacy['history'][0]['after'] = [{}]
        self.path.write_text(json.dumps(legacy))
        with self.assertRaises(service.StorageError):
            self.store.read()

    def test_unresolved_clip_identity_blocks_all_edits_but_keeps_missing_records(self):
        existing = metadata(note='Existing annotation')
        self.save({'art:clip:ambiguous': existing})
        catalog_path = self.path.parent / 'catalog.json'
        catalog_path.write_text(json.dumps({'animation_clips': [
            {'id': 'art:clip:ambiguous', 'identity_editable': False},
            {'id': 'art:clip:unnamed', 'identity_editable': False},
            {'id': 'art:clip:valid', 'identity_editable': True}]}))
        original = self.path.read_bytes()
        for changes in ({'art:clip:ambiguous': metadata(note='Edit')},
                        {'art:clip:unnamed': metadata()},
                        {'art:parent': metadata(), 'art:clip:ambiguous': metadata(display_name='Edit')}):
            with self.subTest(changes=changes), self.assertRaisesRegex(service.ValidationError, 'unique identity'):
                self.save(changes, revision=1)
            self.assertEqual(self.path.read_bytes(), original)
        # Unchanged records in a restored backup do not count as edits.
        self.assertEqual(self.save({'art:clip:ambiguous': existing}, revision=1)['revision'], 1)
        saved = self.save({'art:clip:missing': metadata(note='Retained orphan'),
                           'art:clip:valid': metadata(), 'art:parent': metadata()}, revision=1)
        self.assertEqual(saved['items']['art:clip:ambiguous'], existing)
        self.assertEqual(saved['items']['art:clip:missing']['note'], 'Retained orphan')
        # A catalog rebuild can resolve the identity without restarting the server.
        catalog_path.write_text(json.dumps({'animation_clips': [
            {'id': 'art:clip:ambiguous', 'identity_editable': True}]}))
        self.assertEqual(self.save({'art:clip:ambiguous': metadata(note='Resolved')}, revision=2)['revision'], 3)

    def test_corrupt_clip_catalog_cannot_bypass_identity_guard(self):
        self.path.parent.mkdir(parents=True)
        catalog_path = self.path.parent / 'catalog.json'
        for text in ('invalid json', '[]', '{"animation_clips": [null]}'):
            catalog_path.write_text(text)
            with self.subTest(text=text), self.assertRaises(service.StorageError):
                self.save({'art:clip:unknown': metadata()})
        self.assertFalse(self.path.exists())


class HttpTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'docs/tracker').mkdir(parents=True)
        (self.root / 'docs/tracker/index.html').write_text('<h1>Tracker</h1>')
        (self.root / 'sample.txt').write_text('Project source')
        self.path = self.root / 'docs/tracker/tracking.json'
        self.server = service.TrackerServer(self.root, self.path, port=0)
        self.port = self.server.server_port
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={'poll_interval': 0.01}, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, method='GET', path='/api/tracker', payload=None, headers=None, raw=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=3)
        request_headers = {'Content-Type': 'application/json'}
        request_headers.update(headers or {})
        if payload is not None:
            raw = json.dumps(payload).encode('utf-8')
        connection.request(method, path, body=raw, headers=request_headers)
        response = connection.getresponse()
        status, response_headers, data = response.status, dict(response.getheaders()), response.read()
        connection.close()
        if 'application/json' in response_headers.get('Content-Type', '') and data:
            data = json.loads(data)
        return status, response_headers, data

    def put(self, changes=None, revision=0, **kwargs):
        return self.request('PUT', payload={'version': service.VERSION, 'revision': revision, 'changes': changes or {'movement': metadata()}}, **kwargs)

    def test_get_put_and_new_server_read_same_saved_state(self):
        self.assertEqual(self.server.server_address[0], '127.0.0.1')
        self.assertEqual(self.request()[2], {**service.empty_state(), 'trash': {'transactions': [], 'hidden_ids': []}})
        self.assertFalse(self.path.exists())
        status, _, saved = self.put(headers={'Origin': f'http://127.0.0.1:{self.port}'})
        self.assertEqual(status, 200)
        self.assertEqual(self.request()[2], saved)
        with service.TrackerServer(self.root, self.path, port=0) as restarted:
            self.assertEqual(restarted.store.read(include_trash=True), saved)

    def test_old_tabs_receive_reload_required_without_any_write(self):
        for payload in ({'revision': 0, 'changes': {}}, {'version': 2, 'revision': 0, 'changes': {}},
                        {'version': 3, 'revision': 0, 'changes': {}}):
            status, _, response = self.request('PUT', payload=payload)
            self.assertEqual(status, 409)
            self.assertEqual(response['code'], 'reload_required')
            self.assertEqual(response['required_version'], service.VERSION)
        self.assertFalse(self.path.exists())

    def test_scrap_post_routes_reuse_local_origin_version_and_json_boundaries(self):
        payload = {'version': service.VERSION, 'revision': 0, 'ids': ['art:item']}
        for action in ('prepare', 'delete', 'restore'):
            with patch.object(self.server.scrap, action, return_value={'action': action}) as call:
                path = '/api/tracker/scrap/' + action
                status, _, response = self.request('POST', path, payload=payload)
                self.assertEqual((status, response), (200, {'action': action}))
                call.assert_called_once_with(payload)
                call.reset_mock()
                self.assertEqual(self.request('POST', path, payload=payload, headers={'Origin': 'https://example.com'})[0], 403)
                self.assertEqual(self.request('POST', path, payload=payload, headers={'Content-Type': 'text/plain'})[0], 415)
                status, _, response = self.request('POST', path, payload={**payload, 'version': 3})
                self.assertEqual(status, 409)
                self.assertEqual(response['code'], 'reload_required')
                self.assertEqual(response['required_version'], service.VERSION)
                call.assert_not_called()
        self.assertEqual(self.request('POST', '/api/tracker/scrap/unknown', payload=payload)[0], 404)
        self.assertFalse(self.path.exists())

    def test_scrap_conflicts_and_broken_journal_errors_remain_actionable(self):
        conflict = self.server.scrap_error('conflict', 409, 'Selection changed; prepare it again.', service.empty_state())
        with patch.object(self.server.scrap, 'delete', side_effect=conflict):
            status, _, response = self.request('POST', '/api/tracker/scrap/delete',
                                              payload={'version': service.VERSION, 'revision': 0, 'token': 'old', 'confirmed': True})
        self.assertEqual(status, 409)
        self.assertEqual(response['code'], 'conflict')
        self.assertEqual(response['state'], service.empty_state())
        broken = self.server.scrap_error('storage', 503, 'Trash journal needs recovery.')
        with patch.object(self.server.store, 'trash_snapshot_locked', side_effect=broken):
            status, _, response = self.request()
        self.assertEqual(status, 503)
        self.assertEqual(response['code'], 'storage')
        self.assertIn('recovery', response['error'])

    def test_conflict_validation_and_storage_errors_are_explicit(self):
        saved = self.put()[2]
        status, _, conflict = self.put()
        self.assertEqual(status, 409)
        self.assertEqual(conflict['state'], saved)
        self.assertEqual(self.put({'movement': metadata(status='Completed')}, revision=1)[0], 400)
        self.path.write_text('bad storage')
        self.assertEqual(self.request()[0], 503)
        self.assertEqual(self.put(revision=1)[0], 503)
        self.assertEqual(self.path.read_text(), 'bad storage')

    def test_cross_origin_and_rebinding_hosts_cannot_write(self):
        for headers in ({'Origin': 'https://example.com'}, {'Origin': 'null'},
                        {'Origin': f'http://localhost:{self.port}'}, {'Host': 'example.com'},
                        {'Host': f'127.0.0.1:{self.port + 1}'}, {'Sec-Fetch-Site': 'cross-site'}):
            with self.subTest(headers=headers):
                self.assertEqual(self.put(headers=headers)[0], 403)
        self.assertFalse(self.path.exists())
        status, headers, _ = self.request('OPTIONS', headers={'Origin': 'https://example.com'})
        self.assertEqual(status, 403)
        self.assertNotIn('Access-Control-Allow-Origin', headers)
        self.assertEqual(self.request(headers={'Host': 'example.com'})[0], 403)

    def test_request_size_content_type_and_malformed_json_are_rejected(self):
        self.assertEqual(self.put(headers={'Content-Type': 'text/plain'})[0], 415)
        self.assertEqual(self.put(headers={'Content-Length': str(service.MAX_REQUEST_BYTES + 1)})[0], 413)
        self.assertEqual(self.put(headers={'Content-Length': '9' * 5000})[0], 400)
        self.assertEqual(self.put(headers={'Content-Length': '-1'})[0], 400)
        for raw in (b'{broken', b'{"revision":0,"revision":1,"changes":{}}', b'[]'):
            with self.subTest(raw=raw):
                self.assertEqual(self.request('PUT', raw=raw)[0], 400)
        self.assertFalse(self.path.exists())

    def test_backup_metadata_larger_than_four_mib_can_be_restored(self):
        changes = {f'feature-{number}': metadata(note='x' * 10000) for number in range(430)}
        payload = {'version': service.VERSION, 'revision': 0, 'changes': changes}
        self.assertGreater(len(json.dumps(payload).encode('utf-8')), 4 * 1024 * 1024)
        self.assertEqual(service.MAX_REQUEST_BYTES, service.MAX_STATE_BYTES)
        status, _, saved = self.request('PUT', payload=payload)
        self.assertEqual(status, 200)
        self.assertEqual(saved['revision'], 1)
        self.assertEqual(saved['items'], changes)
        self.assertEqual(self.server.store.read()['items'], changes)

    def test_static_project_sources_redirect_and_head(self):
        status, headers, _ = self.request(path='/')
        self.assertEqual(status, 302)
        self.assertEqual(headers['Location'], '/docs/tracker/')
        self.assertEqual(self.request(path='/docs/tracker/')[0], 200)
        self.assertEqual(self.request(path='/sample.txt')[2], b'Project source')
        status, headers, body = self.request('HEAD', path='/sample.txt')
        self.assertEqual((status, body), (200, b''))
        self.assertEqual(int(headers['Content-Length']), len(b'Project source'))
        self.assertEqual(headers['X-Content-Type-Options'], 'nosniff')
        self.assertEqual(self.request(path='/docs/')[0], 404)

    def test_media_byte_ranges_support_seek_suffix_and_open_ended_reads(self):
        media = bytes(range(256)) * 1024
        (self.root / 'sample.webm').write_bytes(media)
        cases = [('bytes=17-80', 17, 80), ('bytes=70000-', 70000, len(media) - 1),
                 ('bytes=-15', len(media) - 15, len(media) - 1),
                 ('bytes=0-999999', 0, len(media) - 1),
                 ('bytes=-999999', 0, len(media) - 1)]
        for value, start, end in cases:
            with self.subTest(value=value):
                status, headers, body = self.request(path='/sample.webm', headers={'Range': value})
                self.assertEqual(status, 206)
                self.assertEqual(body, media[start:end + 1])
                self.assertEqual(headers['Content-Range'], f'bytes {start}-{end}/{len(media)}')
                self.assertEqual(int(headers['Content-Length']), end - start + 1)
                self.assertEqual(headers['Accept-Ranges'], 'bytes')
                self.assertEqual(headers['Content-Type'], 'video/webm')
                self.assertEqual(headers['X-Content-Type-Options'], 'nosniff')
        status, headers, body = self.request(path='/sample.webm')
        self.assertEqual((status, body), (200, media))
        self.assertEqual(headers['Accept-Ranges'], 'bytes')
        self.assertNotIn('Content-Range', headers)

    def test_media_range_head_has_get_headers_without_a_body(self):
        (self.root / 'sample.mp4').write_bytes(b'0123456789')
        status, headers, body = self.request('HEAD', path='/sample.mp4', headers={'Range': 'bytes=3-6'})
        self.assertEqual((status, body), (206, b''))
        self.assertEqual(headers['Content-Type'], 'video/mp4')
        self.assertEqual(headers['Content-Length'], '4')
        self.assertEqual(headers['Content-Range'], 'bytes 3-6/10')
        self.assertEqual(headers['Accept-Ranges'], 'bytes')

    def test_invalid_and_multiple_ranges_are_rejected_without_file_contents(self):
        for value in ('bytes=99-', 'bytes=8-3', 'bytes=-0', 'bytes=-', 'bytes=0-1,3-4',
                      'bytes=one-two', 'items=0-1', 'bytes=0-1 trailing', 'bytes=+1-3',
                      'bytes=' + '9' * 5000 + '-'):
            with self.subTest(value=value[:40]):
                status, headers, body = self.request(path='/sample.txt', headers={'Range': value})
                self.assertEqual((status, body), (416, b''))
                self.assertEqual(headers['Content-Range'], 'bytes */14')
                self.assertEqual(headers['Content-Length'], '0')
                self.assertEqual(headers['Accept-Ranges'], 'bytes')
        (self.root / 'empty.webm').touch()
        self.assertEqual(self.request(path='/empty.webm')[2], b'')
        status, headers, _ = self.request(path='/empty.webm', headers={'Range': 'bytes=0-'})
        self.assertEqual(status, 416)
        self.assertEqual(headers['Content-Range'], 'bytes */0')
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=3)
        try:
            connection.putrequest('GET', '/sample.txt')
            connection.putheader('Range', 'bytes=0-1')
            connection.putheader('Range', 'bytes=3-4')
            connection.endheaders()
            response = connection.getresponse()
            self.assertEqual((response.status, response.read()), (416, b''))
        finally:
            connection.close()

    def test_range_validators_and_api_requests_keep_existing_semantics(self):
        _, headers, _ = self.request(path='/sample.txt')
        modified = headers['Last-Modified']
        status, _, body = self.request(path='/sample.txt', headers={'Range': 'bytes=0-2', 'If-Range': modified})
        self.assertEqual((status, body), (206, b'Pro'))
        for validator in ('Wed, 21 Oct 2015 07:28:00 GMT', 'invalid date', '"unknown-etag"'):
            with self.subTest(validator=validator):
                status, _, body = self.request(path='/sample.txt', headers={'Range': 'bytes=0-2', 'If-Range': validator})
                self.assertEqual((status, body), (200, b'Project source'))
        status, _, body = self.request(path='/sample.txt', headers={'If-Modified-Since': modified, 'Range': 'bytes=0-2'})
        self.assertEqual((status, body), (304, b''))
        status, _, body = self.request(headers={'Range': 'bytes=0-2'})
        self.assertEqual((status, body), (200, {**service.empty_state(), 'trash': {'transactions': [], 'hidden_ids': []}}))

    def test_range_copy_stops_at_selected_endpoint_and_uses_bounded_reads(self):
        class RecordingStream(io.BytesIO):
            reads = []

            def read(self, size=-1):
                self.reads.append(size)
                return super().read(size)

        source = RecordingStream(b'x' * 300000)
        source.seek(17)
        output = io.BytesIO()
        handler = object.__new__(service.TrackerHandler)
        handler._file_bytes_remaining = 140000
        handler.copyfile(source, output)
        self.assertEqual(len(output.getvalue()), 140000)
        self.assertEqual(source.tell(), 140017)
        self.assertEqual(source.reads, [65536, 65536, 8928])

    def test_static_traversal_private_paths_and_symlinks_are_blocked(self):
        for folder in ('.git', '.codex', '.artifacts'):
            (self.root / folder).mkdir()
            (self.root / folder / 'secret').write_text('private')
        (self.root / 'escape').symlink_to(self.root.parent, target_is_directory=True)
        (self.root / 'private-link').symlink_to(self.root / '.git', target_is_directory=True)
        for path in ('/../secret', '/%2e%2e/secret', '/.git/secret', '/.codex/secret',
                     '/.artifacts/secret', '/private-link/secret', '/escape/secret',
                     '/sample.txt%00', '/docs/%2e%2e/sample.txt', '/a%5cb'):
            with self.subTest(path=path):
                self.assertEqual(self.request(path=path)[0], 403)
        with tempfile.TemporaryDirectory() as outside:
            secret = Path(outside) / 'secret.html'
            secret.write_text('Not a project file')
            (self.root / 'linked-index').mkdir()
            (self.root / 'linked-index/index.html').symlink_to(secret)
            (self.root / 'linked-file.txt').symlink_to(secret)
            self.assertEqual(self.request(path='/linked-index/')[0], 403)
            self.assertEqual(self.request(path='/linked-file.txt')[0], 403)
            for path in ('/linked-index/', '/linked-file.txt', '/.git/secret', '/escape/secret'):
                with self.subTest(path=path):
                    self.assertEqual(self.request(path=path, headers={'Range': 'bytes=0-2'})[0], 403)
            self.assertEqual(self.request(path='/sample.txt', headers={'Host': 'example.com', 'Range': 'bytes=0-2'})[0], 403)

    def test_http_save_failure_does_not_report_success(self):
        saved = self.put()[2]
        with patch.object(self.server.store, '_atomic_replace', side_effect=OSError('disk full')):
            status, _, body = self.put({'movement': metadata(note='unsaved')}, revision=1)
        self.assertEqual(status, 503)
        self.assertEqual(body['code'], 'storage')
        self.assertEqual(self.request()[2], saved)


if __name__ == '__main__':
    unittest.main()
