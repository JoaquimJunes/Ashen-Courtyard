#!/usr/bin/env python3
"""Build the tracker catalog without changing project tracking metadata."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import tempfile
from urllib.parse import quote

from art_catalog_metadata import ArtMetadata, IMAGES, VIDEOS
from art_preview_metadata import PreviewMetadata
from art_image_packs import build_packs
from art_animation_catalog import build_animation_catalog
from art_thumbnail_metadata import apply_thumbnail_metadata
from dev_book_catalog import apply_dev_metadata
from art_pack_edits import effective_catalog, empty_edits
from art_asset_identity import load_identities, identity_for_path, canonical_path, original_path_for, aliases_for

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/tracker'
MODELS = {'.blend', '.glb', '.gltf', '.obj', '.fbx'}
SKIP = {'node_modules', 'vendor', '.artifacts', 'artifacts', '__pycache__',
        '.git', '.godot', '.cache', 'cache', '.pytest_cache'}
TOPICS = {
    'Character architecture': 'Character architecture',
    'Character resources': 'Resources',
    'Items and equipment': 'Items',
    'Presentation': 'Animation',
    'Combat sensing': 'Combat',
    'Camera and controls': 'Camera & controls',
    'Interface': 'Interface',
    'Development tools': 'Development tools',
    'Performance': 'Performance',
    'World and persistence': 'World & persistence',
    'World simulation': 'World simulation',
    'Adventure content': 'Progression',
    'Ground movement': 'Movement',
    'Dodging': 'Movement',
    'Air movement': 'Movement',
    'Reactions': 'Movement',
    'Ledge traversal': 'Movement',
    'Posture': 'Movement',
    'Water movement': 'Movement',
    'Climbing': 'Movement',
    'Object interaction': 'Interaction',
    'Combat': 'Combat',
    'Magic': 'Magic',
}


def project_path(root, relative):
    """Accept portable project-relative paths, never outside-project sources."""
    path = PurePosixPath(relative)
    if path.is_absolute() or '..' in path.parts or '\\' in relative or not path.parts:
        raise ValueError(f'Invalid project-relative path: {relative!r}')
    target = root / path
    if not target.resolve().is_relative_to(root.resolve()):
        raise ValueError(f'Path leaves project: {relative!r}')
    return target


def art_id(relative):
    return 'art:' + hashlib.sha256(relative.encode('utf-8')).hexdigest()[:24]


def previous_catalog(out):
    """Read the previous build; data.js supports migration from the original book."""
    catalog = out / 'catalog.json'
    if catalog.exists():
        data = json.loads(catalog.read_text(encoding='utf-8'))
    elif (out / 'data.js').exists():
        text = (out / 'data.js').read_text(encoding='utf-8').strip()
        prefix = 'window.TRACKER_DATA = '
        if not text.startswith(prefix) or not text.endswith(';'):
            raise ValueError('Cannot safely parse the previous tracker data.js')
        data = json.loads(text[len(prefix):-1])
    else:
        data = {'art': []}
    if not isinstance(data, dict) or not isinstance(data.get('art', []), list):
        raise ValueError('Previous tracker catalog has an invalid art collection')
    return data


def load_features(root, out):
    features = json.loads((out / 'features.json').read_text(encoding='utf-8'))
    seed_path = out / 'checklist_seeds.json'
    seeds = json.loads(seed_path.read_text(encoding='utf-8')) if seed_path.exists() else {}
    ids = set()
    checklist_ids = set()
    result = []
    for original in features:
        item = dict(original)
        if item['id'] in ids:
            raise ValueError(f'Duplicate feature ID: {item["id"]}')
        ids.add(item['id'])
        if item['status'] not in {'Implemented', 'Partial', 'Planned'}:
            raise ValueError(f'Invalid implementation status: {item["id"]}')
        if not item['sources'] or not all(project_path(root, p).is_file() for p in item['sources']):
            raise ValueError(f'Missing feature source: {item["id"]}')
        item['area'] = ('UI' if item['subcategory'] == 'Interface' else
                        'Systems' if item['category'] == 'Game systems' else 'Gameplay')
        item['topic'] = 'Items' if item['id'] == 'healing-items' else TOPICS.get(item['subcategory'], item['subcategory'])
        item['checklist'] = []
        for original_seed in seeds.get(item['id'], []):
            seed = dict(original_seed)
            if set(seed) != {'id', 'text', 'done', 'source'} or seed['done'] is not False:
                raise ValueError(f'Invalid acceptance seed: {item["id"]}')
            if not seed['id'] or seed['id'] in checklist_ids or not seed['text'].strip():
                raise ValueError(f'Duplicate or empty acceptance seed: {item["id"]}')
            source = project_path(root, seed['source'])
            if not source.is_file() or source.suffix != '.md':
                raise ValueError(f'Missing acceptance document: {seed["source"]}')
            # Seeds quote recorded criteria. This guards against accidentally
            # inventing a requirement or silently retaining an obsolete quote.
            if ' '.join(seed['text'].split()) not in ' '.join(source.read_text(encoding='utf-8').split()):
                raise ValueError(f'Acceptance text no longer matches its source: {seed["id"]}')
            checklist_ids.add(seed['id'])
            item['checklist'].append(seed)
        result.append(item)
    if set(seeds) - ids:
        raise ValueError(f'Unknown feature IDs in checklist seeds: {sorted(set(seeds) - ids)}')
    return result


def source_files(root, out):
    """Prune caches and generated tracker files before walking asset folders."""
    paths = []
    for folder in ('art_source', 'assets', 'scenes', 'docs'):
        for directory, directories, filenames in os.walk(root / folder, followlinks=False):
            directory = Path(directory)
            directories[:] = sorted(d for d in directories if d not in SKIP
                                     and not (directory / d).is_symlink()
                                     and (directory / d).resolve() != out.resolve())
            for filename in sorted(filenames):
                p = directory / filename
                if not p.is_file() or p.is_symlink() or p.parent.resolve() == out.resolve():
                    continue
                paths.append(p)
    return paths


def scan_art(root, out):
    paths = source_files(root, out)
    metadata = ArtMetadata(root, paths)
    art = []
    for p in paths:
        relative = p.relative_to(root)
        rel = relative.as_posix()
        folder = relative.parts[0]
        suffix = p.suffix.lower()
        if folder == 'docs':
            kind = 'Lore' if suffix == '.md' and any(w in p.stem.lower() for w in ('lore', 'story', 'narrative')) else None
        elif suffix in IMAGES:
            kind = 'Images'
        elif suffix in MODELS:
            kind = 'Models'
        elif suffix in VIDEOS:
            kind = 'Videos'
        elif suffix == '.tres' and metadata.is_animation_resource(p):
            kind = 'Animations'
        elif folder == 'scenes' and suffix == '.tscn' and ('lab/' in rel or p.stem in ('arena', 'dungeon_courtyard', 'movement_lab')):
            kind = 'Maps & scenes'
        elif folder == 'art_source' and suffix in {'.md', '.html'}:
            kind = 'Design documents' if suffix == '.md' else 'Interactive previews'
        else:
            kind = None
        if kind:
            art.append(dict(title=p.stem.replace('_', ' '), path=rel, kind=kind,
                            origin='Third-party library' if 'third_party' in p.parts else 'Project files',
                            image=suffix in IMAGES, url='../../' + quote(rel), **metadata.fields(p, kind)))
    # This is the existing world concept, not a claim of authored story content.
    if (root / 'DEVELOPMENT_ROADMAP.md').is_file():
        art.append(dict(title='World concept and direction', path='DEVELOPMENT_ROADMAP.md',
                        kind='Lore', origin='Project files', image=False, url='../../DEVELOPMENT_ROADMAP.md',
                        **metadata.fields(root / 'DEVELOPMENT_ROADMAP.md', 'Lore')))
    return art


def merge_art(root, scanned, previous):
    """Keep vanished entries addressable so their project notes are not orphaned."""
    by_path = {}
    identities = load_identities(root)
    for original in previous + scanned:
        old_path = original['path']
        relative = canonical_path(root, old_path, identities)
        item = dict(by_path.get(relative, {}))
        previous_id = item.get('id')
        item.update(original)
        path = project_path(root, relative)
        aliases = aliases_for(root, relative, identities)
        item['id'] = identity_for_path(root, relative, identities) if aliases else previous_id or item.get('id') or art_id(relative)
        item['path'] = relative
        item['url'] = '../../' + quote(relative)
        item['original_paths'] = list(dict.fromkeys([original_path_for(root, relative, identities),
            *aliases, *item.get('original_paths', [])]))
        item['original_names'] = list(dict.fromkeys([PurePosixPath(value).name for value in item['original_paths']]))
        item['role'] = 'Reference' if PurePosixPath(relative).parts[:2] == ('art_source', 'references') else ''
        item['missing'] = not path.is_file()
        item.setdefault('types', [item['kind']])
        item.setdefault('collections', ['UI'] if PurePosixPath(relative).parts[:2] == ('art_source', 'ui') else [])
        item.setdefault('clip_names', [])
        item.setdefault('clip_status', 'unavailable' if item['kind'] in {'Models', 'Animations'} else 'not_applicable')
        # Unknown dates on old, already-missing entries stay explicitly unknown.
        item.setdefault('modified_at', '')
        # Art files have provenance and purpose, never inferred approval/status.
        for field in ('status', 'approval', 'approved'):
            item.pop(field, None)
        by_path[relative] = item
    return [by_path[path] for path in sorted(by_path)]


def write_catalog(data, out):
    """Stage complete UTF-8 files before replacing either generated output."""
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    texts = {
        'data.js': 'window.TRACKER_DATA = ' + json.dumps(data, ensure_ascii=False) + ';\n',
        'catalog.json': json.dumps(data, ensure_ascii=False, indent=2) + '\n',
    }
    staged = []
    originals = {out / name: (out / name).read_bytes() if (out / name).exists() else None for name in texts}
    replaced = []
    try:
        for name, text in texts.items():
            fd, temporary = tempfile.mkstemp(prefix='.' + name + '.', suffix='.tmp', dir=out)
            staged.append((Path(temporary), out / name))
            with os.fdopen(fd, 'w', encoding='utf-8') as handle:
                handle.write(text)
                handle.flush()
                os.fsync(handle.fileno())
        for temporary, destination in staged:
            os.replace(temporary, destination)
            replaced.append(destination)
    except Exception:
        for destination in reversed(replaced):
            previous = originals[destination]
            if previous is None:
                destination.unlink(missing_ok=True)
                continue
            fd, recovery = tempfile.mkstemp(prefix='.' + destination.name + '.recover.', suffix='.tmp', dir=out)
            staged.append((Path(recovery), destination))
            with os.fdopen(fd, 'wb') as handle:
                handle.write(previous)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(recovery, destination)
        raise
    finally:
        for temporary, _ in staged:
            temporary.unlink(missing_ok=True)


def build(root=ROOT, out=None, *, write=True, pack_document=None):
    root = Path(root).resolve()
    out = Path(out).resolve() if out is not None else root / 'docs/tracker'
    previous = previous_catalog(out)
    features = apply_dev_metadata(load_features(root, out))
    art = merge_art(root, scan_art(root, out), previous.get('art', []))
    PreviewMetadata(root).apply(art)
    previous_packs = []
    for original in previous.get('packs', []):
        if original.get('pack_source') == 'custom' or original['id'].startswith('art:pack:user-'):
            continue
        pack = dict(original)
        for key in ('members', 'member_paths', 'cover', 'preview', 'thumbnail', 'preview_member'):
            if 'base_' + key in pack:
                pack[key] = pack['base_' + key]
        previous_packs.append(pack)
    art, packs = build_packs(root, art, previous_packs)
    animation_clips, animation_categories, animation_taxonomy = build_animation_catalog(root, art, previous.get('animation_clips', []))
    data = dict(features=features, art=art, packs=packs, animation_clips=animation_clips,
                animation_categories=animation_categories, animation_taxonomy=animation_taxonomy)
    apply_thumbnail_metadata(data, root)
    if pack_document is None:
        edits_path = out / 'pack_edits.json'
        pack_document = json.loads(edits_path.read_text(encoding='utf-8')) if edits_path.exists() else empty_edits()
    data = effective_catalog(data, pack_document)
    if write:
        write_catalog(data, out)
        print(f'Tracker: {len(features)} features, {len(art)} art entries ({sum(a["missing"] for a in art)} missing)')
    return data


if __name__ == '__main__':
    build()
