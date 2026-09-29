"""Source-backed image groupings; keep individual catalog IDs and notes intact."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re

from art_catalog_metadata import IMAGES, read_text
from art_preview_metadata import asset_url, local_path

MANIFEST = 'tools/art_image_packs.json'


def stable_id(path):
    return 'art:' + hashlib.sha256(path.encode()).hexdigest()[:24]


def member_paths(specification):
    numbered = specification.get('numbered_members')
    if numbered is not None:
        if 'members' in specification:
            raise ValueError('Image pack must use members or numbered_members, not both')
        start, count, digits = (numbered.get(k) for k in ('start', 'count', 'digits'))
        if any(type(v) is not int for v in (start, count, digits)) or start < 0 or not 1 <= count <= 10000 or not 1 <= digits <= 8:
            raise ValueError('Invalid image pack numbered range')
        result = [numbered['prefix'] + f'{index:0{digits}d}' + numbered['suffix'] for index in range(start, start + count)]
    else:
        result = specification.get('members', [])
    if not isinstance(result, list) or not result or not all(isinstance(p, str) for p in result) or len(set(result)) != len(result):
        raise ValueError('Image pack members must be a nonempty, unique, ordered path list')
    return result


def missing_member(relative, types):
    return dict(id=stable_id(relative), path=relative, title=Path(relative).stem.replace('_', ' '),
        kind='Images', types=types, collections=['UI'] if relative.startswith('art_source/ui/') else [],
        origin='Third-party library' if 'third_party' in Path(relative).parts else 'Project files',
        role='Reference' if relative.startswith('art_source/references/') else '', image=True,
        url=asset_url(relative), missing=True, modified_at='', clip_names=[],
        clip_status='unavailable' if 'Animations' in types else 'not_applicable')


def pack_record(pack_id, specification, members, warning=''):
    by_path = {entry['path']: entry for entry in members}
    cover = by_path.get(specification.get('cover'), members[0])
    origins = sorted({entry.get('origin', 'Project files') for entry in members})
    roles = {entry.get('role', '') for entry in members}
    sources = specification.get('sources', [])
    missing = [entry['id'] for entry in members if entry.get('missing')]
    result = dict(id=pack_id, title=specification['title'], description=specification.get('description', ''),
        kind='Image packs', types=sorted({t for entry in members for t in entry.get('types', ['Images'])}),
        collections=sorted({c for entry in members for c in entry.get('collections', [])}),
        origin=origins[0] if len(origins) == 1 else 'Mixed origins', origins=origins,
        role=next(iter(roles)) if len(roles) == 1 else '',
        members=[entry['id'] for entry in members], member_paths={entry['id']: entry['path'] for entry in members},
        cover=cover['id'], image=bool(cover.get('image')) and not cover.get('missing', False), cover_missing=bool(cover.get('missing')),
        url=cover.get('url', ''), path=sources[0] if sources else cover['path'], sources=sources,
        modified_at=max((entry.get('modified_at', '') for entry in members), default=''),
        missing=len(missing) == len(members), missing_count=len(missing), missing_members=missing,
        member_count=len(members), clip_names=[], clip_status='not_applicable')
    preview_member = by_path.get(specification.get('preview_member'))
    if preview_member:
        result['preview_member'] = preview_member['id']
        if preview_member.get('preview', {}).get('kind') == 'sequence':
            result['preview'] = deepcopy(preview_member['preview'])
            if 'sequence' in result['preview']:
                result['preview']['sequence']['start_frame'] = 0
    if warning:
        result['catalog_warning'] = warning
        result['missing_definition'] = True
    return result


def build_packs(root, art, previous=(), manifest_path=None):
    """Return original entries plus documented missing records and ordered packs."""
    root = Path(root).resolve()
    manifest_path = Path(manifest_path) if manifest_path else root / MANIFEST
    if manifest_path.is_file():
        document = json.loads(manifest_path.read_text(encoding='utf-8'))
        if not isinstance(document, dict) or document.get('version') != 1 or not isinstance(document.get('packs'), list):
            raise ValueError('Invalid image pack manifest version or packs collection')
        specifications = document['packs']
    else:
        specifications = []
    entries = list(art)
    by_path = {entry['path']: entry for entry in entries}
    previous_by_id = {entry['id']: entry for entry in previous}
    seen, declared, result = set(), set(), []
    for specification in specifications:
        key = specification.get('key', '')
        if not isinstance(key, str) or not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', key):
            raise ValueError('Image pack key must contain lowercase words separated by hyphens')
        pack_id = 'art:pack:' + key
        if pack_id in declared:
            raise ValueError('Duplicate image pack key: ' + key)
        declared.add(pack_id)
        seen.add(pack_id)
        if not isinstance(specification.get('title'), str) or not specification['title'].strip():
            raise ValueError('Image pack needs a title: ' + key)
        paths = member_paths(specification)
        for relative in paths:
            target = local_path(root, relative)
            if target.suffix.lower() not in IMAGES:
                raise ValueError('Image pack member is not an image: ' + relative)
        if specification.get('cover') not in paths:
            raise ValueError('Image pack cover must be one of its members: ' + key)
        if specification.get('preview_member') and specification['preview_member'] not in paths:
            raise ValueError('Image pack preview must be one of its members: ' + key)
        sources = specification.get('sources', [])
        evidence = specification.get('evidence', [])
        valid = bool(sources) and all(local_path(root, relative).is_file() for relative in sources)
        valid = valid and bool(evidence) and all(item.get('path') in sources and isinstance(item.get('contains'), str)
            and item['contains'] and item['contains'] in read_text(local_path(root, item['path'])) for item in evidence)
        if not valid:
            # Do not create an unsupported new grouping or erase an existing one.
            seen.remove(pack_id)
            continue
        for relative in paths:
            if relative not in by_path:
                if local_path(root, relative).is_file():
                    raise ValueError('Image pack member exists but is excluded from the art catalog: ' + relative)
                item = missing_member(relative, specification.get('member_types', ['Images']))
                by_path[relative] = item
                entries.append(item)
        result.append(pack_record(pack_id, specification, [by_path[relative] for relative in paths]))
    for pack_id, old in previous_by_id.items():
        if pack_id in seen:
            continue
        old_paths = old.get('member_paths', {})
        paths = [old_paths.get(member_id) for member_id in old.get('members', [])]
        paths = [path for path in paths if path]
        if not paths:
            preserved = deepcopy(old)
            preserved.update(catalog_warning='The pack definition or its source evidence is missing.', missing_definition=True)
            result.append(preserved)
            continue
        for relative in paths:
            local_path(root, relative)
            if relative not in by_path:
                item = missing_member(relative, ['Images'])
                # Previous pack IDs, including non-hash legacy IDs, remain stable.
                item['id'] = next(mid for mid, path in old_paths.items() if path == relative)
                entries.append(item)
                by_path[relative] = item
        specification = dict(title=old['title'], description=old.get('description', ''),
            cover=old_paths.get(old.get('cover')), sources=old.get('sources', []),
            preview_member=old_paths.get(old.get('preview_member')))
        result.append(pack_record(pack_id, specification, [by_path[path] for path in paths],
                                  'The pack definition or its source evidence is missing.'))
    return sorted(entries, key=lambda e: e['path']), result
