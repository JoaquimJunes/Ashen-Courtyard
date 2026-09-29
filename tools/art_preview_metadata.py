"""Read-only, dependency-aware animation preview metadata for Art Book builds."""
import base64
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import struct
from urllib.parse import quote, unquote, urlsplit

from art_catalog_metadata import gltf_document, read_json, read_text, VIDEOS

VERSION = 1
PREVIEW_DIR = 'docs/tracker/previews'
MANIFEST = PREVIEW_DIR + '/manifest.json'
CONVERTERS = ('tools/export_art_previews.gd', 'tools/art_preview_metadata.py',
              'tools/prepare_art_previews.py', 'tools/art_catalog_sequences.json')


def local_path(root, relative):
    if not isinstance(relative, str) or not relative or '\\' in relative or '\x00' in relative:
        raise ValueError('Invalid local project path')
    relative = relative.removeprefix('res://')
    path = PurePosixPath(relative)
    if path.is_absolute() or '..' in path.parts:
        raise ValueError('Path must stay inside the project')
    target = root / path
    if not target.resolve().is_relative_to(root.resolve()):
        raise ValueError('Path leaves the project')
    return target


def asset_url(relative):
    return '../../' + quote(relative)


def unavailable(reason, kind='model', status='unavailable', **fields):
    return dict(status=status, kind=kind, reason=reason, **fields)


class Fingerprints:
    def __init__(self, root):
        self.root = root
        self.cache = {}

    def file(self, relative):
        path = local_path(self.root, relative)
        if relative not in self.cache:
            if path.is_file():
                digest = hashlib.sha256()
                with path.open('rb') as source:
                    for block in iter(lambda: source.read(1024 * 1024), b''):
                        digest.update(block)
                self.cache[relative] = digest.hexdigest()
            else:
                self.cache[relative] = '!missing'
        return self.cache[relative]

    def combined(self, paths):
        digest = hashlib.sha256(f'art-preview:{VERSION}\n'.encode())
        for relative in sorted(set(paths)):
            digest.update((relative + '\0' + self.file(relative) + '\n').encode())
        return digest.hexdigest()


def source_dependencies(root, source, extra=()):
    """Follow text resource/import references, including missing imports in hashes."""
    pending = [source, *extra]
    result = set()
    while pending:
        relative = pending.pop().removeprefix('res://')
        if relative in result:
            continue
        path = local_path(root, relative)
        result.add(relative)
        if path.suffix.lower() in {'.fbx', '.glb', '.gltf', '.png', '.jpg', '.jpeg', '.webp'}:
            sidecar = relative + '.import'
            if (root / sidecar).is_file() or path.suffix.lower() == '.fbx':
                pending.append(sidecar)
        if path.suffix.lower() in {'.tres', '.tscn', '.import', '.json'} and path.is_file():
            pending.extend(re.findall(r'"res://([^"\n]+)"', read_text(path)))
    return sorted(result)


def gltf_dependencies(root, path, document):
    dependencies = [path.relative_to(root).as_posix()]
    for collection in ('buffers', 'images'):
        for value in document.get(collection, []):
            uri = value.get('uri')
            if uri is None or (isinstance(uri, str) and uri.startswith('data:')):
                continue
            if not isinstance(uri, str):
                raise ValueError('Invalid asset URI')
            parsed = urlsplit(uri)
            if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment or '\\' in uri:
                raise ValueError('Preview dependencies must be project-local files')
            target = (path.parent / unquote(parsed.path)).resolve()
            if not target.is_relative_to(root.resolve()) or not target.is_file():
                raise ValueError('Missing or outside-project dependency: ' + uri)
            dependencies.append(target.relative_to(root).as_posix())
    return dependencies


def glb_buffer(path):
    with path.open('rb') as stream:
        stream.seek(12)
        while header := stream.read(8):
            length, kind = struct.unpack('<II', header)
            if kind == 0x004E4942:
                return stream.read(length)
            stream.seek(length, 1)
    raise ValueError('Missing embedded animation buffer')


def animation_times(root, path, document, accessor_index, buffers):
    accessor = document['accessors'][accessor_index]
    if accessor.get('type') != 'SCALAR' or accessor.get('componentType') != 5126 or 'sparse' in accessor:
        raise ValueError('Unsupported animation time accessor')
    view = document['bufferViews'][accessor['bufferView']]
    index = view['buffer']
    if index not in buffers:
        uri = document['buffers'][index].get('uri')
        if uri is None:
            buffers[index] = glb_buffer(path)
        elif uri.startswith('data:'):
            header, data = uri.split(',', 1)
            buffers[index] = base64.b64decode(data, validate=True) if header.endswith(';base64') else unquote(data).encode()
        else:
            buffers[index] = (path.parent / unquote(uri)).read_bytes()
    raw = buffers[index]
    offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    count = accessor['count']
    stride = view.get('byteStride', 4)
    if type(count) is not int or count < 1 or stride < 4 or offset < 0 or offset + (count - 1) * stride + 4 > len(raw):
        raise ValueError('Invalid animation time data')
    times = [struct.unpack_from('<f', raw, offset + i * stride)[0] for i in range(count)]
    if not all(math.isfinite(t) and t >= 0 for t in times) or any(a > b for a, b in zip(times, times[1:])):
        raise ValueError('Invalid animation timeline')
    return times[-1]


def direct_model(root, path, fingerprints):
    """Exact glTF animation order/name; never use sorted catalog clip names as IDs."""
    try:
        document = gltf_document(path)
        if document is None:
            raise ValueError('Unreadable glTF/GLB metadata')
        dependencies = gltf_dependencies(root, path, document)
        if not document.get('meshes'):
            raise ValueError('This animation has no model; no documented matching rig is available')
        if not document.get('animations'):
            raise ValueError('This model has no animation clips')
        buffers = {}
        clips = []
        for index, animation in enumerate(document['animations']):
            samplers = animation.get('samplers', [])
            channels = animation.get('channels', [])
            if not channels or not samplers:
                raise ValueError(f'Clip {index + 1} has no playable tracks')
            for channel in channels:
                target = channel.get('target', {})
                if channel.get('extensions') or target.get('extensions'):
                    raise ValueError(f'Clip {index + 1} uses unsupported animation extensions')
                if target.get('path') not in {'translation', 'rotation', 'scale', 'weights'} or type(target.get('node')) is not int:
                    raise ValueError(f'Clip {index + 1} contains unsupported animation targets')
                if not 0 <= target['node'] < len(document.get('nodes', [])):
                    raise ValueError(f'Clip {index + 1} targets a missing node')
            if any(sampler.get('interpolation', 'LINEAR') not in {'LINEAR', 'STEP', 'CUBICSPLINE'} for sampler in samplers):
                raise ValueError(f'Clip {index + 1} uses unsupported interpolation')
            sampler_indices = [channel.get('sampler') for channel in channels]
            if any(type(index) is not int or not 0 <= index < len(samplers) for index in sampler_indices):
                raise ValueError(f'Clip {index + 1} uses a missing animation sampler')
            duration = max(animation_times(root, path, document, samplers[sampler_index]['input'], buffers) for sampler_index in sampler_indices)
            # Empty source names remain empty: index is the stable playback identity.
            clips.append(dict(id=f'gltf:{index}', index=index, name=animation.get('name', ''), duration=duration, loop=False))
        relative = path.relative_to(root).as_posix()
        return dict(status='ready', kind='model', url=asset_url(relative), model=path.stem,
                    model_path=relative, fingerprint=fingerprints.combined(dependencies), clips=clips)
    except (ValueError, OSError, KeyError, IndexError, TypeError, struct.error) as error:
        return unavailable(str(error))


class PreviewMetadata:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.fingerprints = Fingerprints(self.root)
        manifest = read_json(self.root / MANIFEST) or {}
        if not isinstance(manifest, dict):
            manifest = {}
        self.prepared = manifest.get('entries', {}) if manifest.get('version') == VERSION else {}
        self.sequences = manifest.get('sequences', {})
        if not isinstance(self.prepared, dict):
            self.prepared = {}
        if not isinstance(self.sequences, dict):
            self.sequences = {}
        self.resolved_sequences = {}
        self.sequence_members = {}
        for entry in read_json(self.root / 'tools/art_catalog_sequences.json') or []:
            preview = entry.get('preview')
            if not preview or not all(item.get('contains', '') in read_text(local_path(self.root, item['path'])) for item in entry.get('evidence', [])):
                continue
            sequence = preview.get('sequence')
            if sequence:
                for path in self.root.glob(entry['pattern']):
                    if path.is_file():
                        self.sequence_members[path.relative_to(self.root).as_posix()] = preview
            elif preview.get('kind') == 'video':
                for path in self.root.glob(entry['pattern']):
                    self.sequence_members[path.relative_to(self.root).as_posix()] = preview

    def prepared_descriptor(self, relative):
        stored = self.prepared.get(relative)
        sequence_id = (stored.get('sequence') if isinstance(stored, dict) else None) or self.sequence_members.get(relative, {}).get('sequence')
        if sequence_id:
            if sequence_id not in self.resolved_sequences:
                record = self.sequences.get(sequence_id)
                self.resolved_sequences[sequence_id] = self.verify_record(record) if record else unavailable('Sequence preview is missing. Rebuild it.', 'sequence', 'stale')
            descriptor = dict(self.resolved_sequences[sequence_id])
            # Identity is catalog information, even when playback is unavailable.
            # Keeping it prevents one damaged sequence becoming hundreds of rows.
            descriptor['kind'] = 'sequence'
            descriptor['sequence'] = dict(descriptor.get('sequence', {}), id=sequence_id,
                                          start_frame=(stored or {}).get('start_frame', 0))
            return descriptor
        if not isinstance(stored, dict) or not stored:
            return unavailable('Preview has not been prepared. Run the preview preparation tool.')
        return self.verify_record(stored)

    def verify_record(self, stored):
        if not isinstance(stored, dict) or not isinstance(stored.get('descriptor'), dict):
            return unavailable('Invalid preview preparation record. Rebuild this preview.', status='stale')
        descriptor = dict(stored['descriptor'])
        try:
            current = self.fingerprints.combined(stored['dependencies'])
            if current != stored.get('fingerprint'):
                return unavailable('The source or converter changed. Rebuild this preview.', descriptor.get('kind', 'model'), 'stale')
            if descriptor.get('status') == 'ready' and stored.get('output'):
                if self.fingerprints.file(stored['output']) != stored.get('output_sha256'):
                    return unavailable('The prepared preview is missing or changed. Rebuild it.', descriptor['kind'], 'stale')
        except (ValueError, OSError, KeyError, TypeError):
            return unavailable('Invalid preview preparation record. Rebuild this preview.', status='stale')
        return descriptor

    def descriptor(self, entry):
        relative = entry['path']
        path = local_path(self.root, relative)
        if not path.is_file():
            stored = self.prepared.get(relative, {})
            previous = entry.get('preview', {})
            if isinstance(stored, dict) and stored.get('sequence'):
                previous = self.prepared_descriptor(relative)
            fields = {'sequence': previous['sequence']} if previous.get('kind') == 'sequence' and previous.get('sequence') else {}
            return unavailable('The original asset is missing', previous.get('kind', 'video' if path.suffix.lower() in VIDEOS else 'model'), **fields)
        if relative in self.sequence_members:
            return self.prepared_descriptor(relative)
        if path.suffix.lower() in {'.glb', '.gltf'}:
            return direct_model(self.root, path, self.fingerprints)
        if path.suffix.lower() in VIDEOS:
            return dict(status='ready', kind='video', url=asset_url(relative), model='', model_path='',
                        fingerprint=self.fingerprints.combined([relative]), clips=[])
        if path.suffix.lower() == '.fbx':
            mapped = re.search(r'^path\s*=\s*"(res://[^"]+)"', read_text(Path(str(path) + '.import')), re.M)
            try:
                imported = local_path(self.root, mapped.group(1)) if mapped else None
            except ValueError:
                imported = None
            if imported is None or not imported.is_file():
                return unavailable('The existing Godot FBX import is missing. Import the source in Godot, then prepare its preview.')
            return self.prepared_descriptor(relative)
        if path.suffix.lower() == '.tres':
            return self.prepared_descriptor(relative)
        if path.suffix.lower() == '.blend':
            return unavailable('Blender authoring files require an exported GLB for browser preview.')
        return unavailable('This source format has no prepared animation preview')

    def apply(self, entries):
        for entry in entries:
            if ('Animations' in entry.get('types', []) or entry.get('kind') == 'Videos'
                    or ('Models' in entry.get('types', []) and entry.get('clip_status') == 'unavailable')):
                entry['preview'] = self.descriptor(entry)
                # Preserve the previously reviewed authored crawl as a distinct version.
                crawl_versions = {
                    'art_source/mixamo/anim_ual_crawl_retarget_reviewed_v01.glb': ('authored_crawl', 'Previously reviewed crawl retarget · authoring version'),
                    'assets/animations/ual/anim_ual_mixamo_crawling_library_v01.tres': ('corrected_crawl', 'Corrected crawl retarget · attached_shoulders_v1'),
                }
                if entry['path'] in crawl_versions:
                    kind, label = crawl_versions[entry['path']]
                    entry['preview']['provenance'] = dict(kind=kind, label=label,
                        source_path=entry['path'], documentation='art_source/mixamo/README.md')
            else:
                entry.pop('preview', None)
        return entries
