#!/usr/bin/env python3
"""Explicitly prepare local Art Book previews; never runs during browser searches."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from art_catalog_metadata import read_json, read_text
from art_preview_metadata import (CONVERTERS, MANIFEST, PREVIEW_DIR, VERSION,
    Fingerprints, PreviewMetadata, asset_url, direct_model, local_path,
    source_dependencies, unavailable)

ROOT = Path(__file__).resolve().parents[1]
# Image sequences do not depend on the 3D exporter or retarget profiles.
SEQUENCE_CONVERTERS = tuple(p for p in CONVERTERS if p != 'tools/export_art_previews.gd')


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
            stream.close()
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def rig_dependencies(relative):
    if relative.startswith('assets/animations/Mixamo/') and relative.lower().endswith('.fbx'):
        return ['assets/models/ual/runtime_rig.tscn', 'assets/models/ual/mannequin_body.res',
                'tools/art_preview_retarget.gd',
                'tools/art_preview_retarget_profiles/mixamo_common_v1.json',
                'tools/art_preview_retarget_profiles/mixamo_crawl_v1.json']
    if relative.startswith('assets/animations/ual/') and relative.endswith('.tres'):
        return ['assets/models/ual/runtime_rig.tscn', 'assets/models/ual/mannequin_body.res']
    if relative.startswith('assets/animations/') and '/' not in relative[len('assets/animations/'):] and relative.endswith('.tres'):
        return ['assets/third_party/fullplate_knight/knight_complete.glb']
    return []


def evidence_valid(root, entry):
    evidence = entry.get('evidence', [])
    return bool(evidence) and all(item.get('contains', '') in read_text(local_path(root, item['path'])) for item in evidence)


def prepare_sequences(root, manifest, fingerprints, only):
    specifications = read_json(root / 'tools/art_catalog_sequences.json') or []
    definitions = {e['preview']['sequence']: e['preview']['definition'] for e in specifications
                   if e.get('preview', {}).get('definition') and evidence_valid(root, e)}
    prepared = 0
    for sequence_id, definition in definitions.items():
        members = [e for e in specifications if e.get('preview', {}).get('sequence') == sequence_id and evidence_valid(root, e)]
        matching = [p for e in members for p in sorted(root.glob(e['pattern'])) if p.is_file()]
        if only and not any(any(term in p.relative_to(root).as_posix() for term in only) for p in matching):
            continue
        frames = sorted(p for p in root.glob(definition['frames_pattern']) if p.is_file())
        metadata_path = local_path(root, definition['metadata'])
        timing = read_json(metadata_path) or {}
        count, fps = timing.get('frames'), timing.get('fps')
        dependencies = [*SEQUENCE_CONVERTERS, definition['metadata'], *[p.relative_to(root).as_posix() for p in frames],
                        *[item['path'] for e in members for item in e['evidence']]]
        # Include expected absent frames so restoring one invalidates the unavailable record.
        if type(count) is int and 0 < count < 100000 and frames:
            first = frames[0]
            numeric = re.search(r'(\d+)$', first.stem)
            if numeric:
                prefix, width = first.stem[:numeric.start()], len(numeric.group())
                dependencies.extend((first.parent / f'{prefix}{i:0{width}d}{first.suffix}').relative_to(root).as_posix() for i in range(count))
        valid = type(count) is int and count > 0 and type(fps) in (float, int) and math.isfinite(fps) and fps > 0 and len(frames) == count
        indices = [int(re.search(r'(\d+)$', p.stem).group()) for p in frames if re.search(r'(\d+)$', p.stem)]
        valid = valid and indices == list(range(count))
        fingerprint = fingerprints.combined(dependencies)
        if valid:
            output = f'{PREVIEW_DIR}/sequences/{sequence_id}.json'
            payload = dict(version=VERSION, id=sequence_id, fps=fps, loop=definition.get('loop', False),
                           frames=[asset_url(p.relative_to(root).as_posix()) for p in frames])
            if read_json(root / output) != payload:
                atomic_json(root / output, payload)
            # Output may have just changed: avoid stale cached output hash.
            fingerprints.cache.pop(output, None)
            descriptor = dict(status='ready', kind='sequence', url=asset_url(output),
                model='', model_path='', fingerprint=fingerprint, clips=[], duration=count / fps,
                loop=definition.get('loop', False), sequence=dict(id=sequence_id, fps=fps,
                frame_count=count, frames_url=asset_url(output), start_frame=0))
            record = dict(descriptor=descriptor, dependencies=sorted(set(dependencies)), fingerprint=fingerprint,
                          output=output, output_sha256=fingerprints.file(output))
        else:
            record = dict(descriptor=unavailable('The documented frame sequence is incomplete or its timing is invalid.', 'sequence'),
                          dependencies=sorted(set(dependencies)), fingerprint=fingerprint)
        manifest['sequences'][sequence_id] = record
        for entry in members:
            for path in root.glob(entry['pattern']):
                if path.is_file():
                    start = int(re.search(r'(\d+)$', path.stem).group()) if entry['preview'].get('frame_from_filename') else 0
                    manifest['entries'][path.relative_to(root).as_posix()] = dict(sequence=sequence_id, start_frame=start)
        prepared += 1
    for entry in specifications:
        if entry.get('preview', {}).get('kind') != 'video' or not evidence_valid(root, entry):
            continue
        for path in root.glob(entry['pattern']):
            relative = path.relative_to(root).as_posix()
            if only and not any(term in relative for term in only):
                continue
            metadata = entry['preview'].get('metadata')
            timing = read_json(local_path(root, metadata)) or {}
            dependencies = [relative, metadata, *SEQUENCE_CONVERTERS, *[item['path'] for item in entry['evidence']]]
            fingerprint = fingerprints.combined(dependencies)
            descriptor = dict(status='ready', kind='video', url=asset_url(relative), model='', model_path='',
                              fingerprint=fingerprint, clips=[], duration=timing.get('duration', 0), fps=timing.get('fps', 0))
            manifest['entries'][relative] = dict(descriptor=descriptor, dependencies=sorted(set(dependencies)), fingerprint=fingerprint)
    return prepared


def run_exporter(root, jobs, engine):
    with tempfile.TemporaryDirectory(prefix='art-preview-jobs-') as directory:
        temporary = Path(directory)
        source, report = temporary / 'jobs.json', temporary / 'report.json'
        atomic_json(source, dict(jobs=jobs))
        try:
            result = subprocess.run([engine, '--headless', '--path', str(root), '--log-file', str(temporary / 'godot.log'),
                '--script', 'res://tools/export_art_previews.gd', '--', '--jobs', str(source), '--report', str(report)],
                env=dict(os.environ, XDG_DATA_HOME=directory, XDG_CONFIG_HOME=directory),
                capture_output=True, text=True, timeout=600, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            return {}, str(error)
        data = read_json(report)
        if not isinstance(data, dict) or not isinstance(data.get('results'), list):
            return {}, 'The converter did not produce a valid report. ' + (result.stderr or result.stdout)[-1000:]
        return {item.get('source', '').removeprefix('res://'): item for item in data['results']}, ''


def prepare(root=ROOT, only=(), force=False, engine=None, entries=None):
    root = Path(root).resolve()
    out = root / PREVIEW_DIR
    out.mkdir(parents=True, exist_ok=True)
    manifest_path = root / MANIFEST
    manifest = read_json(manifest_path) or {}
    if not isinstance(manifest, dict) or manifest.get('version') != VERSION:
        manifest = dict(version=VERSION, entries={}, sequences={})
    if not isinstance(manifest.get('entries'), dict):
        manifest['entries'] = {}
    if not isinstance(manifest.get('sequences'), dict):
        manifest['sequences'] = {}
    fingerprints = Fingerprints(root)
    sequence_count = prepare_sequences(root, manifest, fingerprints, only)
    if entries is None:
        from build_progress_tracker import scan_art
        entries = scan_art(root, root / 'docs/tracker')
    candidates = [e['path'] for e in entries if 'Animations' in e.get('types', [])
                  and Path(e['path']).suffix.lower() in {'.tres', '.fbx'}
                  and (not only or any(term in e['path'] for term in only))]
    engine = engine or os.environ.get('GODOT_BIN') or str(root / '.artifacts/toolchain/godot')
    engine = shutil.which(engine) or (engine if Path(engine).is_file() else shutil.which('godot') or shutil.which('godot4'))
    converted, cached = 0, 0
    with tempfile.TemporaryDirectory(prefix='.staging-', dir=out) as directory:
        staging = Path(directory)
        jobs, dependencies = [], {}
        for relative in candidates:
            old = manifest['entries'].get(relative, {})
            deps = source_dependencies(root, relative, [*CONVERTERS, *rig_dependencies(relative), *old.get('dependencies', [])])
            fingerprint = fingerprints.combined(deps)
            valid_output = not old.get('output') or fingerprints.file(old['output']) == old.get('output_sha256')
            if not force and old.get('fingerprint') == fingerprint and valid_output and old.get('descriptor', {}).get('status') == 'ready':
                cached += 1
                continue
            key = hashlib.sha256(relative.encode()).hexdigest()[:24]
            jobs.append(dict(source=relative, output=str(staging / (key + '.glb'))))
            dependencies[relative] = deps
        results, failure = run_exporter(root, jobs, engine) if jobs and engine else ({}, 'Godot is unavailable; prepare previews after installing the project toolchain.')
        for job in jobs:
            relative = job['source']
            result = results.get(relative, {})
            reported = [p.removeprefix('res://') for p in result.get('dependencies', [])]
            try:
                deps = source_dependencies(root, relative, [*dependencies[relative], *reported])
                fingerprint = fingerprints.combined(deps)
                temporary = Path(job['output'])
                if result.get('status') == 'ready' and temporary.is_file():
                    inspection = direct_model(root, temporary, fingerprints)
                    if inspection.get('status') != 'ready':
                        raise ValueError(inspection.get('reason', 'Converted model is invalid'))
                    clips = result['clips']
                    if len(clips) != len(inspection['clips']) or any(c['index'] != i
                        or c.get('export_name', c['name']) != inspection['clips'][i]['name']
                        or abs(c['duration'] - inspection['clips'][i]['duration']) > 0.001 for i, c in enumerate(clips)):
                        raise ValueError('Converted clip identity or duration differs from the source report')
                    final = out / (temporary.stem + '-' + fingerprint[:12] + '.glb')
                    os.replace(temporary, final)
                    output = final.relative_to(root).as_posix()
                    fingerprints.cache.pop(output, None)
                    descriptor = dict(status='ready', kind='model', url=asset_url(output),
                        model=result.get('model', ''), model_path=result.get('model_path', '').removeprefix('res://'),
                        fingerprint=fingerprint, clips=clips, validation=result.get('validation', {}))
                    if result.get('provenance'):
                        descriptor['provenance'] = dict(result['provenance'], dependency_fingerprint=fingerprint)
                    record = dict(descriptor=descriptor, dependencies=deps, fingerprint=fingerprint,
                                  output=output, output_sha256=fingerprints.file(output))
                    converted += 1
                else:
                    record = dict(descriptor=unavailable(result.get('reason') or failure or 'The converter rejected this asset.'),
                                  dependencies=deps, fingerprint=fingerprint)
            except (ValueError, OSError, KeyError, TypeError) as error:
                deps = dependencies[relative]
                record = dict(descriptor=unavailable(str(error)), dependencies=deps, fingerprint=fingerprints.combined(deps))
            manifest['entries'][relative] = record
            if record['descriptor']['status'] != 'ready':
                print(f'Unavailable: {relative}: {record["descriptor"]["reason"]}')
    atomic_json(manifest_path, manifest)
    print(f'Previews: {converted} converted, {cached} cached, {sequence_count} documented sequences. Rebuild the tracker catalog next.')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', action='append', default=[], help='Prepare matching path substrings only (repeatable).')
    parser.add_argument('--force', action='store_true', help='Rebuild even when cached fingerprints match.')
    args = parser.parse_args()
    prepare(only=args.only, force=args.force)


if __name__ == '__main__':
    main()
