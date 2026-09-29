#!/usr/bin/env python3
"""Review, apply, or roll back explicit animation filename changes.

Dry-run is the default. Only an explicit --apply changes project files. All
original bytes and a resumable rollback journal remain under .artifacts.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import uuid

from art_asset_identity import REGISTRY, safe_path, validate_registry
from art_scrap_store import _rename_noreplace

ROOT = Path(__file__).resolve().parents[1]
PLAN = 'tools/art_asset_identity_plan.json'
EXCLUDED = {'.git', '.godot', '.artifacts', '.codex', '.agents', '__pycache__', 'node_modules', 'vendor', 'third_party', 'graphify-out'}
TEXT = {'.gd', '.tscn', '.tres', '.godot', '.cfg', '.import', '.uid', '.py', '.cjs', '.js', '.json', '.md', '.html', '.txt', '.yaml', '.yml', '.toml', '.sh'}
GENERATED = {'docs/tracker/catalog.json', 'docs/tracker/data.js', 'docs/tracker/animation_audit.json', REGISTRY, PLAN,
             'tools/build_animation_identity_plan.py', 'tools/art_animation_naming.py',
             'tools/art_animation_catalog.py', 'tools/art_animation_classification.json',
             'tools/verify_animation_duplicates.gd', 'tools/test_animation_duplicates.py',
             'tools/test_animation_migration.py', 'tools/test_art_animation_naming.py', 'tools/test_art_animation_catalog.py'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_hash(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def local(root, relative):
    safe_path(relative)
    current = root
    for part in relative.split('/'):
        current /= part
        if current.is_symlink():
            raise ValueError('Refusing a symbolic-link path: ' + relative)
    if not current.resolve().is_relative_to(root):
        raise ValueError('Path leaves the project: ' + relative)
    return current


def atomic_write(path, data):
    temporary = None
    try:
        fd, temporary = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def encoded(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode('utf-8')


def textual_files(root, excluded_registry):
    for directory, dirs, names in os.walk(root, followlinks=False):
        directory = Path(directory)
        dirs[:] = [name for name in dirs if name not in EXCLUDED and not (directory / name).is_symlink()
                   and (directory / name) != root / 'docs/tracker/previews']
        for name in sorted(names):
            path = directory / name
            relative = path.relative_to(root).as_posix()
            if (path.is_symlink() or path.suffix.lower() not in TEXT or relative in GENERATED
                    or relative == excluded_registry or name.startswith('tracking.') or name.startswith('pack_edits.')
                    or name.endswith('.packs.json') or 'migration' in name and path.suffix == '.json'):
                continue
            yield path


def plan_migration(root, registry_path):
    root = Path(root).resolve()
    registry_path = Path(registry_path).resolve()
    registry = validate_registry(json.loads(registry_path.read_text(encoding='utf-8')))
    excluded_registry = registry_path.relative_to(root).as_posix() if registry_path.is_relative_to(root) else ''
    moves, mapping, destinations = [], {}, set()
    for entry in registry['entries']:
        old, new = entry['original_path'], entry['path']
        if old == new:
            continue
        owned = ('assets/animations/', 'art_source/mixamo/')
        if (not old.startswith(owned) or not new.startswith(owned)
                or Path(old).suffix.lower() not in {'.fbx', '.glb', '.tres'}
                or Path(old).suffix.lower() != Path(new).suffix.lower()):
            raise ValueError('Only project animation .fbx, .glb and .tres filenames may be migrated: ' + old)
        source, target = local(root, old), local(root, new)
        if not source.is_file():
            raise ValueError('Original source is missing; this migration may already be applied: ' + old)
        if target.exists() or new in destinations:
            raise ValueError('Destination already exists or is assigned twice: ' + new)
        if file_hash(source) != entry['source_sha256']:
            raise ValueError('Original source changed since naming review: ' + old)
        for suffix in ('', '.import', '.uid'):
            before, after = old + suffix, new + suffix
            path = local(root, before)
            if not path.exists():
                continue
            destination = local(root, after)
            if destination.exists() or after in destinations:
                raise ValueError('Destination already exists or is assigned twice: ' + after)
            destinations.add(after)
            moves.append(dict(source=before, destination=after, sha256=file_hash(path)))
            mapping[before] = after
    # Replace complete project paths only, simultaneously. Do not replace clip
    # names, resource IDs, bare filenames or original-path provenance records.
    from urllib.parse import quote
    replacements = dict(mapping)
    replacements.update({quote(old, safe='/'): quote(new, safe='/') for old, new in mapping.items()})
    expression = re.compile('|'.join(re.escape(path) for path in sorted(replacements, key=len, reverse=True))) if replacements else None
    edits = []
    if expression:
        for path in textual_files(root, excluded_registry):
            raw = path.read_bytes()
            try:
                before = raw.decode('utf-8')
            except UnicodeDecodeError:
                continue
            after = expression.sub(lambda match: replacements[match[0]], before)
            if before != after:
                relative = path.relative_to(root).as_posix()
                edits.append(dict(original_path=relative, path=mapping.get(relative, relative),
                                  before_hash=digest(raw), after_hash=digest(after.encode('utf-8')), content=after.encode('utf-8')))
    active = local(root, REGISTRY)
    active_bytes = active.read_bytes() if active.exists() else None
    updated_registry = encoded(registry)
    if active_bytes != updated_registry:
        edits.append(dict(original_path=REGISTRY, path=REGISTRY, before_hash=digest(active_bytes) if active_bytes is not None else None,
                          after_hash=digest(updated_registry), content=updated_registry))
    return dict(version=1, root=str(root), registry=registry, moves=moves, edits=edits)


def summary(plan):
    return dict(version=1, root=plan['root'], move_count=len(plan['moves']), reference_file_count=sum(item['path'] != REGISTRY for item in plan['edits']),
                moves=plan['moves'], edited_paths=[item['path'] for item in plan['edits']],
                notes=['Source FBX/GLB bytes are unchanged.', 'Import sidecars move with their source and retain their UIDs.',
                       'Historical tracking records, original provenance, bundled libraries and generated previews are not rewritten.',
                       'Run a Godot import and rebuild derived previews/catalogs after applying.'])


@contextmanager
def migration_lock(root):
    directory = local(root, '.artifacts/animation-naming')
    directory.mkdir(parents=True, exist_ok=True)
    lock = local(root, '.artifacts/animation-naming/migration.lock')
    with lock.open('a+b') as stream:
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def persist_journal(path, journal):
    atomic_write(path, encoded(journal))


def apply_migration(plan, journal_path=None):
    root = Path(plan['root']).resolve()
    with migration_lock(root):
        relative = journal_path or '.artifacts/animation-naming/migration-' + uuid.uuid4().hex + '/journal.json'
        path = local(root, relative)
        if not relative.startswith('.artifacts/animation-naming/') or path.exists():
            raise ValueError('Use a new journal under .artifacts/animation-naming/.')
        path.parent.mkdir(parents=True, exist_ok=False)
        backups = path.parent / 'originals'
        backups.mkdir()
        originals = {}
        for item in plan['moves']:
            source, target = local(root, item['source']), local(root, item['destination'])
            if not source.is_file() or file_hash(source) != item['sha256'] or target.exists():
                raise ValueError('Files changed after migration planning: ' + item['source'])
            originals[item['source']] = source.read_bytes()
        for item in plan['edits']:
            source = local(root, item['original_path'])
            before = source.read_bytes() if source.exists() else None
            if (digest(before) if before is not None else None) != item['before_hash']:
                raise ValueError('A reference changed after migration planning: ' + item['original_path'])
            originals[item['original_path']] = before
        backup_names = {}
        for index, (name, raw) in enumerate(sorted(originals.items())):
            if raw is not None:
                backup = backups / f'{index:05}.bin'
                atomic_write(backup, raw)
                backup_names[name] = backup.relative_to(root).as_posix()
        operations = [dict(type='move', source=item['source'], path=item['destination'], before_hash=item['sha256'], backup=backup_names.get(item['source']), applied=False)
                      for item in plan['moves']]
        operations += [dict(type='write', original_path=item['original_path'], path=item['path'], before_hash=item['before_hash'],
                            after_hash=item['after_hash'], backup=backup_names.get(item['original_path']), applied=False)
                       for item in plan['edits']]
        journal = dict(version=1, root=str(root), created_at=datetime.now(timezone.utc).isoformat(), status='prepared', operations=operations)
        persist_journal(path, journal)
        try:
            for operation in operations:
                target = local(root, operation['path'])
                target.parent.mkdir(parents=True, exist_ok=True)
                if operation['type'] == 'move':
                    source = local(root, operation['source'])
                    if file_hash(source) != operation['before_hash']:
                        raise ValueError('Source changed during migration: ' + operation['source'])
                    _rename_noreplace(source, target)
                else:
                    before = file_hash(target) if target.exists() else None
                    if before != operation['before_hash']:
                        raise ValueError('Reference changed during migration: ' + operation['path'])
                    edit = next(item for item in plan['edits'] if item['path'] == operation['path'])
                    atomic_write(target, edit['content'])
                operation['applied'] = True
                journal['status'] = 'applying'
                persist_journal(path, journal)
            journal['status'] = 'applied'
            persist_journal(path, journal)
        except Exception:
            journal['status'] = 'interrupted'
            persist_journal(path, journal)
            # Keep the journal and originals rather than hiding a partial failure.
            # Rollback first verifies every current file to avoid overwriting edits.
            _rollback(root, path, journal)
            raise
        return path


def _rollback(root, path, journal):
    if journal.get('version') != 1 or journal.get('root') != str(root) or not isinstance(journal.get('operations'), list):
        raise ValueError('Invalid migration journal.')
    operations = journal['operations']
    expected = {}
    for operation in operations:
        if operation.get('type') not in {'move', 'write'}:
            raise ValueError('Unknown journal operation.')
        target = local(root, operation['path'])
        expected.setdefault(operation['path'], set()).add(operation.get('before_hash'))
        if operation['type'] == 'write':
            expected[operation['path']].add(operation['after_hash'])
            if operation['backup']:
                backup = local(root, operation['backup'])
                if not backup.is_file() or file_hash(backup) != operation['before_hash']:
                    raise ValueError('Recovery original is missing or changed: ' + operation['path'])
    for operation in operations:
        target = local(root, operation['path'])
        if operation['type'] == 'move':
            source = local(root, operation['source'])
            if source.exists() and target.exists():
                raise ValueError('Rollback will not overwrite a restored or new file: ' + operation['source'])
            if source.exists():
                if file_hash(source) != operation['before_hash']:
                    raise ValueError('An original path changed after migration: ' + operation['source'])
            elif not target.is_file() or file_hash(target) not in expected[operation['path']]:
                raise ValueError('A migrated file changed; resolve it before rollback: ' + operation['path'])
        elif target.exists():
            if file_hash(target) not in expected[operation['path']]:
                raise ValueError('A reference changed; resolve it before rollback: ' + operation['path'])
        elif operation['before_hash'] is not None and operation['original_path'] == operation['path']:
            raise ValueError('A reference is missing; resolve it before rollback: ' + operation['path'])
    for operation in reversed(operations):
        target = local(root, operation['path'])
        if operation['type'] == 'write':
            if target.exists() and file_hash(target) == operation['after_hash']:
                if operation['backup']:
                    atomic_write(target, local(root, operation['backup']).read_bytes())
                else:
                    target.unlink()
        elif target.exists():
            source = local(root, operation['source'])
            source.parent.mkdir(parents=True, exist_ok=True)
            _rename_noreplace(target, source)
        operation['applied'] = False
    journal['status'] = 'rolled_back'
    persist_journal(path, journal)


def rollback(root, journal_path):
    root = Path(root).resolve()
    with migration_lock(root):
        path = local(root, journal_path)
        if not journal_path.startswith('.artifacts/animation-naming/'):
            raise ValueError('Only an animation migration journal may be rolled back.')
        journal = json.loads(path.read_text(encoding='utf-8'))
        _rollback(root, path, journal)
        return path


def verify_migration(root, journal_path):
    """Prove serialized animation content only changed in explicit path references."""
    root = Path(root).resolve()
    path = local(root, journal_path)
    journal = json.loads(path.read_text(encoding='utf-8'))
    if journal.get('version') != 1 or journal.get('root') != str(root) or journal.get('status') != 'applied':
        raise ValueError("Verification requires this project’s applied migration journal.")
    moves = [item for item in journal['operations'] if item['type'] == 'move']
    mapping = {item['source']: item['path'] for item in moves}
    from urllib.parse import quote
    mapping.update({quote(old, safe='/'): quote(new, safe='/') for old, new in list(mapping.items())})
    expression = re.compile('|'.join(re.escape(path) for path in sorted(mapping, key=len, reverse=True)))
    checked = {'source_files': 0, 'binary_sources_unchanged': 0, 'tres_keyframes_and_bindings_unchanged': 0, 'import_uids_preserved': 0}
    for item in moves:
        before = local(root, item['backup']).read_bytes()
        if digest(before) != item['before_hash']:
            raise ValueError('Recovery bytes changed: ' + item['source'])
        after = local(root, item['path']).read_bytes()
        extension = Path(item['path']).suffix.lower()
        if extension in {'.fbx', '.glb'}:
            if before != after:
                raise ValueError('Binary animation source changed: ' + item['path'])
            checked['binary_sources_unchanged'] += 1
            checked['source_files'] += 1
        elif extension == '.tres':
            expected = expression.sub(lambda match: mapping[match[0]], before.decode('utf-8')).encode('utf-8')
            if expected != after:
                raise ValueError('Animation contents changed beyond explicit resource paths: ' + item['path'])
            checked['tres_keyframes_and_bindings_unchanged'] += 1
            checked['source_files'] += 1
        elif extension == '.import':
            uid = lambda raw: re.findall(rb'^uid\s*=\s*(.+)$', raw, re.MULTILINE)
            if uid(before) != uid(after):
                raise ValueError('Import UID changed: ' + item['path'])
            checked['import_uids_preserved'] += 1
    return checked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--registry', type=Path, default=Path(PLAN))
    action = parser.add_mutually_exclusive_group()
    action.add_argument('--apply', action='store_true')
    action.add_argument('--rollback', metavar='JOURNAL')
    action.add_argument('--verify', metavar='JOURNAL', help='Read-only proof that animation bytes/keyframes and UIDs were preserved.')
    parser.add_argument('--journal', help='New project-relative journal path for --apply.')
    args = parser.parse_args()
    try:
        if args.verify:
            print(json.dumps(verify_migration(args.root, args.verify), indent=2))
            return
        if args.rollback:
            print('Rolled back:', rollback(args.root, args.rollback))
            return
        registry = args.registry if args.registry.is_absolute() else args.root / args.registry
        plan = plan_migration(args.root, registry)
        print(json.dumps(summary(plan), indent=2))
        if args.apply:
            print('Applied. Recovery journal:', apply_migration(plan, args.journal))
        else:
            print('Dry-run only. No source files changed; use --apply after reviewing the plan.')
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
