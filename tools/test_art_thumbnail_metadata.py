import copy
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest

from art_preview_metadata import Fingerprints
from art_thumbnail_metadata import (MANIFEST, RENDER_FILES, WIDTH, HEIGHT,
    apply_thumbnail_metadata, cached_thumbnail, renderer_fingerprint, request_for)


class ThumbnailMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in RENDER_FILES:
            self.write(name, b'renderer')
        self.write('model.glb', b'model bytes')
        self.clip = dict(id='art:clip:first', parent_id='art:model', source_clip=dict(id='native:walk', index=0, name='Walk', duration=1),
                         preview=dict(status='ready',kind='model',url='../../model.glb',fingerprint='prepared',clips=[]))

    def write(self, relative, contents):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)

    def request(self, entry=None):
        fingerprints = Fingerprints(self.root)
        return request_for(self.root, entry or self.clip, fingerprints, renderer_fingerprint(self.root, fingerprints))

    def record(self, request):
        png = b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', WIDTH, HEIGHT)
        self.write(request['output'], png)
        return dict(status='ready', fingerprint=request['fingerprint'], output=request['output'], output_sha256=hashlib.sha256(png).hexdigest(), empty=False)

    def test_source_and_renderer_changes_invalidate_independently(self):
        before = self.request()
        self.write('model.glb', b'edited pose')
        after = self.request()
        self.assertNotEqual(before['fingerprint'], after['fingerprint'])
        self.write(RENDER_FILES[0], b'new camera')
        self.assertNotEqual(after['fingerprint'], self.request()['fingerprint'])

    def test_clip_binding_and_parent_identity_are_part_of_cache(self):
        before = self.request()
        self.clip['source_clip']['index'] = 1
        self.assertNotEqual(before['fingerprint'], self.request()['fingerprint'])
        self.clip['id'] = 'art:clip:other-parent'
        self.assertNotEqual(before['output'], self.request()['output'])

    def test_corrupt_or_missing_png_is_not_published(self):
        request = self.request()
        record = self.record(request)
        self.assertEqual(cached_thumbnail(self.root, request, record, Fingerprints(self.root))['status'], 'ready')
        self.write(request['output'], b'broken')
        self.assertIsNone(cached_thumbnail(self.root, request, record, Fingerprints(self.root)))
        (self.root / request['output']).unlink()
        self.assertIsNone(cached_thumbnail(self.root, request, record, Fingerprints(self.root)))

    def test_metadata_does_not_mutate_preview_or_tracking(self):
        request = self.request()
        record = self.record(request)
        self.write(MANIFEST, json.dumps(dict(version=1,entries={request['id']:record})).encode())
        catalog = dict(animation_clips=[self.clip], art=[dict(id='art:model',path='model.glb')], packs=[], tracking={'note':'Keep me'})
        old_preview = copy.deepcopy(self.clip['preview'])
        apply_thumbnail_metadata(catalog, self.root)
        self.assertEqual(self.clip['preview'], old_preview)
        self.assertEqual(catalog['tracking'], {'note':'Keep me'})
        self.assertEqual(self.clip['thumbnail']['time'], 0)
        self.assertEqual(catalog['art'][0]['thumbnail'], self.clip['thumbnail'])

    def test_sequence_uses_zero_not_pack_cover_or_start_frame(self):
        self.write('frames.json', json.dumps(dict(frames=['../../zero.png','../../later.png'])).encode())
        self.write('zero.png', b'zero')
        self.write('later.png', b'later')
        sequence = dict(id='art:pack:sequence', cover='later', preview=dict(status='ready',kind='sequence',url='../../frames.json', fingerprint='sequence',sequence=dict(id='wisps',start_frame=176)))
        request = self.request(sequence)
        self.assertEqual(request['image'], '../../zero.png')
        self.assertEqual(request['id'], 'sequence:wisps')
        sequence['id'] = 'art:frame:176'
        self.assertEqual(request['fingerprint'], self.request(sequence)['fingerprint'])

    def test_error_does_not_disable_playable_preview(self):
        request = self.request()
        self.write(MANIFEST, json.dumps(dict(version=1,entries={request['id']:dict(status='error',fingerprint=request['fingerprint'],reason='No WebGL')})).encode())
        apply_thumbnail_metadata(dict(animation_clips=[self.clip]), self.root)
        self.assertEqual(self.clip['thumbnail']['status'], 'error')
        self.assertEqual(self.clip['preview']['status'], 'ready')

    def test_external_and_escaping_sources_are_rejected(self):
        for url in ['https://example.com/private.glb', '../../../../outside.glb']:
            self.clip['preview']['url'] = url
            with self.assertRaises(ValueError):
                self.request()

    def test_unknown_manifest_version_is_not_accepted(self):
        request = self.request()
        self.write(MANIFEST, json.dumps(dict(version=9,entries={request['id']:self.record(request)})).encode())
        apply_thumbnail_metadata(dict(animation_clips=[self.clip]), self.root)
        self.assertEqual(self.clip['thumbnail']['status'], 'pending')

    def test_malformed_cache_does_not_break_catalog_or_playback(self):
        for contents in [b'{broken', b'["invalid root"]', b'null']:
            self.write(MANIFEST, contents)
            apply_thumbnail_metadata(dict(animation_clips=[self.clip]), self.root)
            self.assertEqual(self.clip['thumbnail']['status'], 'pending')
            self.assertEqual(self.clip['preview']['status'], 'ready')


if __name__ == '__main__':
    unittest.main()
