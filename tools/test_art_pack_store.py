"""Pack edits, discovery and Trash protection use disposable project fixtures."""
from copy import deepcopy
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

from art_pack_store import ArtPackStore, PackError, empty_edits
from art_scrap_store import ScrapStore, ScrapError
from serve_progress_tracker import TrackerStore, TrackerServer, PackConflictError, ReloadRequiredError, ValidationError


def metadata(label=''):
    return dict(status='', attention=[], priority='Normal', note='Keep existing notes', checklist=[], related=[],
                display_name='', animation_categories=None, animation_tags=None, review_label=label, art_tags=[])


class PackTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.out = self.root / 'docs/tracker'
        self.out.mkdir(parents=True)
        self.catalog = dict(art=[], features=[], packs=[], animation_clips=[], animation_categories=[])
        for number in range(4):
            path = f'art_source/review/stage_{number}.png'
            source = self.root / path
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(b'fixture image')
            self.catalog['art'].append(dict(id='art:' + str(number), path=path, title='Stage ' + str(number),
                kind='Images', types=['Images'], collections=[], origin='Project files', role='', image=True,
                url='../../' + path, missing=False, modified_at=''))
        self.write_catalog()
        self.store = TrackerStore(self.out / 'tracking.json', self.root)
        self.packs = ArtPackStore(self.root, self.store)
        self.scrap = ScrapStore(self.root, self.store)
        self.store.trash_snapshot_locked = self.scrap.trash_locked
        self.store.trash_assert_editable_locked = self.scrap.assert_editable_locked
        self.store.pack_catalog_locked = self.packs.effective_catalog_locked
        self.store.pack_revision_locked = self.packs.revision_locked

    def write_catalog(self):
        (self.out / 'catalog.json').write_text(json.dumps(self.catalog))
        (self.out / 'data.js').write_text('window.TRACKER_DATA = ' + json.dumps(self.catalog) + ';\n')

    def create(self, members=None, revision=0, title='My review pack'):
        return self.packs.create(dict(version=5, revision=revision, title=title, members=members or ['art:0', 'art:1']))

    def remove(self, pack_id, member_id, revision):
        return self.packs.remove(dict(version=5, revision=revision, pack_id=pack_id, member_id=member_id))

    def test_read_is_pure_and_suggestions_do_not_create_packs(self):
        result = self.packs.read()
        self.assertEqual(result['revision'], 0)
        self.assertEqual(result['catalog']['packs'], [])
        self.assertEqual(len(result['suggestions']), 1)
        self.assertFalse(self.packs.path.exists())
        self.assertFalse(self.store.path.exists())

    def test_create_restart_backup_and_no_annotation_or_asset_changes(self):
        originals = {entry['path']: (self.root / entry['path']).read_bytes() for entry in self.catalog['art']}
        state = self.store.update(dict(version=5, revision=0, changes={'art:0': metadata('Approved')}))
        result = self.create()
        pack = result['catalog']['packs'][0]
        self.assertTrue(pack['id'].startswith('art:pack:user-'))
        self.assertEqual(pack['members'], ['art:0', 'art:1'])
        restarted = ArtPackStore(self.root, TrackerStore(self.store.path, self.root))
        self.assertEqual(restarted.read()['catalog'], result['catalog'])
        previous = self.packs.path.read_bytes()
        self.create(['art:2', 'art:3'], revision=1, title='Another pack')
        self.assertEqual(self.packs.backup_path.read_bytes(), previous)
        self.assertEqual(self.store.read(), state)
        self.assertEqual({path: (self.root / path).read_bytes() for path in originals}, originals)
        self.assertEqual(json.loads(self.packs.path.read_text())['history'][-1]['action'], 'create')

    def test_remove_custom_members_retains_empty_pack_identity_and_notes(self):
        result = self.create()
        identifier = result['catalog']['packs'][0]['id']
        state = self.store.update(dict(version=5, revision=0, pack_revision=1, changes={identifier: metadata('Approved')}))
        self.remove(identifier, 'art:0', 1)
        result = self.remove(identifier, 'art:1', 2)
        self.assertEqual(result['catalog']['packs'][0]['members'], [])
        self.assertEqual(result['catalog']['packs'][0]['id'], identifier)
        self.assertEqual(self.store.read(), state)
        self.assertTrue((self.root / self.catalog['art'][0]['path']).exists())

    def test_documented_exclusion_survives_refresh_with_new_members(self):
        self.catalog['packs'] = [dict(id='art:pack:documented', title='Documented', members=['art:0', 'art:1'], sources=[])]
        self.write_catalog()
        self.remove('art:pack:documented', 'art:0', 0)
        fresh = deepcopy(self.catalog)
        fresh['packs'][0]['members'].append('art:2')
        with patch('build_progress_tracker.build', return_value=fresh) as build:
            result = self.packs.refresh(dict(version=5, revision=1))
        build.assert_called_once_with(root=self.root, out=self.out, write=False, pack_document=empty_edits())
        self.assertEqual(result['revision'], 2)
        self.assertEqual(result['catalog']['packs'][0]['members'], ['art:1', 'art:2'])
        self.assertNotIn('art:0', {member for suggestion in result['suggestions'] for member in suggestion['members']})
        self.assertEqual(ArtPackStore(self.root, self.store).read()['catalog'], result['catalog'])

    def test_conflicts_never_overwrite(self):
        first = self.create()
        raw = self.packs.path.read_bytes()
        for action in (lambda: self.create(), lambda: self.packs.refresh(dict(version=5, revision=0)),
                       lambda: self.remove(first['catalog']['packs'][0]['id'], 'art:0', 0)):
            with self.assertRaises(PackError) as caught:
                action()
            self.assertEqual(caught.exception.code, 'conflict')
            self.assertEqual(caught.exception.state['revision'], 1)
            self.assertEqual(self.packs.path.read_bytes(), raw)

    def test_invalid_selections_names_and_versions_are_rejected(self):
        selections = [['art:0'], ['art:0', 'art:0'], ['art:0', 'art:unknown'], ['art:0', 1], []]
        for members in selections:
            with self.subTest(members=members), self.assertRaises(PackError):
                self.packs.create(dict(version=5, revision=0, title='Pack', members=members))
        for title in ('', ' ', '\x00', 'a' * 201, None):
            with self.subTest(title=title), self.assertRaises(PackError):
                self.create(title=title)
        with self.assertRaises(PackError) as caught:
            self.packs.create(dict(version=3, revision=0, title='Pack', members=['art:0', 'art:1']))
        self.assertEqual(caught.exception.code, 'reload_required')
        self.assertFalse(self.packs.path.exists())

    def test_missing_nonimages_and_outside_paths_are_rejected(self):
        for change in ({'missing': True}, {'image': False}, {'path': '../outside.png'}):
            original = self.catalog['art'][0].copy()
            self.catalog['art'][0].update(change)
            self.write_catalog()
            with self.assertRaises(PackError):
                self.create()
            self.catalog['art'][0] = original
        self.write_catalog()
        (self.root / self.catalog['art'][0]['path']).unlink()
        with self.assertRaises(PackError):
            self.create()

    def test_failed_save_keeps_prior_records(self):
        self.create()
        before = self.packs.path.read_bytes()
        atomic = self.store._atomic_replace
        def fail(path, data):
            if path == self.packs.path:
                raise OSError('disk full')
            atomic(path, data)
        with patch.object(self.store, '_atomic_replace', side_effect=fail), self.assertRaises(PackError) as caught:
            self.create(['art:2', 'art:3'], revision=1)
        self.assertEqual(caught.exception.code, 'storage')
        self.assertEqual(self.packs.path.read_bytes(), before)
        self.assertEqual(self.packs.backup_path.read_bytes(), before)

    def test_failed_refresh_keeps_catalog_and_revision(self):
        self.create()
        before = self.packs.path.read_bytes()
        catalog_before = (self.out / 'catalog.json').read_bytes()
        with patch('build_progress_tracker.build', side_effect=ValueError('bad manifest')), self.assertRaises(PackError):
            self.packs.refresh(dict(version=5, revision=1))
        self.assertEqual(self.packs.path.read_bytes(), before)
        with patch('build_progress_tracker.build', return_value=self.catalog), patch('build_progress_tracker.write_catalog', side_effect=OSError('disk full')), self.assertRaises(PackError):
            self.packs.refresh(dict(version=5, revision=1))
        self.assertEqual(self.packs.path.read_bytes(), before)
        self.assertEqual((self.out / 'catalog.json').read_bytes(), catalog_before)

    def test_corrupt_missing_or_symlink_storage_never_overwritten(self):
        self.packs.path.write_text('invalid')
        with self.assertRaises(PackError):
            self.create()
        self.assertEqual(self.packs.path.read_text(), 'invalid')
        self.packs.path.unlink()
        self.packs.backup_path.write_text(json.dumps(empty_edits()))
        with self.assertRaises(PackError):
            self.packs.read()
        self.packs.backup_path.unlink()
        target = self.root / 'other.json'
        target.write_text(json.dumps(empty_edits()))
        self.packs.path.symlink_to(target)
        with self.assertRaises(PackError):
            self.create()
        self.assertEqual(json.loads(target.read_text()), empty_edits())

    def test_custom_state_uses_isolated_sibling_path(self):
        other = ArtPackStore(self.root, TrackerStore(self.root / 'test-state.json', self.root))
        self.assertEqual(other.path, self.root / 'test-state.packs.json')
        self.assertEqual(self.packs.path, self.out / 'pack_edits.json')

    def test_approved_custom_pack_protects_member_from_trash(self):
        pack_id = self.create()['catalog']['packs'][0]['id']
        self.store.update(dict(version=5, revision=0, pack_revision=1, changes={pack_id: metadata('Approved'), 'art:0': metadata('Scrap')}))
        with self.assertRaisesRegex(ScrapError, 'supports Approved work'):
            self.scrap.prepare(dict(version=5, revision=1, ids=['art:0']))
        self.assertTrue((self.root / self.catalog['art'][0]['path']).exists())

    def test_pack_edit_invalidates_prepared_trash_plan_and_hidden_members_rejected(self):
        self.store.update(dict(version=5, revision=0, changes={'art:0': metadata('Scrap')}))
        plan = self.scrap.prepare(dict(version=5, revision=1, ids=['art:0']))
        self.create()
        with self.assertRaises(ScrapError) as caught:
            self.scrap.delete(dict(version=5, revision=1, token=plan['token'], confirmed=True))
        self.assertEqual(caught.exception.code, 'conflict')
        plan = self.scrap.prepare(dict(version=5, revision=1, ids=['art:0']))
        self.scrap.delete(dict(version=5, revision=1, token=plan['token'], confirmed=True))
        with self.assertRaises(PackError):
            self.create(['art:0', 'art:2'], revision=1)


    def test_membership_token_blocks_stale_approval_after_every_pack_change(self):
        result = self.create()
        pack_id = result['catalog']['packs'][0]['id']
        initial = self.store.update(dict(version=5, revision=0, changes={'art:3': metadata()}))
        payload = dict(version=5, revision=1, pack_revision=1,
                       changes={pack_id: metadata('Approved'), 'art:0': metadata('Approved'), 'art:1': metadata('Approved')})
        operations = (
            lambda: self.create(['art:2', 'art:3'], revision=1),
            lambda: self.remove(pack_id, 'art:0', 2),
            lambda: self.packs.refresh(dict(version=5, revision=3)),
        )
        for operation in operations:
            payload['pack_revision'] = self.packs.read()['revision']
            with patch('build_progress_tracker.build', return_value=self.catalog):
                operation()
            before = self.store.path.read_bytes()
            with self.assertRaises(PackConflictError) as caught:
                self.store.update(payload)
            self.assertEqual(caught.exception.revision, payload['pack_revision'] + 1)
            self.assertEqual(self.store.path.read_bytes(), before)
            self.assertEqual(self.store.read(), initial)
        with self.assertRaises(ReloadRequiredError):
            self.store.update({key: value for key, value in payload.items() if key != 'pack_revision'})
        current = self.packs.read()
        pack = next(pack for pack in current['catalog']['packs'] if pack['id'] == pack_id)
        changes = {key: metadata('Approved') for key in [pack_id, *pack['members']]}
        saved = self.store.update(dict(version=5, revision=1, pack_revision=current['revision'], changes=changes))
        self.assertEqual(saved['items'][pack_id]['review_label'], 'Approved')
        self.assertNotIn('art:0', saved['items'])
        self.assertEqual(saved['items']['art:1']['review_label'], 'Approved')

    def test_ordinary_legacy_edits_remain_supported_and_bad_tokens_rejected(self):
        saved = self.store.update(dict(version=5, revision=0, changes={'art:0': metadata()}))
        for token in (-1, True, '0', None):
            with self.subTest(token=token), self.assertRaises(ValidationError):
                self.store.update(dict(version=5, revision=1, pack_revision=token, changes={'art:1': metadata()}))
        self.assertEqual(self.store.read(), saved)
        self.create()
        with self.assertRaises(PackConflictError):
            self.store.update(dict(version=5, revision=1, pack_revision=0, changes={'art:1': metadata()}))
        self.assertEqual(self.store.read(), saved)

class PackHTTPTests(unittest.TestCase):
    write_catalog = PackTests.write_catalog

    def setUp(self):
        PackTests.setUp(self)
        self.server = TrackerServer(self.root, self.store.path, port=0)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={'poll_interval': .01}, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)

    def request(self, action='', payload=None, origin=None, method=None, path=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        headers = {'Content-Type': 'application/json'}
        if origin:
            headers['Origin'] = origin
        connection.request(method or ('POST' if payload else 'GET'), path or '/api/tracker/packs' + action,
                           json.dumps(payload).encode() if payload else None, headers)
        response = connection.getresponse()
        status, result = response.status, json.loads(response.read())
        connection.close()
        return status, result

    def test_annotation_save_returns_pack_conflict_without_partial_approval(self):
        _, result = self.request('/create', dict(version=5, revision=0, title='Pack', members=['art:0', 'art:1']))
        pack_id = result['catalog']['packs'][0]['id']
        payload = dict(version=5, revision=0, changes={pack_id: metadata('Approved'), 'art:0': metadata('Approved')})
        status, error = self.request(payload=payload, method='PUT', path='/api/tracker')
        self.assertEqual((status, error['code']), (409, 'reload_required'))
        status, error = self.request(payload={**payload, 'pack_revision': 0}, method='PUT', path='/api/tracker')
        self.assertEqual((status, error['code'], error['pack_revision']), (409, 'pack_conflict', 1))
        self.assertFalse(self.store.path.exists())
        payload['changes']['art:1'] = metadata('Approved')
        status, result = self.request(payload={**payload, 'pack_revision': 1}, method='PUT', path='/api/tracker')
        self.assertEqual(status, 200)
        self.assertEqual(set(result['items']), {pack_id, 'art:0', 'art:1'})

    def test_routes_version_origin_and_conflict(self):
        self.assertEqual(self.request()[0], 200)
        payload = dict(version=5, revision=0, title='Pack', members=['art:0', 'art:1'])
        self.assertEqual(self.request('/create', payload, origin='https://example.com')[0], 403)
        self.assertEqual(self.request('/create', {**payload, 'version': 3})[1]['code'], 'reload_required')
        status, created = self.request('/create', payload)
        self.assertEqual(status, 200)
        self.assertEqual(self.request('/create', payload)[1]['code'], 'conflict')
        identifier = created['catalog']['packs'][0]['id']
        self.assertEqual(self.request('/remove', dict(version=5, revision=1, pack_id=identifier, member_id='art:0'))[0], 200)
        with patch('build_progress_tracker.build', return_value=self.catalog):
            status, refreshed = self.request('/refresh', dict(version=5, revision=2))
        self.assertEqual((status, refreshed['revision']), (200, 3))
        self.assertEqual(self.request()[1]['revision'], 3)


if __name__ == '__main__':
    unittest.main()
