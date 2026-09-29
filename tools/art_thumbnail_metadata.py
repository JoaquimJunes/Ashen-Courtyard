"""Read-only thumbnail cache validation, independent of playable preview state."""
import hashlib
import json
from pathlib import Path
import struct
from urllib.parse import unquote, urlsplit

from art_catalog_metadata import read_json
from art_preview_metadata import Fingerprints, asset_url, local_path

ROOT = Path(__file__).resolve().parents[1]
VERSION = 1
WIDTH, HEIGHT = 384, 256
DIRECTORY = 'docs/tracker/previews/thumbnails'
MANIFEST = DIRECTORY + '/manifest.json'
RENDER_FILES = ('docs/tracker/preview-model.js', 'docs/tracker/preview-media.js',
                'docs/tracker/thumbnail-render.html', 'docs/tracker/thumbnail-render.js',
                'tools/capture_art_thumbnails.cjs', 'tools/art_thumbnail_metadata.py')


def project_url_path(root, url):
    parsed = urlsplit(url)
    if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment or '\\' in url:
        raise ValueError('Thumbnail sources must be local project files')
    path = (root / 'docs/tracker' / unquote(parsed.path)).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError('Thumbnail source leaves the project')
    return path.relative_to(root.resolve()).as_posix()


def renderer_fingerprint(root, fingerprints):
    vendor = root / 'docs/tracker/vendor/three'
    dependencies = [*RENDER_FILES, *(p.relative_to(root).as_posix() for p in vendor.rglob('*') if p.is_file())]
    return fingerprints.combined(dependencies)


def thumbnail_key(entry):
    preview = entry.get('preview', {})
    if entry.get('source_clip'):
        return entry['id']
    if preview.get('kind') == 'sequence':
        return 'sequence:' + str(preview.get('sequence', {}).get('id', entry['id']))
    if preview.get('kind') == 'video':
        return entry['id']
    return None


def request_for(root, entry, fingerprints, renderer):
    preview = entry.get('preview', {})
    key = thumbnail_key(entry)
    if not key or entry.get('missing') or preview.get('status') != 'ready':
        return None
    source = project_url_path(root, preview['url'])
    dependencies = [source]
    if preview['kind'] == 'sequence':
        sequence = read_json(local_path(root, source)) or {}
        if not sequence.get('frames'):
            raise ValueError('The sequence has no first frame')
        image = sequence['frames'][0]
        dependencies.append(project_url_path(root, image))
    else:
        image = None
    # Includes the prepared fingerprint AND actual bytes, so a stale catalog or
    # edited derived file cannot accidentally reuse its old picture.
    binding = dict(key=key, source=source, preview_fingerprint=preview.get('fingerprint'),
                   kind=preview['kind'], clip=entry.get('source_clip'), renderer=renderer,
                   dependencies=fingerprints.combined(dependencies), size=[WIDTH, HEIGHT], time=0)
    digest = hashlib.sha256(json.dumps(binding, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return dict(id=key, fingerprint=digest, descriptor=preview, clip=entry.get('source_clip'),
                image=image, output=f'{DIRECTORY}/{hashlib.sha256(key.encode()).hexdigest()[:20]}-{digest[:16]}.png')


def png_dimensions(path):
    with path.open('rb') as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise ValueError('Not a PNG thumbnail')
    return struct.unpack('>II', header[16:24])


def cached_thumbnail(root, request, record, fingerprints):
    if not isinstance(record, dict) or record.get('fingerprint') != request['fingerprint']:
        return None
    if record.get('status') == 'error':
        return dict(status='error', reason=record.get('reason', 'Thumbnail preparation failed.'))
    try:
        output = record['output']
        if output != request['output'] or png_dimensions(local_path(root, output)) != (WIDTH, HEIGHT):
            return None
        if fingerprints.file(output) != record.get('output_sha256'):
            return None
    except (ValueError, OSError, KeyError, TypeError):
        return None
    return dict(status='ready', url=asset_url(output), width=WIDTH, height=HEIGHT,
                time=0, empty=bool(record.get('empty')), fingerprint=request['fingerprint'])


def thumbnail_entries(catalog):
    return [*catalog.get('animation_clips', []),
            *(entry for entry in [*catalog.get('art', []), *catalog.get('packs', [])]
              if entry.get('preview', {}).get('kind') in {'sequence', 'video'})]


def apply_thumbnail_metadata(catalog, root=ROOT):
    """Attach derived metadata without changing previews, assets or annotations."""
    root = Path(root).resolve()
    manifest = read_json(root / MANIFEST) or {}
    if not isinstance(manifest, dict):
        manifest = {}
    records = manifest.get('entries', {}) if manifest.get('version') == VERSION else {}
    if not isinstance(records, dict):
        records = {}
    fingerprints = Fingerprints(root)
    renderer = renderer_fingerprint(root, fingerprints)
    for entry in thumbnail_entries(catalog):
        try:
            request = request_for(root, entry, fingerprints, renderer)
            if request is None:
                entry['thumbnail'] = dict(status='unavailable', reason=entry.get('preview', {}).get('reason', 'A prepared preview is required.'))
            else:
                entry['thumbnail'] = cached_thumbnail(root, request, records.get(request['id']), fingerprints) or dict(status='pending', reason='First-frame thumbnail has not been prepared for this version.')
        except (ValueError, OSError, KeyError, TypeError) as error:
            entry['thumbnail'] = dict(status='unavailable', reason=str(error))
    # Library cards can show their first clip; the actual clips retain distinct
    # thumbnails and original file records retain their stable identities.
    first_by_parent = {}
    for clip in catalog.get('animation_clips', []):
        first_by_parent.setdefault(clip.get('parent_id'), clip.get('thumbnail'))
    for entry in catalog.get('art', []):
        if entry['id'] in first_by_parent:
            entry['thumbnail'] = first_by_parent[entry['id']]
    return catalog
