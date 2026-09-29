#!/usr/bin/env python3
"""Render exact frame-zero Art Book thumbnails offline; never changes tracking data.

Run after preparing previews and rebuilding the catalog, then rebuild the catalog
again to publish thumbnail metadata. Playwright and Chromium must be installed.
"""
import argparse
import hashlib
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

from art_catalog_metadata import read_json
from art_preview_metadata import Fingerprints, PreviewMetadata
from art_thumbnail_metadata import (ROOT, VERSION, WIDTH, HEIGHT, DIRECTORY, MANIFEST,
    cached_thumbnail, png_dimensions, renderer_fingerprint, request_for, thumbnail_entries)
from prepare_art_previews import atomic_json
from serve_progress_tracker import TrackerHandler


class CaptureHandler(TrackerHandler):
    """Reuse local host/path/range protections; this server has no state API."""
    def log_message(self, *_args):
        pass

    def do_GET(self):
        if self._request_path().startswith('/api/'):
            return self.send_error(404)
        return super().do_GET()

    def do_HEAD(self):
        if self._request_path().startswith('/api/'):
            return self.send_error(404)
        return super().do_HEAD()

    def do_PUT(self):
        return self.send_error(405)


def current_entries(root, catalog):
    """Refuse stale prepared previews even when the supplied catalog is old."""
    parents = {entry['id']: dict(entry) for entry in catalog.get('art', [])}
    PreviewMetadata(root).apply(list(parents.values()))
    entries = []
    for original in thumbnail_entries(catalog):
        entry = dict(original)
        parent = parents.get(entry.get('parent_id', entry['id']))
        # Sequence packs share a member's documented descriptor.
        if not parent and entry.get('preview_member'):
            parent = parents.get(entry['preview_member'])
        if parent:
            entry['preview'] = parent.get('preview', {})
            if entry.get('source_clip') and entry['preview'].get('status') == 'ready':
                source = entry['source_clip']
                matches = [clip for clip in entry['preview'].get('clips', []) if clip == source]
                if len(matches) != 1:
                    entry['preview'] = dict(status='stale', reason='Clip binding changed; rebuild the catalog.')
        entries.append(entry)
    return entries


def prepare(root=ROOT, catalog_path=None, only=(), force=False, chromium=None, node=None):
    root = Path(root).resolve()
    catalog = read_json(Path(catalog_path) if catalog_path else root / 'docs/tracker/catalog.json')
    if not isinstance(catalog, dict) or 'animation_clips' not in catalog:
        raise ValueError('Build the clip catalog before preparing thumbnails.')
    output_dir = root / DIRECTORY
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest = read_json(root / MANIFEST) or {}
    if not isinstance(manifest, dict) or manifest.get('version') != VERSION or not isinstance(manifest.get('entries'), dict):
        manifest = dict(version=VERSION, entries={})
    fingerprints = Fingerprints(root)
    renderer = renderer_fingerprint(root, fingerprints)
    pending = {}
    seen = set()
    cached = unavailable = 0
    for entry in current_entries(root, catalog):
        if only and not any(term in entry.get('path', '') or term in entry.get('title', '') or term in entry['id'] for term in only):
            continue
        try:
            request = request_for(root, entry, fingerprints, renderer)
        except (ValueError, OSError, KeyError, TypeError):
            unavailable += 1
            continue
        if request is None:
            unavailable += 1
            continue
        key = request['id']
        if key in seen:
            continue
        seen.add(key)
        record = cached_thumbnail(root, request, manifest['entries'].get(key), fingerprints)
        if not force and record and record['status'] == 'ready':
            cached += 1
        else:
            pending[key] = request
    if not pending:
        print(f'Thumbnails: {cached} cached, {unavailable} unavailable; nothing to render.')
        return dict(prepared=0, failed=0, cached=cached, unavailable=unavailable)
    # Models grouped by URL allow all clips to share one resource load.
    jobs = sorted(pending.values(), key=lambda item: (item['descriptor']['kind'], item['descriptor']['url'], (item.get('clip') or {}).get('index', 0)))
    env = os.environ.copy()
    bundled = Path.home() / '.cache/codex-runtimes/codex-primary-runtime/dependencies/node'
    env.setdefault('NODE_PATH', str(bundled / 'node_modules'))
    executable = node or shutil.which('node') or str(bundled / 'bin/node')
    chromium = chromium or shutil.which('chromium') or shutil.which('chromium-browser')
    if not chromium:
        raise ValueError('Chromium is required; supply --chromium with its executable path.')
    with tempfile.TemporaryDirectory(prefix='.capture-', dir=output_dir) as temporary:
        stage = Path(temporary)
        with ThreadingHTTPServer(('127.0.0.1', 0), CaptureHandler) as server:
            server.root = root
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                atomic_json(stage / 'jobs.json', dict(jobs=jobs, output=str(stage), executable=chromium,
                    url=f'http://127.0.0.1:{server.server_port}/docs/tracker/thumbnail-render.html'))
                subprocess.run([executable, str(root / 'tools/capture_art_thumbnails.cjs'), str(stage / 'jobs.json'), str(stage / 'results.json')],
                               env=env, cwd=root, check=True, timeout=max(120, len(jobs) * 45))
            finally:
                server.shutdown()
                thread.join()
        results = read_json(stage / 'results.json')
        if not isinstance(results, list) or len(results) != len(jobs):
            raise ValueError('The renderer did not return every requested thumbnail.')
        prepared = failed = 0
        for result in results:
            request = pending[result['id']]
            record = dict(status=result['status'], fingerprint=request['fingerprint'])
            if result['status'] == 'ready':
                source = stage / Path(request['output']).name
                if png_dimensions(source) != (WIDTH, HEIGHT):
                    raise ValueError('Renderer returned a thumbnail with incorrect dimensions.')
                record.update(output=request['output'], output_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                              empty=result['empty'], capture={key: value for key, value in result.items() if key not in {'id','status','filename','empty'}})
                os.replace(source, root / request['output'])
                prepared += 1
            else:
                record['reason'] = result.get('reason', 'Could not render the first frame.')
                failed += 1
            manifest['entries'][request['id']] = record
        # PNGs are immutable cache files; the manifest is the atomic publication
        # point. An interrupted build leaves the previous manifest usable.
        atomic_json(root / MANIFEST, manifest)
    print(f'Thumbnails: {prepared} prepared, {failed} failed, {cached} cached, {unavailable} unavailable.')
    return dict(prepared=prepared, failed=failed, cached=cached, unavailable=unavailable)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--catalog', type=Path)
    parser.add_argument('--only', action='append', default=[], help='Source path, title or ID substring; repeatable.')
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--chromium')
    parser.add_argument('--node')
    args = parser.parse_args()
    try:
        result = prepare(args.root, args.catalog, args.only, args.force, args.chromium, args.node)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f'Thumbnail preparation failed: {error}\n')
    if result['failed']:
        parser.exit(1, 'Some thumbnails could not be prepared; animation playback remains available.\n')


if __name__ == '__main__':
    main()
