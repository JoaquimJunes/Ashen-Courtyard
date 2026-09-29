#!/usr/bin/env python3
"""Serve the project tracker locally and persist its sparse human annotations.

Run from any directory: python3 tools/serve_progress_tracker.py
The generated catalog remains separate from docs/tracker/tracking.json.
"""

import argparse
from copy import deepcopy
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from functools import lru_cache
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import tempfile
import threading
import unicodedata
from urllib.parse import unquote, urlsplit, urlunsplit


ROOT = Path(__file__).resolve().parents[1]
MAX_REQUEST_BYTES = 64 * 1024 * 1024
MAX_STATE_BYTES = 64 * 1024 * 1024
MAX_ITEMS = 20000
STATUSES = {'', 'Planned', 'In progress', 'Ready for review', 'Completed', 'Deferred'}
ATTENTION = {'Bug found', 'Needs improvement', 'Needs testing', 'Needs visual review', 'Blocked', 'SPECIAL'}
PRIORITIES = {'High', 'Normal', 'Low'}
VERSION = 5
REVIEW_LABELS = {'', 'Approved', 'Scrap'}
LEGACY_METADATA_FIELDS = ('status', 'attention', 'priority', 'note', 'checklist', 'related')
V3_METADATA_DEFAULTS = {'display_name': '', 'animation_categories': None, 'animation_tags': None}
V4_METADATA_DEFAULTS = {**V3_METADATA_DEFAULTS, 'review_label': ''}
NEW_METADATA_DEFAULTS = {**V4_METADATA_DEFAULTS, 'art_tags': []}
METADATA_FIELDS = (*LEGACY_METADATA_FIELDS, *NEW_METADATA_DEFAULTS)
VERSION_FIELDS = {2: LEGACY_METADATA_FIELDS, 3: (*LEGACY_METADATA_FIELDS, *V3_METADATA_DEFAULTS),
                  4: (*LEGACY_METADATA_FIELDS, *V4_METADATA_DEFAULTS), 5: METADATA_FIELDS}
ART_TAG_SUGGESTIONS = ('Combat', 'Magic', 'Clothing', 'Armor', 'Weapons', 'Items')
EXCLUDED_PARTS = {'.git', '.codex', '.agents', '.artifacts', '.godot', '__pycache__'}


class ValidationError(ValueError):
    """A request or persisted document does not conform to the tracker schema."""


class StorageError(OSError):
    """Storage cannot be safely read or replaced; callers must retain their edits."""


class ReloadRequiredError(Exception):
    """An old browser must reload rather than erase fields it cannot represent."""

    def __init__(self, message=None):
        super().__init__(message or 'The tracker saving format changed. Reload this page before saving; your edits have not been written.')


class ConflictError(Exception):
    def __init__(self, state):
        super().__init__('The tracker changed elsewhere. Reload before saving again.')
        self.state = state


class PackConflictError(Exception):
    def __init__(self, revision):
        super().__init__('Image-pack membership changed in another tab. Reload project data and review the pack before saving; no annotations were changed.')
        self.revision = revision


def empty_state():
    return {'version': VERSION, 'revision': 0, 'items': {}, 'history': []}


def exact_keys(value, keys, label):
    if not isinstance(value, dict) or set(value) != set(keys):
        raise ValidationError(f'{label} must contain exactly: {", ".join(keys)}.')


def text_value(value, label, maximum, *, nonempty=False):
    if not isinstance(value, str) or len(value) > maximum:
        raise ValidationError(f'{label} must be text of at most {maximum} characters.')
    if nonempty and (not value.strip() or any(ord(c) < 32 for c in value)):
        raise ValidationError(f'{label} must be nonempty text without control characters.')
    # Lone surrogate escapes are legal JSON but cannot be written as UTF-8.
    try:
        value.encode('utf-8')
    except UnicodeEncodeError as error:
        raise ValidationError(f'{label} must contain valid Unicode.') from error
    return value


def item_id(value):
    text_value(value, 'Item ID', 200, nonempty=True)
    if value in {'__proto__', 'constructor', 'prototype'}:
        raise ValidationError('Reserved item ID.')
    return value


def safe_relative_path(value, root):
    """Accept project-relative POSIX paths, including not-yet-created sources."""
    text_value(value, 'Source path', 500)
    if not value:
        return
    parts = value.split('/')
    if ('\\' in value or ':' in value or any(ord(c) < 32 for c in value)
            or any(part in {'', '.', '..'} or part in EXCLUDED_PARTS for part in parts)):
        raise ValidationError('Source must be a safe path relative to the project.')
    try:
        relative = (root / value).resolve().relative_to(root)
    except (ValueError, OSError, RuntimeError) as error:
        raise ValidationError('Source must remain inside the project.') from error
    if EXCLUDED_PARTS.intersection(relative.parts):
        raise ValidationError('Source cannot refer to private project files.')


@lru_cache(maxsize=4)
def _taxonomy_at(path, modified, size):
    try:
        data = json.loads(Path(path).read_text(encoding='utf-8'))
        if not isinstance(data, dict) or data.get('version') != 1:
            raise ValueError('Unsupported vocabulary version')
        result = {}
        for field in ('categories', 'tags'):
            values = data[field]
            if (not isinstance(values, list) or any(not isinstance(v, str) or not v.strip() for v in values)
                    or len(set(values)) != len(values)):
                raise ValueError('Invalid vocabulary labels')
            result[field] = frozenset(values)
        return result
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise StorageError('Animation vocabulary is unavailable or invalid. Restore tools/art_animation_taxonomy.json before saving labels.') from error


def animation_taxonomy():
    path = ROOT / 'tools/art_animation_taxonomy.json'
    try:
        info = path.stat()
    except OSError as error:
        raise StorageError('Animation vocabulary is unavailable. Restore tools/art_animation_taxonomy.json before saving labels.') from error
    return _taxonomy_at(str(path), info.st_mtime_ns, info.st_size)


@lru_cache(maxsize=4)
def _locked_clips_at(path, modified, size):
    """Read generated identities only; catalog lookup never imports an asset."""
    try:
        catalog = json.loads(Path(path).read_text(encoding='utf-8'))
        clips = catalog.get('animation_clips', [])
        if not isinstance(clips, list) or any(not isinstance(clip, dict) or not isinstance(clip.get('id'), str)
                                             for clip in clips):
            raise ValueError('Invalid clip records')
        return frozenset(clip['id'] for clip in clips if clip.get('identity_editable') is False)
    except (OSError, ValueError, AttributeError) as error:
        raise StorageError('Animation identities cannot be read. Rebuild the tracker catalog before editing clips.') from error


def locked_clip_ids(root):
    path = root / 'docs/tracker/catalog.json'
    try:
        info = path.stat()
    except FileNotFoundError:
        return frozenset()
    except OSError as error:
        raise StorageError('Animation identities cannot be read. Check the tracker catalog before editing clips.') from error
    return _locked_clips_at(str(path), info.st_mtime_ns, info.st_size)


def validate_metadata(metadata, root, *, version=VERSION, identifier=None):
    exact_keys(metadata, VERSION_FIELDS[version], 'Item metadata')
    if not isinstance(metadata['status'], str) or metadata['status'] not in STATUSES:
        raise ValidationError('Invalid workflow status.')
    if not isinstance(metadata['priority'], str) or metadata['priority'] not in PRIORITIES:
        raise ValidationError('Invalid priority.')
    flags = metadata['attention']
    if (not isinstance(flags, list) or len(flags) > len(ATTENTION)
            or any(not isinstance(flag, str) or flag not in ATTENTION for flag in flags)
            or len(set(flags)) != len(flags)):
        raise ValidationError('Attention must be a list of unique supported flags.')
    text_value(metadata['note'], 'Note', 10000)
    checklist = metadata['checklist']
    if not isinstance(checklist, list) or len(checklist) > 200:
        raise ValidationError('Checklist must contain at most 200 entries.')
    seen = set()
    for entry in checklist:
        exact_keys(entry, ('id', 'text', 'done', 'source'), 'Checklist entry')
        check_identifier = text_value(entry['id'], 'Checklist ID', 128, nonempty=True)
        if check_identifier in seen:
            raise ValidationError('Checklist IDs must be unique within an item.')
        seen.add(check_identifier)
        text_value(entry['text'], 'Checklist text', 2000, nonempty=True)
        if type(entry['done']) is not bool:
            raise ValidationError('Checklist done must be a boolean.')
        safe_relative_path(entry['source'], root)
    if metadata['status'] == 'Completed' and (not checklist or not all(entry['done'] for entry in checklist)):
        raise ValidationError('Completed requires a nonempty checklist with every entry checked.')
    related = metadata['related']
    if not isinstance(related, list) or len(related) > 200:
        raise ValidationError('Related features must contain at most 200 IDs.')
    for related_identifier in related:
        item_id(related_identifier)
    if len(set(related)) != len(related):
        raise ValidationError('Related feature IDs must be unique.')
    normalized = deepcopy(metadata)
    if version >= 3:
        name = metadata['display_name']
        if not isinstance(name, str) or any(ord(c) < 32 for c in name):
            raise ValidationError('Display name must be text without control characters.')
        normalized['display_name'] = text_value(name.strip(), 'Display name', 200)
        for field, vocabulary in (('animation_categories', 'categories'), ('animation_tags', 'tags')):
            values = metadata[field]
            if values is None:
                continue
            if not isinstance(values, list) or any(not isinstance(value, str) for value in values):
                raise ValidationError(f'{field} must be null or a list of controlled labels.')
            allowed = animation_taxonomy()[vocabulary]
            if len(values) > len(allowed) or any(value not in allowed for value in values) or len(set(values)) != len(values):
                raise ValidationError(f'{field} must contain unique supported labels.')
    if version >= 4 and (not isinstance(metadata['review_label'], str) or metadata['review_label'] not in REVIEW_LABELS):
        raise ValidationError('Review label must be Approved, Scrap or empty.')
    if version >= 4 and metadata['review_label'] and identifier is not None and not identifier.startswith('art:'):
        raise ValidationError('Approved and Scrap labels are available only in Art Book.')
    if version >= 5:
        tags = metadata['art_tags']
        if not isinstance(tags, list) or len(tags) > 32:
            raise ValidationError('Use at most 32 tags per entry.')
        if tags and identifier is not None and not identifier.startswith('art:'):
            raise ValidationError('Art tags are available only in Art Book.')
        normalized_tags = []
        for tag in tags:
            if not isinstance(tag, str) or any(ord(c) < 32 or ord(c) == 127 for c in tag):
                raise ValidationError('Tags must be text without control characters.')
            tag = ' '.join(unicodedata.normalize('NFKC', tag).split())
            tag = text_value(tag, 'Tag', 60, nonempty=True)
            normalized_tags.append(next((s for s in ART_TAG_SUGGESTIONS if s.lower() == tag.lower()), tag))
        if len({tag.lower() for tag in normalized_tags}) != len(tags):
            raise ValidationError('This entry already has that tag.')
        normalized['art_tags'] = normalized_tags
    return normalized


def validate_state(state, root):
    exact_keys(state, ('version', 'revision', 'items', 'history'), 'Tracker state')
    if type(state['version']) is not int or state['version'] not in VERSION_FIELDS:
        raise ValidationError('Unsupported tracker state version; expected version 2, 3, 4 or 5.')
    version = state['version']
    if type(state['revision']) is not int or state['revision'] < 0:
        raise ValidationError('Revision must be a nonnegative integer.')
    items = state['items']
    if not isinstance(items, dict) or len(items) > MAX_ITEMS:
        raise ValidationError(f'Tracker items must contain at most {MAX_ITEMS} records.')
    for identifier, metadata in items.items():
        item_id(identifier)
        validate_metadata(metadata, root, version=version, identifier=identifier)
    if not isinstance(state['history'], list):
        raise ValidationError('History must be a list.')
    for event in state['history']:
        if (not isinstance(event, dict) or not {'at', 'id', 'fields'}.issubset(event)
                or set(event) - {'at', 'id', 'fields', 'before', 'after', 'revision'}):
            raise ValidationError('Invalid tracker history entry.')
        text_value(event['at'], 'History timestamp', 64, nonempty=True)
        try:
            datetime.fromisoformat(event['at'].replace('Z', '+00:00'))
        except ValueError as error:
            raise ValidationError('History timestamp must be an ISO date.') from error
        item_id(event['id'])
        fields = event['fields']
        if (not isinstance(fields, list) or not fields
                or any(not isinstance(field, str) or field not in VERSION_FIELDS[version] for field in fields)
                or len(set(fields)) != len(fields)):
            raise ValidationError('Invalid changed fields in history.')
        for key in ('before', 'after'):
            if key in event and event[key] is not None:
                # Historical activity keeps the metadata shape recorded at that time.
                if not isinstance(event[key], dict):
                    raise ValidationError('History snapshots must contain item metadata.')
                snapshot_version = next((number for number, fields in VERSION_FIELDS.items() if set(event[key]) == set(fields)), None)
                if snapshot_version is None or snapshot_version > version:
                    raise ValidationError('History cannot contain invalid or newer metadata.')
                validate_metadata(event[key], root, version=snapshot_version, identifier=event['id'])
        if 'revision' in event and (type(event['revision']) is not int
                                    or not 1 <= event['revision'] <= state['revision']):
            raise ValidationError('Invalid history revision.')


def migrate_state(state):
    """Upgrade records in memory; historical events remain byte-for-byte equivalent."""
    if state['version'] == VERSION:
        return state
    migrated = deepcopy(state)
    migrated['version'] = VERSION
    migrated['items'] = {identifier: {**deepcopy(NEW_METADATA_DEFAULTS), **metadata}
                         for identifier, metadata in state['items'].items()}
    return migrated


def decode_json(data):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValidationError(f'Duplicate JSON key: {key}.')
            result[key] = value
        return result

    def invalid_number(value):
        raise ValidationError(f'Invalid JSON number: {value}.')

    try:
        return json.loads(data.decode('utf-8'), object_pairs_hook=unique_object,
                          parse_constant=invalid_number)
    except ValidationError:
        raise
    except (UnicodeDecodeError, ValueError, RecursionError) as error:
        raise ValidationError('Request or stored document is not valid UTF-8 JSON.') from error


class TrackerStore:
    """Read on every operation so stale tabs and external edits cannot be lost."""

    def __init__(self, path, root):
        self.path = Path(path).absolute()
        self.root = Path(root).resolve()
        self.backup_path = self.path.with_name(self.path.name + '.bak')
        self.version_backup_paths = {version: self.path.with_name(self.path.name + f'.v{version}.bak')
                                     for version in VERSION_FIELDS if version < VERSION}
        self.legacy_backup_path = self.version_backup_paths[2]
        self.lock = threading.Lock()
        # The recoverable Trash store supplies this nonlocking snapshot hook.
        # Every call below already holds the shared lock exactly once.
        self.trash_snapshot_locked = None
        self.trash_assert_editable_locked = None
        self.pack_catalog_locked = None
        self.pack_revision_locked = None

    def _read(self):
        if self.path.is_symlink():
            raise StorageError('Tracker state must be a regular file, not a symbolic link.')
        try:
            with self.path.open('rb') as stream:
                raw = stream.read(MAX_STATE_BYTES + 1)
        except FileNotFoundError:
            if self.backup_path.exists() or any(path.exists() for path in self.version_backup_paths.values()):
                raise StorageError('Tracker state is missing but its backup exists. Restore it before saving.')
            return empty_state(), None
        except OSError as error:
            raise StorageError('Cannot read tracker state. No data was replaced.') from error
        try:
            if len(raw) > MAX_STATE_BYTES:
                raise ValidationError('Tracker state exceeds its storage limit.')
            state = decode_json(raw)
            validate_state(state, self.root)
        except (ValidationError, ValueError, RecursionError) as error:
            raise StorageError('Tracker state is corrupt or unsupported. No data was replaced. '
                               'Restore tracking.json from its .bak recovery copy after inspecting both files.') from error
        return migrate_state(state), raw

    def _with_trash(self, state):
        trash = self.trash_snapshot_locked() if self.trash_snapshot_locked else {'transactions': [], 'hidden_ids': []}
        return {**state, 'trash': trash}

    def read(self, *, include_trash=False):
        with self.lock:
            state = self._read()[0]
            return self._with_trash(state) if include_trash else state

    @staticmethod
    def _atomic_replace(path, data):
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='wb', dir=path.parent,
                                             prefix='.' + path.name + '.', delete=False) as stream:
                temporary = Path(stream.name)
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)

    def update(self, payload, *, include_trash=False):
        if not isinstance(payload, dict):
            raise ValidationError('Save request must be an object.')
        if type(payload.get('version')) is not int or payload['version'] != VERSION:
            raise ReloadRequiredError()
        required = ('version', 'revision', 'changes')
        exact_keys(payload, (*required, 'pack_revision') if 'pack_revision' in payload else required, 'Save request')
        if 'pack_revision' in payload and (type(payload['pack_revision']) is not int or payload['pack_revision'] < 0):
            raise ValidationError('Pack revision must be a nonnegative integer.')
        revision, changes = payload['revision'], payload['changes']
        if type(revision) is not int or revision < 0:
            raise ValidationError('Revision must be a nonnegative integer.')
        if not isinstance(changes, dict) or len(changes) > MAX_ITEMS:
            raise ValidationError(f'Changes must contain at most {MAX_ITEMS} items.')
        normalized_changes = {}
        for identifier, metadata in changes.items():
            item_id(identifier)
            normalized_changes[identifier] = validate_metadata(metadata, self.root, identifier=identifier)
        changes = normalized_changes
        with self.lock:
            state, previous_bytes = self._read()
            if revision != state['revision']:
                raise ConflictError(self._with_trash(state) if include_trash else state)
            if self.pack_revision_locked is not None:
                requires_pack_revision = any(identifier.startswith('art:pack:') and metadata['review_label'] == 'Approved'
                                             for identifier, metadata in changes.items())
                if requires_pack_revision and 'pack_revision' not in payload:
                    raise ReloadRequiredError('Reload this tracker before approving a whole pack. Its membership must be checked before saving; no annotations were changed.')
                if 'pack_revision' in payload:
                    current_pack_revision = self.pack_revision_locked()
                    if payload['pack_revision'] != current_pack_revision:
                        raise PackConflictError(current_pack_revision)
            trash = self.trash_snapshot_locked() if self.trash_snapshot_locked else {'transactions': [], 'hidden_ids': []}
            hidden_ids = set(trash['hidden_ids'])
            changed_ids = [identifier for identifier, metadata in changes.items() if state['items'].get(identifier) != metadata]
            if changed_ids and self.trash_assert_editable_locked:
                self.trash_assert_editable_locked(changed_ids)
            locked_clips = locked_clip_ids(self.root) if any(identifier.startswith('art:clip:') for identifier in changes) else frozenset()
            next_state = deepcopy(state)
            timestamp = datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
            for identifier, metadata in changes.items():
                before = state['items'].get(identifier)
                fields = [field for field in METADATA_FIELDS if before is None or before[field] != metadata[field]]
                if not fields:
                    continue
                if identifier in hidden_ids:
                    raise ValidationError('This Art Book entry is in Trash. Restore it before editing its labels or notes.')
                if identifier in locked_clips:
                    raise ValidationError(f'Clip {identifier} has no verified unique identity. Edit its parent asset until the clip identity is resolved.')
                next_state['items'][identifier] = deepcopy(metadata)
                next_state['history'].append({'at': timestamp, 'id': identifier, 'fields': fields,
                                              'before': before, 'after': deepcopy(metadata),
                                              'revision': revision + 1})
            if next_state == state:
                return {**state, 'trash': trash} if include_trash else state
            next_state['revision'] += 1
            validate_state(next_state, self.root)
            encoded = (json.dumps(next_state, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
            if len(encoded) > MAX_STATE_BYTES:
                raise ValidationError('Tracker storage limit reached. Export and archive history before adding more data.')
            try:
                self.path.parent.mkdir(parents=True, exist_ok=True)
                # A backup is only replaced by bytes already parsed and validated.
                if previous_bytes is not None:
                    previous_version = decode_json(previous_bytes)['version']
                    if previous_version in self.version_backup_paths:
                        version_backup_path = self.version_backup_paths[previous_version]
                        if version_backup_path.is_symlink():
                            raise OSError('The pre-upgrade recovery copy must not be a symbolic link.')
                        # Retain the first pre-upgrade copy independently of rotating backups.
                        if not version_backup_path.exists():
                            self._atomic_replace(version_backup_path, previous_bytes)
                    self._atomic_replace(self.backup_path, previous_bytes)
                self._atomic_replace(self.path, encoded)
            except OSError as error:
                raise StorageError('Cannot save tracker state. Your changes were not saved; retry after fixing storage.') from error
            return {**next_state, 'trash': trash} if include_trash else next_state


class TrackerServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, root=ROOT, state_path=None, port=8765):
        from art_scrap_store import ScrapError, ScrapStore
        from art_pack_store import ArtPackStore, PackError
        self.root = Path(root).resolve()
        self.store = TrackerStore(state_path or self.root / 'docs/tracker/tracking.json', self.root)
        self.scrap = ScrapStore(self.root, self.store)
        self.scrap_error = ScrapError
        self.store.trash_snapshot_locked = self.scrap.trash_locked
        self.store.trash_assert_editable_locked = self.scrap.assert_editable_locked
        self.packs = ArtPackStore(self.root, self.store)
        self.pack_error = PackError
        self.store.pack_catalog_locked = self.packs.effective_catalog_locked
        self.store.pack_revision_locked = self.packs.revision_locked
        super().__init__(('127.0.0.1', port), TrackerHandler)


class TrackerHandler(SimpleHTTPRequestHandler):
    server_version = 'LocalProgressTracker/5'

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(args[2].root), **kwargs)

    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def end_headers(self):
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'same-origin')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def _json(self, status, data):
        encoded = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(encoded)))
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(encoded)

    def _error(self, status, code, message, **extra):
        self._json(status, {'error': message, 'code': code, **extra})

    def _trusted_host(self):
        port = self.server.server_port
        allowed = {f'127.0.0.1:{port}', f'localhost:{port}'}
        if port == 80:
            allowed.update({'127.0.0.1', 'localhost'})
        hosts = self.headers.get_all('Host', [])
        if len(hosts) != 1 or hosts[0] not in allowed:
            self._error(HTTPStatus.FORBIDDEN, 'host', 'Use the local tracker address shown by the server.')
            return False
        return True

    def _request_path(self):
        try:
            parsed = urlsplit(self.path)
            if parsed.scheme or parsed.netloc:
                raise ValueError
            return unquote(parsed.path, errors='strict')
        except (ValueError, UnicodeDecodeError):
            return None

    def do_GET(self):
        if not self._trusted_host():
            return
        path = self._request_path()
        if path == '/api/tracker':
            try:
                self._json(HTTPStatus.OK, self.server.store.read(include_trash=True))
            except StorageError as error:
                self._error(HTTPStatus.SERVICE_UNAVAILABLE, 'storage', str(error))
            except self.server.scrap_error as error:
                self._scrap_error_response(error)
            return
        if path == '/api/tracker/packs':
            try:
                self._json(HTTPStatus.OK, self.server.packs.read())
            except self.server.pack_error as error:
                self._scrap_error_response(error)
            except self.server.scrap_error as error:
                self._scrap_error_response(error)
            return
        if path == '/':
            self.send_response(HTTPStatus.FOUND)
            self.send_header('Location', '/docs/tracker/')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if path is None or path.startswith('/api/'):
            self._error(HTTPStatus.NOT_FOUND, 'not_found', 'Unknown tracker endpoint.')
            return
        if self.command == 'HEAD':
            super().do_HEAD()
        else:
            super().do_GET()

    def do_HEAD(self):
        self.do_GET()

    def send_head(self):
        self._file_bytes_remaining = 0
        path = self._request_path()
        if path is None or not path.startswith('/'):
            self.send_error(HTTPStatus.FORBIDDEN)
            return None
        relative = path[1:].rstrip('/')
        try:
            safe_relative_path(relative, self.server.root)
        except ValidationError:
            self.send_error(HTTPStatus.FORBIDDEN, 'Path is outside the shared project files.')
            return None
        target = (self.server.root / relative).resolve()
        if target.is_dir():
            # Never expose directory listings, including private metadata filenames.
            if not any((target / name).is_file() for name in ('index.html', 'index.htm')):
                self.send_error(HTTPStatus.NOT_FOUND)
                return None
            for name in ('index.html', 'index.htm'):
                if (target / name).exists():
                    try:
                        safe_relative_path((target / name).relative_to(self.server.root).as_posix(), self.server.root)
                    except ValidationError:
                        self.send_error(HTTPStatus.FORBIDDEN)
                        return None
            if not path.endswith('/'):
                parsed = urlsplit(self.path)
                self.send_response(HTTPStatus.MOVED_PERMANENTLY)
                self.send_header('Location', urlunsplit(parsed._replace(path=parsed.path + '/')))
                self.send_header('Content-Length', '0')
                self.end_headers()
                return None
            target = next(target / name for name in ('index.html', 'index.htm')
                          if (target / name).is_file())
        elif path.endswith('/') or not target.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return None
        try:
            stream = target.open('rb')
        except OSError:
            self.send_error(HTTPStatus.NOT_FOUND)
            return None
        try:
            info = os.fstat(stream.fileno())
            modified = datetime.fromtimestamp(info.st_mtime, timezone.utc).replace(microsecond=0)
            # Preserve ordinary conditional GET behavior. Range requests apply only
            # after a normal request would have returned the full representation.
            if 'If-None-Match' not in self.headers:
                since = self._http_date(self.headers.get('If-Modified-Since'))
                if since is not None and modified <= since:
                    self.send_response(HTTPStatus.NOT_MODIFIED)
                    self.end_headers()
                    stream.close()
                    return None
            ranges = self.headers.get_all('Range', [])
            if_range = self.headers.get('If-Range')
            if if_range is not None and self._http_date(if_range) != modified:
                # We do not issue entity tags. Unknown/stale validators request
                # the complete current file, never a slice of another version.
                ranges = []
            start, end = 0, info.st_size - 1
            if ranges:
                selected = self._byte_range(ranges, info.st_size)
                if selected is None:
                    self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                    self.send_header('Accept-Ranges', 'bytes')
                    self.send_header('Content-Range', f'bytes */{info.st_size}')
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    stream.close()
                    return None
                start, end = selected
            length = end - start + 1
            stream.seek(start)
            self._file_bytes_remaining = length
            self.send_response(HTTPStatus.PARTIAL_CONTENT if ranges else HTTPStatus.OK)
            self.send_header('Content-Type', self.guess_type(str(target)))
            self.send_header('Content-Length', str(length))
            self.send_header('Last-Modified', self.date_time_string(info.st_mtime))
            self.send_header('Accept-Ranges', 'bytes')
            if ranges:
                self.send_header('Content-Range', f'bytes {start}-{end}/{info.st_size}')
            self.end_headers()
            return stream
        except Exception:
            stream.close()
            raise

    @staticmethod
    def _http_date(value):
        if value is None:
            return None
        try:
            result = parsedate_to_datetime(value)
            return result.replace(tzinfo=timezone.utc) if result.tzinfo is None else result
        except (TypeError, ValueError, OverflowError):
            return None

    @staticmethod
    def _byte_range(headers, size):
        """Support one byte interval; malformed/multiple/empty intervals get 416."""
        if len(headers) != 1 or len(headers[0]) > 256 or size == 0:
            return None
        match = re.fullmatch(r'bytes=([0-9]*)-([0-9]*)', headers[0].strip(), re.IGNORECASE)
        if match is None or not any(match.groups()):
            return None
        first, last = match.groups()
        if not first:
            suffix = int(last)
            return (max(0, size - suffix), size - 1) if suffix > 0 else None
        start = int(first)
        end = min(int(last), size - 1) if last else size - 1
        return (start, end) if start <= end and start < size else None

    def copyfile(self, source, outputfile):
        # The standard handler copies until EOF. A range must stop at its last
        # byte, and streaming in fixed chunks keeps large media out of memory.
        remaining = self._file_bytes_remaining
        while remaining:
            data = source.read(min(64 * 1024, remaining))
            if not data:
                break
            outputfile.write(data)
            remaining -= len(data)

    def do_PUT(self):
        if not self._trusted_host():
            return
        if self._request_path() != '/api/tracker':
            self._error(HTTPStatus.NOT_FOUND, 'not_found', 'Unknown tracker endpoint.')
            return
        self._write_json(lambda payload: self.server.store.update(payload, include_trash=True))

    def do_POST(self):
        if not self._trusted_host():
            return
        actions = {'/api/tracker/scrap/prepare': self.server.scrap.prepare,
                   '/api/tracker/scrap/delete': self.server.scrap.delete,
                   '/api/tracker/scrap/restore': self.server.scrap.restore,
                   '/api/tracker/packs/create': self.server.packs.create,
                   '/api/tracker/packs/remove': self.server.packs.remove,
                   '/api/tracker/packs/refresh': self.server.packs.refresh}
        action = actions.get(self._request_path())
        if action is None:
            self._error(HTTPStatus.NOT_FOUND, 'not_found', 'Unknown tracker endpoint.')
            return
        self._write_json(action)

    def _scrap_error_response(self, error):
        extra = {'state': error.state} if error.state is not None else {}
        if error.code == 'reload_required':
            extra['required_version'] = VERSION
        self._error(error.status, error.code, str(error), **extra)

    def _write_json(self, action):
        """Metadata saves, pack edits and Trash commands use the same local-write boundary."""
        origins = self.headers.get_all('Origin', [])
        if ((origins and origins != ['http://' + self.headers['Host']])
                or self.headers.get('Sec-Fetch-Site', 'same-origin') not in {'same-origin', 'none'}):
            self._error(HTTPStatus.FORBIDDEN, 'origin', 'Writes must come from this tracker page.')
            return
        if self.headers.get('Content-Type', '').split(';', 1)[0].strip().lower() != 'application/json':
            self._error(HTTPStatus.UNSUPPORTED_MEDIA_TYPE, 'content_type', 'Send application/json.')
            return
        lengths = self.headers.get_all('Content-Length', [])
        if not lengths:
            self._error(HTTPStatus.LENGTH_REQUIRED, 'length', 'Content-Length is required.')
            return
        if (len(lengths) != 1 or len(lengths[0]) > 10 or not lengths[0].isascii()
                or not lengths[0].isdigit() or 'Transfer-Encoding' in self.headers):
            self._error(HTTPStatus.BAD_REQUEST, 'length', 'Invalid request body length.')
            return
        length = int(lengths[0])
        if length > MAX_REQUEST_BYTES:
            self._error(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, 'too_large', 'Save request exceeds 64 MiB.')
            return
        try:
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise ValidationError('Request body was incomplete.')
            payload = decode_json(raw)
            if isinstance(payload, dict) and (type(payload.get('version')) is not int or payload['version'] != VERSION):
                raise ReloadRequiredError()
            state = action(payload)
        except (ValidationError, RecursionError) as error:
            self._error(HTTPStatus.BAD_REQUEST, 'validation', str(error))
        except ReloadRequiredError as error:
            self._error(HTTPStatus.CONFLICT, 'reload_required', str(error), required_version=VERSION)
        except ConflictError as error:
            self._error(HTTPStatus.CONFLICT, 'conflict', str(error), state=error.state)
        except PackConflictError as error:
            self._error(HTTPStatus.CONFLICT, 'pack_conflict', str(error), pack_revision=error.revision)
        except StorageError as error:
            self._error(HTTPStatus.SERVICE_UNAVAILABLE, 'storage', str(error))
        except (self.server.scrap_error, self.server.pack_error) as error:
            self._scrap_error_response(error)
        except (OSError, TimeoutError):
            self._error(HTTPStatus.BAD_REQUEST, 'body', 'Unable to read the complete request body.')
        else:
            self._json(HTTPStatus.OK, state)

    def do_OPTIONS(self):
        self._error(HTTPStatus.FORBIDDEN, 'origin', 'Cross-origin access is not supported.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8765, help='Local port (default: 8765).')
    parser.add_argument('--root', type=Path, default=ROOT, help='Project root to serve.')
    parser.add_argument('--state', type=Path, help='Alternate tracker state path (for testing).')
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        parser.error('--port must be between 0 and 65535.')
    if not args.root.is_dir():
        parser.error('--root must be an existing directory.')
    with TrackerServer(args.root, args.state, args.port) as server:
        print(f'Tracker: http://127.0.0.1:{server.server_port}/docs/tracker/', flush=True)
        print(f'Saved annotations: {server.store.path}', flush=True)
        print(f'Saved image packs: {server.packs.path}', flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
