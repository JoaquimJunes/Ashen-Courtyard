"""Checks for failure detection, clean isolation, and verified build downloads."""
import hashlib
import contextlib
import io
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import check_project
import install_toolchain
import run_tests


class BuildPipelineTests(unittest.TestCase):
    def test_version_pin(self):
        check_project.validate_version('4.6.2.stable.official.71f334935')
        for version in ('4.6.1.stable.official', '4.6.2.rc1.official', '4.7.stable.official'):
            with self.assertRaises(ValueError):
                check_project.validate_version(version)

    def test_clean_copy_omits_caches_and_preserves_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            source.mkdir()
            for folder in ('.git', '.godot', '.artifacts', 'graphify-out', 'features'):
                (source / folder).mkdir()
                (source / folder / 'value').write_text('preserved original')
            check_project.copy_source(source, root / 'copy')
            self.assertEqual([p.name for p in (root / 'copy').iterdir()], ['features'])
            self.assertEqual((source / '.godot/value').read_text(), 'preserved original')

    def run_result(self, result, required=None):
        with tempfile.TemporaryDirectory() as directory:
            records = []
            with patch('check_project.subprocess.run', return_value=result), contextlib.redirect_stderr(io.StringIO()):
                check_project.run_step('probe', ['unused'], Path(directory), {}, Path(directory), records,
                                       required_output=required)
            return records

    def test_engine_error_fails_even_with_zero_exit(self):
        with self.assertRaises(RuntimeError):
            self.run_result(subprocess.CompletedProcess([], 0, 'SCRIPT ERROR: broken\n', ''))

    def test_nonzero_exit_fails(self):
        with self.assertRaises(RuntimeError):
            self.run_result(subprocess.CompletedProcess([], 1, '', ''))

    def test_smoke_requires_completion_marker(self):
        with self.assertRaises(RuntimeError):
            self.run_result(subprocess.CompletedProcess([], 0, 'Engine started\n', ''), 'RELEASE SMOKE: PASS')
        result = self.run_result(subprocess.CompletedProcess([], 0, 'RELEASE SMOKE: PASS\n', ''), 'RELEASE SMOKE: PASS')
        self.assertTrue(result[0]['passed'])

    def test_timeout_records_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            records = []
            timeout = subprocess.TimeoutExpired(['probe'], 1, output=b'before timeout', stderr=b'error detail')
            with patch('check_project.subprocess.run', side_effect=timeout), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(RuntimeError):
                check_project.run_step('timeout', ['probe'], Path(directory), {}, Path(directory), records)
            self.assertFalse(records[0]['passed'])
            self.assertIn('error detail', (Path(directory) / 'timeout.log').read_text())

    def test_runner_timeout_preserves_stderr_and_line_boundaries(self):
        timeout = subprocess.TimeoutExpired(['probe'], 1, output=b'PASS: first check\n',
                                            stderr=b'SCRIPT ERROR: important failure\n')
        output = run_tests.timeout_output(timeout)
        self.assertIn('\nSCRIPT ERROR: important failure\n', output)
        self.assertIn('SCRIPT ERROR: important failure', run_tests.classify(-1, output)['errors'])

    def test_verified_cache_avoids_network(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'cache.zip'
            archive.write_bytes(b'correct')
            with patch('install_toolchain.urllib.request.urlopen') as network:
                install_toolchain.download_verified('unused', archive, hashlib.sha256(b'correct').hexdigest())
            network.assert_not_called()

    def test_corrupt_download_cannot_replace_cache(self):
        import io
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'cache.zip'
            archive.write_bytes(b'old cache')
            with patch('install_toolchain.urllib.request.urlopen', return_value=io.BytesIO(b'corrupt')):
                with self.assertRaises(ValueError):
                    install_toolchain.download_verified('unused', archive, hashlib.sha256(b'expected').hexdigest())
            self.assertEqual(archive.read_bytes(), b'old cache')
            self.assertEqual(len(list(Path(directory).iterdir())), 1)

    def test_release_archive_preserves_executable_and_checksums(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'ashen-courtyard.x86_64').write_bytes(b'binary')
            (root / 'ashen-courtyard.x86_64').chmod(0o755)
            (root / 'ashen-courtyard.pck').write_bytes(b'pack')
            (root / 'CREDITS.md').write_text('credits')
            (root / 'licenses').mkdir()
            check_project.package_release(root, root)
            with tarfile.open(root / 'ashen-courtyard-linux-x86_64.tar.gz') as archive:
                self.assertEqual(archive.getmember('ashen-courtyard/ashen-courtyard.x86_64').mode, 0o755)
            self.assertTrue((root / 'SHA256SUMS').read_text().endswith('ashen-courtyard-linux-x86_64.tar.gz\n'))


if __name__ == '__main__':
    unittest.main()
