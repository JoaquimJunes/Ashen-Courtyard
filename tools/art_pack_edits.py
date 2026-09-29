"""Pure image-pack projections and review-only suggestions; never modify assets."""
from copy import deepcopy
import hashlib
from pathlib import PurePosixPath
import re

from art_image_packs import pack_record


def empty_edits():
    return dict(version=1, revision=0, custom_packs=[], excluded_members={}, history=[])


def _unique(values):
    return list(dict.fromkeys(values))


def _missing_record(member_id, path=''):
    return dict(id=member_id, path=path, title=PurePosixPath(path).stem or 'Missing image',
        kind='Images', types=['Images'], collections=[], origin='Project files', role='',
        image=True, url='', missing=True, modified_at='', clip_names=[], clip_status='not_applicable')


def effective_catalog(catalog, edits=None):
    """Apply saved membership without changing catalog or tracking annotations.

    Documented packs retain their original membership separately so projecting an
    already projected catalog is safe. Custom pack membership comes from edits.
    Empty packs keep their identity and remain addressable for notes/history.
    """
    result = deepcopy(catalog)
    edits = edits if edits is not None else empty_edits()
    entries = result.setdefault('art', [])
    by_id = {item['id']: item for item in entries}
    old_packs = {pack['id']: pack for pack in result.get('packs', [])}
    packs = []
    specifications = []
    for old in old_packs.values():
        if old.get('pack_source') == 'custom' or old['id'].startswith('art:pack:user-'):
            continue
        original = deepcopy(old)
        original.setdefault('base_members', list(old.get('members', [])))
        original.setdefault('base_member_paths', dict(old.get('member_paths', {})))
        original.setdefault('base_cover', old.get('cover', ''))
        for key in ('preview', 'thumbnail', 'preview_member'):
            if 'base_' + key not in original and key in old:
                original['base_' + key] = deepcopy(old[key])
        specifications.append((original, original['base_members'], 'documented'))
    for custom in edits.get('custom_packs', []):
        old = old_packs.get(custom['id'], {})
        record = dict(id=custom['id'], title=custom['title'], description='User-created image pack.',
            sources=[], member_paths=old.get('member_paths', {}), created_at=custom.get('created_at', ''))
        specifications.append((record, custom['members'], 'custom'))

    for original, declared, source in specifications:
        pack_id = original['id']
        excluded = set(edits.get('excluded_members', {}).get(pack_id, []))
        declared = _unique(declared)
        members = [member for member in declared if member not in excluded]
        paths = original.get('base_member_paths', original.get('member_paths', {}))
        for member in members:
            if member not in by_id:
                by_id[member] = _missing_record(member, paths.get(member, ''))
                entries.append(by_id[member])
        current = [by_id[member] for member in members]
        cover_id = original.get('base_cover', original.get('cover'))
        cover = next((entry for entry in current if entry['id'] == cover_id and not entry.get('missing')), None)
        cover = cover or next((entry for entry in current if not entry.get('missing')), None)
        cover = cover or (current[0] if current else None)
        if current:
            specification = dict(title=original['title'], description=original.get('description', ''),
                cover=cover['path'], sources=original.get('sources', []))
            pack = pack_record(pack_id, specification, current)
            pack.update(cover=cover['id'], url=cover.get('url', ''),
                        image=bool(cover.get('image')) and not cover.get('missing', False),
                        cover_missing=bool(cover.get('missing')))
        else:
            pack = dict(id=pack_id, title=original['title'], description=original.get('description', ''),
                kind='Image packs', types=original.get('types', ['Images']),
                collections=original.get('collections', []), origin=original.get('origin', 'Project files'),
                origins=original.get('origins', ['Project files']), role=original.get('role', ''),
                members=[], member_paths={}, cover='', image=False, cover_missing=False,
                url='', path=original.get('path', ''), sources=original.get('sources', []),
                modified_at='', missing=False, missing_count=0, missing_members=[], member_count=0,
                clip_names=[], clip_status='not_applicable')
        # Keep provenance and original previews available for a future undo,
        # while exposed playback always describes current membership.
        for key, value in original.items():
            if key.startswith('base_') or key in ('catalog_warning', 'missing_definition', 'created_at'):
                pack[key] = deepcopy(value)
        pack['pack_source'] = source
        if source == 'documented' and members == declared:
            for key in ('preview', 'thumbnail'):
                value = original.get('base_' + key)
                if value is not None and (key != 'thumbnail' or pack['cover'] == original.get('base_cover')):
                    pack[key] = deepcopy(value)
            if original.get('base_preview_member'):
                pack['preview_member'] = original['base_preview_member']
        elif original.get('base_preview', {}).get('kind') == 'sequence':
            pack['preview'] = dict(status='unavailable', kind='sequence',
                reason='Pack membership changed. Open an individual frame to play the original documented sequence.')
        packs.append(pack)
    result['packs'] = packs
    result['pack_revision'] = edits.get('revision', 0)
    return result


apply_pack_edits = effective_catalog


def _natural(value):
    return tuple((1, int(part)) if part.isdigit() else (0, part.casefold())
                 for part in re.split(r'(\d+)', value))


def suggest_packs(catalog, edits=None, hidden_ids=None):
    """Suggest ungrouped neighboring images; create nothing and infer no timing.

    Numbered names share an exact folder/prefix/suffix. Remaining same-folder
    images may form a review suggestion. Excluded members are deliberately not
    suggested again, so refresh cannot immediately undo a manual removal.
    """
    effective = effective_catalog(catalog, edits)
    unavailable = set(hidden_ids or ())
    for values in (edits or {}).get('excluded_members', {}).values():
        unavailable.update(values)
    for pack in effective.get('packs', []):
        unavailable.update(pack.get('members', []))
    folders, numbered = {}, {}
    for item in effective.get('art', []):
        if not item.get('image') or item.get('missing') or item['id'] in unavailable or not item.get('path'):
            continue
        path = PurePosixPath(item['path'])
        if len(path.parts) < 3:
            continue
        folders.setdefault(path.parent.as_posix(), []).append(item)
        match = re.fullmatch(r'(.*?)(\d+)([^\d]*)', path.stem)
        if match:
            key = (path.parent.as_posix(), match[1], match[3], path.suffix.lower())
            numbered.setdefault(key, []).append(item)
    suggestions, used = [], set()

    def append(items, reason, title):
        items = sorted(items, key=lambda entry: (_natural(entry['path']), entry['id']))
        members = [item['id'] for item in items]
        identity = '\n'.join(sorted(members))
        suggestions.append(dict(id='pack-suggestion:' + hashlib.sha256(identity.encode()).hexdigest()[:24],
            title=title, reason=reason, members=members, member_count=len(members),
            cover=members[0], path=PurePosixPath(items[0]['path']).parent.as_posix(),
            url=items[0].get('url', ''), image=True))
        used.update(members)

    for key in sorted(numbered):
        items = numbered[key]
        if len(items) < 2:
            continue
        folder, prefix, suffix, _ = key
        subject = (prefix + suffix).strip(' _-.') or PurePosixPath(folder).name
        append(items, 'Numbered filenames in the same folder; review the proposed members.',
               subject.replace('_', ' ').replace('-', ' ') + ' — numbered images')
    for folder in sorted(folders):
        items = [item for item in folders[folder] if item['id'] not in used]
        if len(items) >= 2:
            append(items, 'Images in the same folder; a shared purpose has not been assumed.',
                   PurePosixPath(folder).name.replace('_', ' ').replace('-', ' ') + ' — folder images')
    return suggestions
