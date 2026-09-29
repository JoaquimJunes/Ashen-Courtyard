"""Editable image-pack membership; never changes source files or annotations."""
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import uuid

from art_pack_edits import effective_catalog, suggest_packs

MAX_BYTES = 16 * 1024 * 1024
MAX_PACKS = 2000
MAX_MEMBERS = 20000


class PackError(Exception):
    def __init__(self, code, status, message, state=None):
        super().__init__(message)
        self.code, self.status, self.state = code, status, state


def empty_edits():
    return dict(version=1, revision=0, custom_packs=[], excluded_members={}, history=[])


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def decode(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate JSON key')
            result[key] = value
        return result
    def invalid_number(value):
        raise ValueError('Invalid JSON number')
    return json.loads(raw.decode('utf-8'), object_pairs_hook=unique, parse_constant=invalid_number)


def identifier(value):
    return isinstance(value, str) and value.startswith('art:') and len(value) <= 200 and not any(ord(c) < 32 for c in value)


def members_valid(values):
    return (isinstance(values, list) and len(values) <= MAX_MEMBERS
            and all(identifier(value) for value in values) and len(values) == len(set(values)))


def validate_edits(data):
    if not isinstance(data, dict) or set(data) != {'version', 'revision', 'custom_packs', 'excluded_members', 'history'}:
        raise ValueError('Invalid pack document fields')
    if type(data['version']) is not int or data['version'] != 1 or type(data['revision']) is not int or data['revision'] < 0:
        raise ValueError('Invalid pack document version or revision')
    packs = data['custom_packs']
    if not isinstance(packs, list) or len(packs) > MAX_PACKS:
        raise ValueError('Too many custom packs')
    seen = set()
    for pack in packs:
        if not isinstance(pack, dict) or set(pack) != {'id', 'title', 'members', 'created_at'}:
            raise ValueError('Invalid custom pack fields')
        if (not isinstance(pack['id'], str) or not re.fullmatch(r'art:pack:user-[0-9a-f]{32}', pack['id'])
                or pack['id'] in seen or not title_valid(pack['title']) or not members_valid(pack['members'])):
            raise ValueError('Invalid custom pack')
        seen.add(pack['id'])
        date_valid(pack['created_at'])
    exclusions = data['excluded_members']
    if (not isinstance(exclusions, dict) or len(exclusions) > MAX_PACKS
            or any(not identifier(key) or not key.startswith('art:pack:') or not members_valid(value)
                   for key, value in exclusions.items())):
        raise ValueError('Invalid excluded pack members')
    if not isinstance(data['history'], list):
        raise ValueError('Invalid pack history')
    for event in data['history']:
        if (not isinstance(event, dict) or set(event) != {'at', 'action', 'pack_id', 'members', 'revision'}
                or event['action'] not in {'create', 'remove', 'refresh'}
                or not members_valid(event['members'])
                or type(event['revision']) is not int or not 1 <= event['revision'] <= data['revision']
                or (event['pack_id'] != '' and not identifier(event['pack_id']))):
            raise ValueError('Invalid pack activity')
        date_valid(event['at'])
    encoded(data)  # Reject lone surrogate strings before filesystem writes.


def title_valid(value):
    return isinstance(value, str) and bool(value.strip()) and len(value) <= 200 and not any(ord(c) < 32 for c in value)


def date_valid(value):
    if not isinstance(value, str) or len(value) > 64:
        raise ValueError('Invalid date')
    datetime.fromisoformat(value.replace('Z', '+00:00'))


class ArtPackStore:
    def __init__(self, root, tracking_store):
        self.root = Path(root).resolve()
        self.store = tracking_store
        self.path = self.store.path.with_name('pack_edits.json' if self.store.path.name == 'tracking.json'
                                              else self.store.path.stem + '.packs.json')
        self.backup_path = self.path.with_name(self.path.name + '.bak')
        self.catalog_path = self.root / 'docs/tracker/catalog.json'

    def _error(self, message, code='validation', status=400, state=None):
        raise PackError(code, status, message, state)

    def _read(self):
        try:
            if self.path.is_symlink() or self.backup_path.is_symlink():
                raise ValueError('Pack records must not be symbolic links')
            if not self.path.exists():
                if self.backup_path.exists():
                    raise ValueError('Pack records are missing but the recovery copy exists')
                return empty_edits(), None
            with self.path.open('rb') as stream:
                raw = stream.read(MAX_BYTES + 1)
            if len(raw) > MAX_BYTES:
                raise ValueError('Pack records exceed the storage limit')
            data = decode(raw)
            validate_edits(data)
            return data, raw
        except (OSError, ValueError, UnicodeError, RecursionError) as error:
            self._error('Pack records cannot be read safely. Inspect pack_edits.json and its .bak recovery copy; no records were replaced.', 'storage', 503)

    def _catalog(self):
        try:
            raw = self.catalog_path.read_bytes()
            catalog = decode(raw)
            if not isinstance(catalog, dict) or not isinstance(catalog.get('art'), list):
                raise ValueError('Invalid catalog')
            for key in ('art', 'packs', 'features', 'animation_clips', 'animation_categories'):
                values = catalog.get(key, [])
                if (not isinstance(values, list) or any(not isinstance(entry, dict) or not isinstance(entry.get('id'), str)
                                                       for entry in values)):
                    raise ValueError('Invalid catalog entries')
            return catalog
        except (OSError, ValueError, UnicodeError, RecursionError):
            self._error('The Art Book catalog is unavailable. Rebuild it before editing packs.', 'storage', 503)

    def _project(self, catalog, edits):
        try:
            return effective_catalog(catalog, edits)
        except (KeyError, TypeError, ValueError, RecursionError):
            self._error('The pack catalog is malformed. Rebuild it before editing packs; saved membership has not changed.', 'storage', 503)

    def revision_locked(self):
        """Membership token for annotation saves holding the same shared lock."""
        return self._read()[0]['revision']

    def effective_catalog_locked(self):
        """Called by Trash while the shared tracking lock is already held."""
        edits, _ = self._read()
        catalog = self._project(self._catalog(), edits)
        return catalog, hashlib.sha256(encoded({'catalog': catalog, 'pack_edits': edits})).hexdigest()

    def _hidden(self):
        hook = self.store.trash_snapshot_locked
        return set(hook()['hidden_ids']) if hook else set()

    def _snapshot(self, edits, catalog=None):
        catalog = self._catalog() if catalog is None else catalog
        effective = self._project(catalog, edits)
        try:
            suggestions = suggest_packs(catalog, edits=edits, hidden_ids=self._hidden())
        except (KeyError, TypeError, ValueError, RecursionError):
            self._error('The image catalog cannot be searched safely. Rebuild it before editing packs.', 'storage', 503)
        return dict(version=1, revision=edits['revision'], catalog=effective, suggestions=suggestions)

    def read(self):
        with self.store.lock:
            return self._snapshot(self._read()[0])

    def _request(self, payload, fields):
        if not isinstance(payload, dict) or set(payload) != {'version', 'revision', *fields}:
            self._error('Invalid pack request fields.')
        if type(payload['version']) is not int or payload['version'] != 5:
            self._error('Reload the tracker before editing packs.', 'reload_required', 409)
        if type(payload['revision']) is not int or payload['revision'] < 0:
            self._error('Pack revision must be a nonnegative integer.')
        edits, raw = self._read()
        if payload['revision'] != edits['revision']:
            self._error('Packs changed in another tab. Refresh packs and review your selection again.', 'conflict', 409,
                        self._snapshot(edits))
        return edits, raw

    def _write(self, edits, previous, action, pack_id='', members=None):
        edits = deepcopy(edits)
        edits['revision'] += 1
        edits['history'].append(dict(at=datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z'),
                                     action=action, pack_id=pack_id, members=members or [], revision=edits['revision']))
        try:
            validate_edits(edits)
            data = encoded(edits)
            if len(data) > MAX_BYTES:
                self._error('Pack storage is full. Preserve a backup before archiving old activity.')
            self.path.parent.mkdir(parents=True, exist_ok=True)
            if previous is not None:
                self.store._atomic_replace(self.backup_path, previous)
            self.store._atomic_replace(self.path, data)
        except (OSError, ValueError, UnicodeError, RecursionError):
            self._error('Could not save packs. Your existing packs and original images were preserved; retry after fixing storage.', 'storage', 503)
        return edits

    def _images(self, members, catalog):
        if not members_valid(members) or len(members) < 2:
            self._error('Select at least two different images (at most 20,000).')
        assets = {entry['id']: entry for entry in catalog['art']}
        hidden = self._hidden()
        for member in members:
            entry = assets.get(member)
            if not entry or not entry.get('image') or entry.get('missing') or member in hidden:
                self._error('Every selected member must be an existing image outside Trash: ' + member)
            relative = entry.get('path')
            if not isinstance(relative, str):
                self._error('A selected image has no source file: ' + member)
            source = (self.root / relative).resolve()
            if not source.is_relative_to(self.root) or not source.is_file():
                self._error('A selected image is missing or outside the project: ' + member)

    def create(self, payload):
        with self.store.lock:
            edits, raw = self._request(payload, {'title', 'members'})
            if not title_valid(payload['title']):
                self._error('Pack name must contain 1–200 characters without control characters.')
            catalog = self._catalog()
            self._images(payload['members'], catalog)
            if len(edits['custom_packs']) >= MAX_PACKS:
                self._error('The custom pack limit has been reached.')
            pack = dict(id='art:pack:user-' + uuid.uuid4().hex, title=payload['title'].strip(),
                        members=list(payload['members']), created_at=datetime.now(timezone.utc).isoformat())
            edits['custom_packs'].append(pack)
            self._snapshot(edits, catalog)  # Validate the complete view before committing.
            edits = self._write(edits, raw, 'create', pack['id'], pack['members'])
            return self._snapshot(edits, catalog)

    def remove(self, payload):
        with self.store.lock:
            edits, raw = self._request(payload, {'pack_id', 'member_id'})
            if not identifier(payload['pack_id']) or not identifier(payload['member_id']):
                self._error('Choose a pack and an image from the current catalog.')
            catalog = self._catalog()
            effective = self._project(catalog, edits)
            pack = next((pack for pack in effective.get('packs', []) if pack['id'] == payload['pack_id']), None)
            if pack is None or payload['member_id'] not in pack.get('members', []):
                self._error('The image is no longer in this pack. Refresh packs and try again.', 'conflict', 409,
                            self._snapshot(edits, catalog))
            hidden = self._hidden()
            if payload['pack_id'] in hidden or payload['member_id'] in hidden:
                self._error('Restore the pack or image from Trash before editing membership.')
            custom = next((item for item in edits['custom_packs'] if item['id'] == pack['id']), None)
            if custom is not None:
                custom['members'].remove(payload['member_id'])
            else:
                excluded = edits['excluded_members'].setdefault(pack['id'], [])
                if payload['member_id'] not in excluded:
                    excluded.append(payload['member_id'])
            self._snapshot(edits, catalog)
            edits = self._write(edits, raw, 'remove', pack['id'], [payload['member_id']])
            return self._snapshot(edits, catalog)

    def refresh(self, payload):
        from build_progress_tracker import build, write_catalog
        with self.store.lock:
            edits, raw = self._request(payload, set())
            try:
                # Discovery is explicit. The builder never imports or converts assets.
                fresh = build(root=self.root, out=self.catalog_path.parent, write=False, pack_document=empty_edits())
                self._snapshot(edits, fresh)  # Complete projection before replacing files.
            except Exception as error:
                self._error('Pack refresh failed while reading project files. Existing packs were preserved: ' + str(error), 'storage', 503)
            updated = self._write(edits, raw, 'refresh')
            try:
                write_catalog(fresh, self.catalog_path.parent)
            except Exception as error:
                # The builder restores its catalog pair on failure. Restore our
                # revision too; an interrupted process merely leaves a harmless
                # extra revision, never a lost member or an edited source asset.
                try:
                    if raw is None:
                        self.path.unlink(missing_ok=True)
                    else:
                        self.store._atomic_replace(self.path, raw)
                except OSError:
                    self._error('Refresh could not finish. Pack records remain recoverable; inspect the project recovery copies before retrying.', 'storage', 503)
                self._error('Pack refresh could not be saved. Existing packs were preserved: ' + str(error), 'storage', 503)
            return self._snapshot(updated, fresh)
