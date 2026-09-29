"""Conservative, build-time art metadata. Never import or modify source assets."""
from datetime import datetime, timezone
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import struct
import subprocess
import tempfile
from urllib.parse import unquote, urlsplit

IMAGES = {'.png', '.jpg', '.jpeg', '.webp', '.svg'}
VIDEOS = {'.mp4', '.webm', '.mov', '.m4v', '.ogv', '.avi', '.mkv'}
STRING = r'"(?:\\.|[^"\\])*"'
SECTIONS = re.compile(r'^\[([^\n]+)\]\s*\n', re.M)
HTML_HEAD_LIMIT = 64 * 1024
HTML_DESCRIPTION_LIMIT = 240


def html_description(path):
    """Use authored head metadata only; never render HTML or inspect frame contents."""
    class HeadMetadata(HTMLParser):
        def __init__(self):
            super().__init__(convert_charrefs=True)
            self.description = ''
            self.title = ''
            self.title_parts = None
            self.finished = False

        def handle_starttag(self, tag, attrs):
            if tag == 'body':
                self.finished = True
            if self.finished:
                return
            if tag == 'meta':
                values = dict(attrs)
                if (values.get('name') or '').lower() == 'description' and not self.description:
                    self.description = (values.get('content') or '').strip()
            elif tag == 'title' and not self.title:
                self.title_parts = []

        def handle_data(self, data):
            if not self.finished and self.title_parts is not None:
                self.title_parts.append(data)

        def handle_endtag(self, tag):
            if tag == 'head':
                self.finished = True
            elif tag == 'title' and not self.finished and self.title_parts is not None:
                self.title = ''.join(self.title_parts)
                self.title_parts = None

    try:
        with path.open('rb') as stream:
            head = stream.read(HTML_HEAD_LIMIT).decode('utf-8', errors='replace')
    except OSError:
        return ''
    parser = HeadMetadata()
    parser.feed(head)
    description = ' '.join((parser.description or parser.title).split())
    if len(description) > HTML_DESCRIPTION_LIMIT:
        description = description[:HTML_DESCRIPTION_LIMIT - 1].rstrip() + '…'
    return description


def strings(value):
    return sorted({v for v in value if isinstance(v, str) and v.strip()}, key=lambda v: (v.casefold(), v))


def read_text(path):
    try:
        return path.read_text(encoding='utf-8')
    except (OSError, UnicodeError):
        return ''


def read_json(path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, UnicodeError, ValueError):
        return None


def local_reference(root, source, value):
    """Resolve only local references inside the project, never fetch remote URIs."""
    if not isinstance(value, str) or not value or '\x00' in value:
        return None
    if value.startswith('res://'):
        target = root / value[6:]
    else:
        try:
            uri = urlsplit(value.replace('\\', '/'))
        except ValueError:
            return None
        if uri.scheme or uri.netloc or uri.query or uri.fragment:
            return None
        target = source.parent / unquote(uri.path)
    target = target.resolve()
    return target if target.is_relative_to(root) else None


def gltf_document(path):
    """Read GLB's JSON chunk without loading its mesh/texture binary payload."""
    if path.suffix.lower() == '.gltf':
        document = read_json(path)
    else:
        try:
            with path.open('rb') as stream:
                magic, version, length = struct.unpack('<4sII', stream.read(12))
                if magic != b'glTF' or version != 2 or length != path.stat().st_size:
                    return None
                size, kind = struct.unpack('<II', stream.read(8))
                if kind != 0x4E4F534A or size > length - 20:
                    return None
                document = json.loads(stream.read(size).decode('utf-8').rstrip('\x00 \r\n\t'))
        except (OSError, UnicodeError, ValueError, struct.error):
            return None
    if not isinstance(document, dict) or not isinstance(document.get('asset'), dict):
        return None
    return document if str(document['asset'].get('version', '')).startswith('2.') else None


def gltf_textures(root, path, document):
    textures = document.get('textures', [])
    images = document.get('images', [])
    if not isinstance(textures, list) or not isinstance(images, list):
        return set()
    indices = set()

    def visit(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key.lower().endswith('texture') and isinstance(child, dict):
                    index = child.get('index')
                    if type(index) is int:
                        indices.add(index)
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(document.get('materials', []))
    result = set()
    for index in indices:
        if not 0 <= index < len(textures) or not isinstance(textures[index], dict):
            continue
        texture = textures[index]
        sources = [texture.get('source')]
        extensions = texture.get('extensions', {})
        if isinstance(extensions, dict):
            sources.extend(extension.get('source') for extension in extensions.values() if isinstance(extension, dict))
        for source in sources:
            if type(source) is int and 0 <= source < len(images) and isinstance(images[source], dict):
                target = local_reference(root, path, images[source].get('uri'))
                if target is not None and target.suffix.lower() in IMAGES:
                    result.add(target)
    return result


def attributes(header):
    result = {}
    for key, value in re.findall(r'(\w+)=(' + STRING + ')', header):
        try:
            result[key] = json.loads(value)
        except ValueError:
            pass
    return result


def godot_document(root, path):
    """Read declared Animation/AnimationLibrary names and material texture links."""
    text = read_text(path)
    headers = list(SECTIONS.finditer(text))
    if not headers or not headers[0].group(1).startswith(('gd_resource ', 'gd_scene ')):
        return None
    resource_type = attributes(headers[0].group(1)).get('type', '')
    blocks = [(match.group(1), text[match.end():headers[index + 1].start() if index + 1 < len(headers) else len(text)])
              for index, match in enumerate(headers)]
    external = {}
    names = []
    library_names = []
    has_library = False
    animation = False
    textures = set()
    for header, body in blocks:
        attrs = attributes(header)
        if header.startswith('ext_resource '):
            target = local_reference(root, path, attrs.get('path'))
            if target is not None:
                external[attrs.get('id')] = target
    for header, body in blocks:
        kind = resource_type if header == 'resource' else attributes(header).get('type', '')
        if kind in {'Animation', 'AnimationLibrary'}:
            animation = True
        if kind == 'AnimationLibrary':
            has_library = True
            data = re.search(r'^_data\s*=\s*\{(.*?)\}', body, re.M | re.S)
            if data:
                for value in re.findall(r'(?:^|,)\s*&?(' + STRING + r')\s*:\s*(?:SubResource|ExtResource)\(', data.group(1), re.M):
                    try:
                        library_names.append(json.loads(value))
                    except ValueError:
                        pass
        elif kind == 'Animation':
            match = re.search(r'^resource_name\s*=\s*(' + STRING + ')', body, re.M)
            if match:
                try:
                    names.append(json.loads(match.group(1)))
                except ValueError:
                    pass
        if kind.endswith('Material') or kind in {'StandardMaterial3D', 'ORMMaterial3D'}:
            for value in re.findall(r'ExtResource\((' + STRING + r')\)', body):
                try:
                    target = external.get(json.loads(value))
                except ValueError:
                    continue
                if target is not None and target.suffix.lower() in IMAGES:
                    textures.add(target)
    # Library keys are the names used to play clips. A subresource's resource_name
    # can be an alternate display label, so don't count it as a second clip.
    return dict(resource_type=resource_type, names=strings(library_names if has_library else names),
                animation=animation, textures=textures)


def obj_textures(root, paths):
    """Only material libraries actually linked by an OBJ provide texture evidence."""
    result = set()
    libraries = set()
    for path in paths:
        for line in read_text(path).splitlines():
            if line.lstrip().startswith('mtllib '):
                try:
                    references = shlex.split(line.strip()[7:])
                except ValueError:
                    continue
                # Unquoted filenames containing spaces are common in OBJ exports.
                combined = local_reference(root, path, line.strip()[7:])
                if combined is not None and combined.is_file():
                    libraries.add(combined)
                else:
                    libraries.update(target for value in references if (target := local_reference(root, path, value)) is not None)
    for path in libraries:
        for line in read_text(path).splitlines():
            try:
                tokens = shlex.split(line, comments=True)
            except ValueError:
                continue
            if not tokens or tokens[0].lower() not in {'map_ka', 'map_kd', 'map_ks', 'map_ns', 'map_d', 'bump', 'map_bump', 'disp', 'decal', 'norm', 'refl'}:
                continue
            # MTL options precede the image filename. Resolve the longest existing
            # suffix, supporting both quoted and exporter-written unquoted spaces.
            for start in range(1, len(tokens)):
                target = local_reference(root, path, ' '.join(tokens[start:]))
                if target is not None and target.is_file() and target.suffix.lower() in IMAGES:
                    result.add(target)
                    break
    return result


def imported_fbx_metadata(root, paths):
    """Inspect existing remaps only. No --editor, --import, scene instantiation or saves."""
    candidates = {}
    for path in paths:
        text = read_text(Path(str(path) + '.import'))
        match = re.search(r'^path\s*=\s*(' + STRING + ')', text, re.M)
        if not match:
            continue
        try:
            imported = local_reference(root, path, json.loads(match.group(1)))
        except ValueError:
            continue
        if imported is not None and imported.is_relative_to(root / '.godot/imported') and imported.is_file():
            candidates[path.relative_to(root).as_posix()] = str(imported)
    engine = os.environ.get('GODOT_BIN') or str(root / '.artifacts/toolchain/godot')
    engine = shutil.which(engine) or (engine if Path(engine).is_file() else shutil.which('godot') or shutil.which('godot4'))
    if not candidates or not engine:
        return {}
    with tempfile.TemporaryDirectory(prefix='art-catalog-') as directory:
        temporary = Path(directory)
        source = temporary / 'input.json'
        target = temporary / 'output.json'
        source.write_text(json.dumps(candidates), encoding='utf-8')
        try:
            subprocess.run([engine, '--headless', '--path', str(root), '--log-file', str(temporary / 'godot.log'),
                            '--script', str(Path(__file__).with_name('read_art_import_metadata.gd')),
                            '--', str(source), str(target)],
                           env=dict(os.environ, XDG_DATA_HOME=directory, XDG_CONFIG_HOME=directory),
                           capture_output=True, text=True, timeout=45, check=False)
        except (OSError, subprocess.TimeoutExpired):
            return {}
        result = read_json(target)
        return result if isinstance(result, dict) else {}


def sequence_members(root, manifest_path=None):
    """Explicit file patterns backed by existing documentation, never folder guesses."""
    manifest = read_json(manifest_path or Path(__file__).with_name('art_catalog_sequences.json'))
    result = {}
    if not isinstance(manifest, list):
        return result
    for entry in manifest:
        if not isinstance(entry, dict) or not isinstance(entry.get('pattern'), str):
            continue
        pattern = entry['pattern']
        if not pattern.startswith('art_source/ui/') or '..' in Path(pattern).parts:
            continue
        evidence = entry.get('evidence', [])
        if not evidence or not all(isinstance(item, dict) and isinstance(item.get('path'), str)
                                   and isinstance(item.get('contains'), str)
                                   and (root / item['path']).resolve().is_relative_to(root)
                                   and item['contains'] in read_text(root / item['path']) for item in evidence):
            continue
        types = {'Animations'} | (set(entry.get('types', [])) & {'Textures'})
        for path in root.glob(pattern):
            if path.is_file() and not path.is_symlink():
                result.setdefault(path.resolve(), set()).update(types)
    return result


class ArtMetadata:
    def __init__(self, root, paths):
        self.root = root
        self.documents = {}
        self.textures = set()
        self.sequences = sequence_members(root)
        for path in paths:
            suffix = path.suffix.lower()
            if suffix in {'.glb', '.gltf'}:
                document = gltf_document(path)
                if document is None:
                    self.documents[path] = dict(animation=False, names=[], status='unavailable')
                    continue
                animations = document.get('animations', [])
                if not isinstance(animations, list):
                    self.documents[path] = dict(animation=False, names=[], status='unavailable')
                    continue
                self.documents[path] = dict(animation=bool(animations),
                                            names=strings(a.get('name') for a in animations if isinstance(a, dict)),
                                            status='available' if animations else 'not_applicable')
                self.textures.update(gltf_textures(root, path, document))
            elif suffix in {'.tres', '.tscn'}:
                document = godot_document(root, path)
                if document is not None:
                    document['status'] = 'available' if document['animation'] else 'not_applicable'
                    self.documents[path] = document
                    self.textures.update(document['textures'])
        self.textures.update(obj_textures(root, [p for p in paths if p.suffix.lower() == '.obj']))
        for relative, data in imported_fbx_metadata(root, [p for p in paths if p.suffix.lower() == '.fbx']).items():
            if isinstance(data, dict) and isinstance(data.get('clip_names'), list):
                names = strings(data['clip_names'])
                self.documents[root / relative] = dict(animation=bool(names), names=names,
                                                       status='available' if names else 'not_applicable')

    def is_animation_resource(self, path):
        return self.documents.get(path, {}).get('resource_type') in {'Animation', 'AnimationLibrary'}

    def fields(self, path, kind):
        relative = path.relative_to(self.root)
        types = [kind]
        if path.suffix.lower() in IMAGES and (path.resolve() in self.textures
                                             or 'Textures' in self.sequences.get(path.resolve(), set())
                                             or any(part.lower() in {'texture', 'textures'} for part in relative.parts[:-1])):
            types.append('Textures')
        document = self.documents.get(path, {})
        status = document.get('status', 'unavailable' if path.suffix.lower() in {'.fbx', '.blend'} else 'not_applicable')
        animation_folder = (status == 'unavailable' and path.suffix.lower() in {'.fbx', '.blend', '.glb', '.gltf'}
                            and any(part.lower() in {'animation', 'animations'} for part in relative.parts[:-1]))
        if document.get('animation') or animation_folder or path.resolve() in self.sequences or kind == 'Animations':
            if 'Animations' not in types:
                types.append('Animations')
        fields = dict(types=types, collections=['UI'] if relative.parts[:2] == ('art_source', 'ui') else [],
                      clip_names=document.get('names', []), clip_status=status,
                      modified_at=datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat(timespec='microseconds').replace('+00:00', 'Z'))
        if path.suffix.lower() in {'.html', '.htm'}:
            fields['description'] = html_description(path)
        return fields
