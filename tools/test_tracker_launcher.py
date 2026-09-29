"""Launcher generation uses disposable paths; it never changes user services."""
from pathlib import Path
import tempfile
import unittest

import manage_progress_tracker as launcher


class LauncherTests(unittest.TestCase):
    def test_login_and_recovery_do_not_require_network_or_terminal(self):
        root = Path('/tmp/Ashen Courtyard')
        unit = launcher.service_text(root, Path('/usr/bin/python3'))
        self.assertIn('WantedBy=default.target', unit)
        self.assertIn('Restart=always', unit)
        self.assertIn('StartLimitIntervalSec=0', unit)
        self.assertNotIn('network', unit)
        self.assertIn('"/tmp/Ashen Courtyard/tools/serve_progress_tracker.py"', unit)
        desktop = launcher.desktop_text(root, Path('/usr/bin/python3'))
        self.assertIn('Terminal=false', desktop)
        self.assertIn('"/tmp/Ashen Courtyard/tools/manage_progress_tracker.py" "open"', desktop)

    def test_service_path_specifiers_are_literal(self):
        self.assertEqual(launcher.unit_quote('/tmp/50%/$cash', command=True), '"/tmp/50%%/$$cash"')
        self.assertEqual(launcher.desktop_quote('/tmp/50%/a b'), '"/tmp/50%%/a b"')
        for value in ('a\nb', 'a\0b'):
            for quote in (launcher.unit_quote, launcher.desktop_quote):
                with self.assertRaises(ValueError):
                    quote(value)

    def test_reinstall_keeps_recovery_copy_and_refuses_unrelated_files(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / 'user/tracker.service'
            first = launcher.MARKER + '\nfirst'
            self.assertTrue(launcher.managed_write(target, first))
            self.assertFalse(launcher.managed_write(target, first))
            self.assertTrue(launcher.managed_write(target, launcher.MARKER + '\nsecond'))
            self.assertEqual(target.with_name(target.name + '.bak').read_text(), first)
            target.write_text('Existing unrelated configuration')
            with self.assertRaises(RuntimeError):
                launcher.managed_write(target, first)
            self.assertEqual(target.read_text(), 'Existing unrelated configuration')


if __name__ == '__main__':
    unittest.main()
