"""Actual imported-clip duplicate checks; reports use disposable output files."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from art_asset_identity import canonical_path

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get('GODOT_BIN', ROOT / '.artifacts/toolchain/godot'))


@unittest.skipUnless(GODOT.is_file(), 'The project Godot toolchain is unavailable')
class AnimationDuplicateTests(unittest.TestCase):
    def test_exact_duplicates_verify_but_distinct_directions_and_missing_sources_do_not(self):
        prefix = 'assets/animations/Mixamo/'
        left = prefix + 'Braced Hang Shimmy Left.fbx'
        same = prefix + 'Braced Hang Shimmy.fbx'
        right = prefix + 'Braced Hang Shimmy Right.fbx'
        missing = prefix + 'Missing audit fixture.fbx'
        if not all((ROOT / canonical_path(ROOT, path)).is_file() for path in (left, right)):
            self.skipTest('The distinct directional source fixtures are unavailable')
        before = {path: hashlib.sha256((ROOT / canonical_path(ROOT, path)).read_bytes()).hexdigest()
                  for path in (left, same, right) if (ROOT / canonical_path(ROOT, path)).is_file()}
        with tempfile.TemporaryDirectory(prefix='animation-duplicate-audit-', dir=ROOT / '.artifacts') as directory:
            folder = Path(directory)
            jobs, report = folder / 'jobs.json', folder / 'report.json'
            jobs.write_text(json.dumps({'pairs': [{'members': [left, same]}, {'members': [left, right]},
                                                   {'members': [left, missing]}], 'sources': [left]}))
            process = subprocess.run([str(GODOT), '--headless', '--path', str(ROOT), '--log-file', str(folder / 'engine.log'),
                                      '--script', 'res://tools/verify_animation_duplicates.gd', '--',
                                      '--jobs', str(jobs), '--report', str(report)], capture_output=True, text=True, timeout=60)
            self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            data = json.loads(report.read_text())
        identical, different, unavailable = data['groups']
        with self.subTest('known independent duplicate pair'):
            if same not in before:
                self.skipTest('Redundant source was removed; historical proof remains in .artifacts/animation-naming/pose-verification.json')
            self.assertTrue(identical['verified'])
            self.assertGreater(identical['samples'], 120)
            self.assertEqual(identical['max_position_error_m'], 0)
            self.assertEqual(identical['max_basis_error'], 0)
            self.assertEqual(identical['member_sha256'][left], before[left])
        self.assertFalse(different['verified'], 'Left and right motions must remain distinct')
        self.assertFalse(unavailable['verified'])
        self.assertIn('unavailable', unavailable['reason'].lower())
        inspection = data['sources'][0]
        self.assertEqual(len(inspection['clips'][0]['poses']), 9)
        self.assertEqual(inspection['clips'][0]['poses'][0]['time'], 0)
        self.assertAlmostEqual(inspection['clips'][0]['poses'][-1]['time'], inspection['clips'][0]['duration'])
        self.assertGreater(len(inspection['bones']), 50)
        self.assertEqual(before, {path: hashlib.sha256((ROOT / canonical_path(ROOT, path)).read_bytes()).hexdigest() for path in before})


if __name__ == '__main__':
    unittest.main()
