"""Recoverable Art Book disposal. Catalog identities never imply file ownership."""
from copy import deepcopy
from datetime import datetime, timezone
import ctypes
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import time

VERSION = 5
TRASH = '.artifacts/tracker-trash'
SKIP = {'.git', '.godot', '.artifacts', '.codex', '.agents', 'node_modules', 'vendor', '__pycache__', 'graphify-out'}


class ScrapError(Exception):
    def __init__(self, code, status, message, state=None):
        super().__init__(message)
        self.code, self.status, self.state = code, status, state


def _now():
    return datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def _encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def _rename_noreplace(source, target):
    """Linux atomic no-clobber rename; an existence check alone is insufficient."""
    function = getattr(ctypes.CDLL(None, use_errno=True), 'renameat2', None)
    if function is None:
        raise OSError(errno.ENOTSUP, 'Atomic no-overwrite file moves are unavailable on this platform.')
    function.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    function.restype = ctypes.c_int
    if function(-100, os.fsencode(source), -100, os.fsencode(target), 1) != 0:
        error = ctypes.get_errno()
        if error in {errno.ENOSYS, errno.EINVAL, errno.ENOTSUP}:
            raise OSError(error, 'Atomic no-overwrite file moves are unsupported by this filesystem.')
        raise OSError(error, os.strerror(error), str(target))


class ScrapStore:
    def __init__(self, root, tracking_store):
        self.root = Path(root).resolve()
        self.store = tracking_store
        self.pending = {}
        with self.store.lock:
            self._recover()

    def _error(self, message, code='validation', status=400, state=None):
        raise ScrapError(code, status, message, state)

    def _safe(self, relative):
        if (not isinstance(relative, str) or not relative or '\\' in relative or ':' in relative
                or any(ord(c) < 32 for c in relative) or any(p in {'', '.', '..'} for p in relative.split('/'))):
            self._error('Invalid project file path.')
        current = self.root
        for part in relative.split('/'):
            current /= part
            if current.is_symlink():
                self._error('Symbolic links cannot be moved or used as trash locations: ' + relative)
        if not current.resolve().is_relative_to(self.root):
            self._error('The file must remain inside this project.')
        return current

    def _source(self, relative):
        if not isinstance(relative, str) or relative.split('/')[0] not in {'assets', 'art_source'}:
            self._error('Only original files inside assets or art_source can be moved to Trash.')
        if any(p in SKIP or p.startswith('.') for p in relative.split('/')):
            self._error('Generated, private and hidden project files cannot be moved to Trash.')
        return self._safe(relative)

    def _base(self):
        return self._safe(TRASH)

    def _txdir(self, identifier):
        if not isinstance(identifier, str) or not re.fullmatch(r'[0-9a-f]{32}', identifier):
            self._error('Invalid trash transaction.')
        return self._safe(TRASH + '/' + identifier)

    def _journal(self, record):
        directory = self._txdir(record['id'])
        directory.mkdir(parents=True, exist_ok=True)
        self.store._atomic_replace(directory / 'journal.json', _encoded(record))
        self._sync(directory)

    @staticmethod
    def _sync(directory):
        handle = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(handle)
        finally:
            os.close(handle)

    def _records(self):
        base = self._base()
        if not base.exists():
            return []
        records = []
        for directory in sorted(base.iterdir()):
            if not re.fullmatch(r'[0-9a-f]{32}', directory.name):
                continue
            path = self._txdir(directory.name) / 'journal.json'
            self._safe(path.relative_to(self.root).as_posix())
            if not path.is_file():
                continue
            try:
                record = json.loads(path.read_text(encoding='utf-8'))
                if (record.get('version') != 1 or record.get('id') != directory.name
                        or not {'version', 'id', 'created_at', 'phase', 'tracking_revision', 'items'}.issubset(record)
                        or set(record) - {'version', 'id', 'created_at', 'phase', 'tracking_revision', 'items', 'restored_at'}
                        or not isinstance(record.get('created_at'), str)
                        or type(record.get('tracking_revision')) is not int or record['tracking_revision'] < 0
                        or not isinstance(record.get('items'), list)
                        or not 1 <= len(record['items']) <= 2000
                        or record.get('phase') not in {'moving', 'committed', 'restoring', 'restored', 'rolled_back'}):
                    raise ValueError('Invalid journal fields')
                seen = set()
                fields = {'id', 'title', 'path', 'kind', 'effect', 'bytes', 'affected_clips', 'affected_packs', 'warnings'}
                for item in record['items']:
                    if not isinstance(item, dict) or item.get('kind') not in {'file', 'virtual'}:
                        raise ValueError('Invalid journal item kind')
                    if set(item) != fields | ({'fingerprint'} if item['kind'] == 'file' else set()):
                        raise ValueError('Invalid journal item fields')
                    if (any(not isinstance(item[key], str) or any(ord(c) < 32 for c in item[key]) for key in ('id', 'title', 'path', 'effect'))
                            or not item['id'].startswith('art:') or len(item['id']) > 200 or item['id'] in seen
                            or type(item['bytes']) is not int or item['bytes'] < 0):
                        raise ValueError('Invalid journal item identity')
                    seen.add(item['id'])
                    for key in ('affected_clips', 'affected_packs', 'warnings'):
                        if not isinstance(item[key], list) or any(not isinstance(v, str) for v in item[key]):
                            raise ValueError('Invalid journal item references')
                    if item['kind'] == 'file':
                        self._source(item['path'])
                        fingerprint = item['fingerprint']
                        if (not isinstance(fingerprint, dict) or set(fingerprint) != {'size', 'sha256', 'device', 'inode', 'mtime_ns'}
                                or any(type(fingerprint[key]) is not int or fingerprint[key] < 0 for key in ('size', 'device', 'inode', 'mtime_ns'))
                                or not isinstance(fingerprint['sha256'], str) or not re.fullmatch(r'[0-9a-f]{64}', fingerprint['sha256'])
                                or fingerprint['size'] != item['bytes']):
                            raise ValueError('Invalid journal file fingerprint')
                records.append(record)
            except (OSError, ValueError, TypeError, AttributeError, KeyError, ScrapError) as error:
                self._error('A trash recovery journal cannot be read. Restore it before changing files.', 'storage', 503)
        return records

    def _snapshot(self, path):
        info = path.stat()
        if not stat.S_ISREG(info.st_mode):
            self._error('Only regular files can be moved to Trash.')
        digest = hashlib.sha256()
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        after = path.stat()
        if (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns) != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
            self._error('A selected file changed while it was being checked. Review the selection again.', 'conflict', 409)
        return dict(size=info.st_size, sha256=digest.hexdigest(), device=info.st_dev, inode=info.st_ino, mtime_ns=info.st_mtime_ns)

    def _payload(self, payload, keys):
        if not isinstance(payload, dict) or set(payload) != set(keys):
            self._error('Invalid trash request fields.')
        if type(payload['version']) is not int or payload['version'] != VERSION:
            self._error('Reload this tracker before changing Scrap.', 'reload_required', 409)
        if type(payload['revision']) is not int or payload['revision'] < 0:
            self._error('Invalid tracking revision.')
        state, raw = self.store._read()
        if payload['revision'] != state['revision']:
            self._error('The tracker changed elsewhere. Reload and review the selection again.', 'conflict', 409, state)
        return state, raw

    def _catalog(self):
        hook = getattr(self.store, 'pack_catalog_locked', None)
        if hook is not None:
            try:
                return hook()
            except Exception as error:
                self._error('The current pack catalog cannot be checked safely. Restore pack records before moving files: ' + str(error), 'storage', 503)
        try:
            raw = (self.root / 'docs/tracker/catalog.json').read_bytes()
            catalog = json.loads(raw)
            if not isinstance(catalog, dict) or not isinstance(catalog.get('art'), list):
                raise ValueError
            return catalog, hashlib.sha256(raw).hexdigest()
        except (OSError, ValueError, TypeError):
            self._error('The current Art Book catalog is unavailable. Rebuild it before moving files.', 'storage', 503)

    def _references(self, paths):
        """Known textual references only; never claim a complete dependency graph."""
        result = {path: {'runtime': [], 'documents': []} for path in paths}
        if not paths:
            return result
        for directory, dirs, names in os.walk(self.root, followlinks=False):
            directory = Path(directory)
            dirs[:] = [d for d in dirs if d not in SKIP and not (directory / d).is_symlink()
                       and (directory / d) != self.root / 'docs/tracker']
            for name in names:
                file = directory / name
                if file.is_symlink() or file.suffix.lower() not in {'.gd', '.tscn', '.tres', '.godot', '.gdshader', '.html', '.md', '.css', '.js'}:
                    continue
                relative = file.relative_to(self.root).as_posix()
                try:
                    content = file.read_text(encoding='utf-8', errors='replace')
                except OSError:
                    self._error('A project reference could not be checked: ' + relative, 'storage', 503)
                for path in paths:
                    if relative == path:
                        continue
                    if re.search(r'["\']res://' + re.escape(path) + r'["\']', content):
                        result[path]['runtime'].append(relative)
                    elif path in content or ('/' in path and Path(path).name in content):
                        result[path]['documents'].append(relative)
        return result

    def _selection(self, ids, state):
        if (not isinstance(ids, list) or not ids or len(ids) > 2000 or any(not isinstance(i, str) for i in ids)
                or len(set(ids)) != len(ids)):
            self._error('Select a nonempty list of unique Art Book items.')
        catalog, fingerprint = self._catalog()
        files = {e['id']: e for e in catalog['art']}
        virtual = {e['id']: e for key in ('packs', 'animation_clips', 'animation_categories') for e in catalog.get(key, [])}
        hidden = set(self._summary()['hidden_ids'])
        hidden.update(c['id'] for c in catalog.get('animation_clips', []) if c.get('parent_id') in hidden)
        protected = set()
        for feature in catalog.get('features', []):
            protected.update(p for p in feature.get('sources', []) if isinstance(p, str))
            checks = [*feature.get('checklist', []), *state['items'].get(feature['id'], {}).get('checklist', [])]
            protected.update(c['source'] for c in checks if c.get('source'))
        for pack in catalog.get('packs', []):
            protected.update(p for p in pack.get('sources', []) if isinstance(p, str))
        prepared = []
        for identifier in ids:
            entry = files.get(identifier) or virtual.get(identifier)
            if not identifier.startswith('art:') or entry is None:
                self._error('Only existing Art Book entries can be moved to Trash.')
            if identifier in hidden:
                self._error('This item is already in Trash: ' + entry.get('title', identifier))
            if state['items'].get(identifier, {}).get('review_label') != 'Scrap':
                self._error('Every selected item must first be saved with the Scrap label.')
            item = dict(id=identifier, title=entry.get('title', identifier), path=entry.get('path', ''),
                        kind='virtual', effect='Catalog entry only; source files retained', bytes=0,
                        affected_clips=[], affected_packs=[], warnings=[])
            if identifier in files:
                path = entry.get('path', '')
                source = self._source(path)
                if path in protected:
                    self._error('This file is required as project or pack evidence and cannot be moved: ' + path)
                if not source.is_file():
                    self._error('The original file is missing: ' + path)
                clips = [e for e in catalog.get('animation_clips', []) if e.get('parent_id') == identifier]
                packs = [e for e in catalog.get('packs', []) if identifier in e.get('members', [])]
                approved = [e for e in [*clips, *packs] if state['items'].get(e['id'], {}).get('review_label') == 'Approved']
                if approved:
                    self._error('This file supports Approved work: ' + ', '.join(e.get('title', e['id']) for e in approved))
                snapshot = self._snapshot(source)
                item.update(kind='file', effect='Move this original file to recoverable project Trash', bytes=snapshot['size'],
                            fingerprint=snapshot, affected_clips=[e['id'] for e in clips], affected_packs=[e['id'] for e in packs])
            prepared.append(item)
        references = self._references([item['path'] for item in prepared if item['kind'] == 'file'])
        for item in prepared:
            if item['kind'] != 'file':
                continue
            refs = references[item['path']]
            if refs['runtime']:
                self._error('This file is referenced by Godot project resources and cannot be moved: ' + item['path'] + ' (' + ', '.join(refs['runtime'][:5]) + ')')
            item['warnings'] = ['Referenced in ' + path for path in refs['documents']]
        return prepared, fingerprint

    def prepare(self, payload):
        with self.store.lock:
            self._recover()
            state, _ = self._payload(payload, ('version', 'revision', 'ids'))
            items, catalog = self._selection(payload['ids'], state)
            self.pending = {key: value for key, value in self.pending.items() if value['expires'] > time.time()}
            token = secrets.token_hex(24)
            self.pending[token] = dict(ids=list(payload['ids']), items=items, catalog=catalog, journal=self._journal_fingerprint(), revision=state['revision'], expires=time.time() + 600)
            return dict(token=token, revision=state['revision'], expires_at=datetime.fromtimestamp(self.pending[token]['expires'], timezone.utc).isoformat(), items=deepcopy(items))

    def _move(self, source, target):
        if target.exists() or target.is_symlink():
            self._error('A destination already exists; no file was overwritten.', 'conflict', 409)
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            _rename_noreplace(source, target)
        except FileExistsError:
            self._error('A destination appeared during the move; no file was overwritten.', 'conflict', 409)
        self._sync(source.parent)
        self._sync(target.parent)

    def _file_pairs(self, record):
        return [(self._source(item['path']), self._safe(TRASH + '/' + record['id'] + '/files/' + item['path']))
                for item in record['items'] if item['kind'] == 'file']

    def _rollback(self, record, restoring=False):
        for original, trashed in reversed(self._file_pairs(record)):
            source, target = (original, trashed) if restoring else (trashed, original)
            if source.exists():
                self._move(source, target)
        record['phase'] = 'committed' if restoring else 'rolled_back'
        self._journal(record)

    def _recover(self):
        """An unfinished operation rolls back; only committed journals hide IDs."""
        for record in self._records():
            phase = record['phase']
            if phase in {'committed', 'restored', 'rolled_back'}:
                continue
            try:
                self._rollback(record, phase == 'restoring')
            except (OSError, ScrapError) as error:
                self._error('Trash recovery could not finish safely: ' + str(error), 'storage', 503)

    def delete(self, payload):
        with self.store.lock:
            self._recover()
            state, _ = self._payload(payload, ('version', 'revision', 'token', 'confirmed'))
            if payload['confirmed'] is not True or not isinstance(payload['token'], str):
                self._error('Explicit confirmation of the reviewed selection is required.')
            plan = self.pending.get(payload['token'])
            if not plan or plan['expires'] <= time.time():
                self._error('This confirmation expired. Review the selection again.', 'conflict', 409)
            items, catalog = self._selection(plan['ids'], state)
            if state['revision'] != plan['revision'] or catalog != plan['catalog'] or items != plan['items'] or self._journal_fingerprint() != plan['journal']:
                self._error('The selected files or labels changed. Review the selection again.', 'conflict', 409)
            record = dict(version=1, id=secrets.token_hex(16), created_at=_now(), phase='moving',
                          tracking_revision=state['revision'], items=items)
            try:
                self._journal(record)
                for original, trashed in self._file_pairs(record):
                    self._move(original, trashed)
                record['phase'] = 'committed'
                self._journal(record)
            except (OSError, ScrapError) as error:
                try:
                    self._rollback(record)
                except (OSError, ScrapError):
                    self._error('The move failed and recovery is pending. No existing file will be overwritten.', 'storage', 503)
                self._error('Nothing was moved to Trash; the operation was rolled back. ' + str(error), 'storage', 503)
            del self.pending[payload['token']]
            return dict(state=state, trash=self._summary(), transaction_id=record['id'])

    def restore(self, payload):
        with self.store.lock:
            self._recover()
            state, _ = self._payload(payload, ('version', 'revision', 'transaction_id'))
            self._txdir(payload['transaction_id'])
            record = next((r for r in self._records() if r['id'] == payload['transaction_id'] and r['phase'] == 'committed'), None)
            if record is None:
                self._error('This Trash transaction is unavailable or already restored.')
            pairs = self._file_pairs(record)
            for (original, trashed), item in zip(pairs, (i for i in record['items'] if i['kind'] == 'file')):
                if original.exists() or original.is_symlink():
                    self._error('Restore would overwrite an existing file: ' + item['path'], 'conflict', 409)
                if not trashed.is_file() or self._snapshot(trashed)['sha256'] != item['fingerprint']['sha256']:
                    self._error('A trashed file is missing or changed: ' + item['path'], 'storage', 503)
            record.update(phase='restoring', tracking_revision=state['revision'])
            try:
                self._journal(record)
                for original, trashed in pairs:
                    self._move(trashed, original)
                # Review labels remain Scrap; restoration never grants approval.
                record['phase'] = 'restored'
                record['restored_at'] = _now()
                self._journal(record)
            except (OSError, ScrapError) as error:
                try:
                    self._rollback(record, restoring=True)
                except (OSError, ScrapError):
                    self._error('Restore failed and recovery is pending. No existing file will be overwritten.', 'storage', 503)
                self._error('Restore did not finish; reload to recover safely. ' + str(error), 'storage', 503)
            return dict(state=state, trash=self._summary(), transaction_id=record['id'])

    def _summary(self):
        records = [r for r in self._records() if r['phase'] == 'committed']
        transactions = [dict(id=r['id'], moved_at=r['created_at'], items=[{k: deepcopy(v) for k, v in i.items() if k != 'fingerprint'} for i in r['items']]) for r in records]
        return dict(transactions=transactions, hidden_ids=sorted({i['id'] for r in records for i in r['items']}))

    def _journal_fingerprint(self):
        return hashlib.sha256(_encoded(self._records())).hexdigest()

    def trash_locked(self):
        """For service reads/updates already holding tracking_store.lock."""
        self._recover()
        return self._summary()

    def assert_editable_locked(self, ids):
        hidden = set(self.trash_locked()['hidden_ids'])
        if hidden:
            catalog, _ = self._catalog()
            hidden.update(c['id'] for c in catalog.get('animation_clips', []) if c.get('parent_id') in hidden)
        if hidden.intersection(ids):
            self._error('Restore this item from Trash before editing its labels or notes.', 'conflict', 409)

    def trash(self):
        with self.store.lock:
            self._recover()
            return self._summary()
