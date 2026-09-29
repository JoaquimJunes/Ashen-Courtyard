"""Stable Art Book identities across explicitly recorded project-file renames."""
from functools import lru_cache
import hashlib
import json
from pathlib import Path, PurePosixPath
import re

REGISTRY = 'tools/art_asset_identities.json'


def legacy_id(path):
    return 'art:' + hashlib.sha256(path.encode('utf-8')).hexdigest()[:24]


def safe_path(path):
    if (not isinstance(path, str) or not path or '\\' in path or ':' in path
            or PurePosixPath(path).is_absolute() or any(part in ('', '.', '..') for part in path.split('/'))
            or any(ord(c) < 32 for c in path)):
        raise ValueError('Identity paths must be safe project-relative POSIX paths.')
    return path


def validate_registry(data):
    if not isinstance(data, dict) or set(data) != {'version', 'entries'} or type(data['version']) is not int or data['version'] != 1:
        raise ValueError('Expected asset identity registry version 1.')
    if not isinstance(data['entries'], list) or len(data['entries']) > 20000:
        raise ValueError('Identity registry must contain at most 20,000 entries.')
    ids, paths = set(), {}
    for entry in data['entries']:
        if not isinstance(entry, dict) or set(entry) != {'id', 'original_path', 'path', 'aliases', 'source_sha256'}:
            raise ValueError('Invalid asset identity fields.')
        identifier = entry['id']
        if not isinstance(identifier, str) or not re.fullmatch(r'art:[0-9a-f]{24}', identifier) or identifier in ids:
            raise ValueError('Asset identities must be unique legacy Art Book IDs.')
        ids.add(identifier)
        if not isinstance(entry['source_sha256'], str) or not re.fullmatch(r'[0-9a-f]{64}', entry['source_sha256']):
            raise ValueError('A complete source SHA-256 is required for every identity.')
        aliases = entry['aliases']
        if not isinstance(aliases, list) or any(not isinstance(a, str) for a in aliases) or len(set(aliases)) != len(aliases):
            raise ValueError('Identity aliases must be unique paths.')
        for path in [entry['original_path'], entry['path'], *aliases]:
            safe_path(path)
            if path in paths and paths[path] != identifier:
                raise ValueError('A path is assigned to different asset identities: ' + path)
            paths[path] = identifier
    return data


@lru_cache(maxsize=16)
def _load(path, modified, size):
    data = json.loads(Path(path).read_text(encoding='utf-8'))
    return validate_registry(data)


def load_identities(root):
    path = Path(root) / REGISTRY
    if not path.exists():
        return {'version': 1, 'entries': []}
    if path.is_symlink():
        raise ValueError('Asset identity registry must not be a symbolic link.')
    info = path.stat()
    return _load(str(path.resolve()), info.st_mtime_ns, info.st_size)


def _entry(root, path, registry=None):
    registry = load_identities(root) if registry is None else registry
    for entry in registry['entries']:
        if path in [entry['original_path'], entry['path'], *entry['aliases']]:
            return entry
    return None


def identity_for_path(root, path, registry=None):
    entry = _entry(root, path, registry)
    return entry['id'] if entry else legacy_id(path)


def original_path_for(root, path, registry=None):
    entry = _entry(root, path, registry)
    return entry['original_path'] if entry else path


def canonical_path(root, path, registry=None):
    entry = _entry(root, path, registry)
    return entry['path'] if entry else path


def aliases_for(root, path, registry=None):
    entry = _entry(root, path, registry)
    return list(dict.fromkeys([entry['original_path'], *entry['aliases']])) if entry else []
