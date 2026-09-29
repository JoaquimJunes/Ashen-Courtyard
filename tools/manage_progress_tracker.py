#!/usr/bin/env python3
"""Install or open the offline tracker using the Linux user service manager."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.request import ProxyHandler, build_opener

ROOT = Path(__file__).resolve().parents[1]
SERVICE = 'ashen-courtyard-tracker.service'
URL = 'http://127.0.0.1:8765/docs/tracker/'
MARKER = '# Managed by tools/manage_progress_tracker.py.'


def unit_quote(value, *, command=False):
    value = str(value)
    if any(ord(c) < 32 for c in value):
        raise ValueError('Launcher paths cannot contain control characters.')
    value = value.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%')
    if command:
        value = value.replace('$', '$$')
    return '"' + value + '"'


def desktop_quote(value):
    """Escape both Desktop Entry string parsing and Exec argument parsing."""
    value = str(value)
    if any(ord(c) < 32 for c in value):
        raise ValueError('Launcher paths cannot contain control characters.')
    for character in ('\\', '"', '`', '$'):
        value = value.replace(character, '\\' + character)
    return '"' + value.replace('\\', '\\\\').replace('%', '%%') + '"'


def service_text(root, python):
    command = ' '.join(unit_quote(value, command=True) for value in
                       (python, root / 'tools/serve_progress_tracker.py', '--root', root, '--port', '8765'))
    return f'''{MARKER}
[Unit]
Description=Ashen Courtyard offline Dev book and Art Book
StartLimitIntervalSec=0

[Service]
Type=exec
ExecStart={command}
Environment=PYTHONUNBUFFERED=1
Restart=always
RestartSec=3
KillSignal=SIGINT
TimeoutStopSec=15

[Install]
WantedBy=default.target
'''


def desktop_text(root, python):
    command = ' '.join(desktop_quote(value) for value in
                       (python, root / 'tools/manage_progress_tracker.py', 'open'))
    return f'''{MARKER}
[Desktop Entry]
Type=Application
Name=Ashen Courtyard Tracker
Comment=Open the offline Dev book and Art Book
Exec={command}
Icon=applications-development
Terminal=false
StartupNotify=false
Categories=Development;
Keywords=Ashen;Tracker;DevBook;ArtBook;Offline;
'''


def managed_write(path, text, mode=0o644):
    """Keep a recovery copy when updating an already installed launcher."""
    path = Path(path)
    if path.is_symlink():
        raise RuntimeError(f'Refusing to replace a symbolic link: {path}')
    if path.exists():
        previous = path.read_text()
        if previous == text:
            path.chmod(mode)
            return False
        if not previous.startswith(MARKER):
            raise RuntimeError(f'An unrelated file already exists at {path}; nothing was replaced.')
        shutil.copy2(path, path.with_name(path.name + '.bak'))
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(mode)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return True


def systemctl(*args):
    result = subprocess.run(['systemctl', '--user', *args], capture_output=True, text=True, timeout=25)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or 'The tracker service could not start.')
    return result.stdout.strip()


def wait_ready(timeout=15):
    # Local requests must not depend on internet or the user's proxy settings.
    opener = build_opener(ProxyHandler({}))
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            with opener.open('http://127.0.0.1:8765/api/tracker', timeout=1) as response:
                if not response.headers.get('Server', '').startswith('LocalProgressTracker/'):
                    raise RuntimeError('Port 8765 is occupied by another application.')
                data = json.load(response)
                if not isinstance(data.get('items'), dict) or not isinstance(data.get('history'), list):
                    raise RuntimeError('The tracker did not return readable project data.')
            with opener.open(URL, timeout=1) as response:
                if response.status != 200:
                    raise RuntimeError('The tracker page is unavailable.')
            return
        except (OSError, ValueError) as error:
            last_error = error
            time.sleep(.15)
    raise RuntimeError(f'The tracker did not become ready: {last_error}. '
                       f'Check: journalctl --user -u {SERVICE} -n 30')


def install(shortcut_dir=None):
    if not (ROOT / 'tools/serve_progress_tracker.py').is_file():
        raise RuntimeError('The project tracker server is missing.')
    python = Path('/usr/bin/python3')
    if not python.is_file():
        raise RuntimeError('Install the system Python 3 runtime first.')
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    changed = managed_write(config / 'systemd/user' / SERVICE, service_text(ROOT, python))
    desktop = desktop_text(ROOT, python)
    managed_write(data / 'applications/ashen-courtyard-tracker.desktop', desktop, 0o755)
    if shortcut_dir is not None:
        shortcut = Path(shortcut_dir).expanduser() / 'Open Project Tracker.desktop'
        managed_write(shortcut, desktop, 0o755)
        if shutil.which('gio'):
            subprocess.run(['gio', 'set', str(shortcut), 'metadata::trusted', 'true'],
                           capture_output=True, timeout=5)
    systemctl('daemon-reload')
    systemctl('enable', SERVICE)
    systemctl('restart' if changed else 'start', SERVICE)
    wait_ready()
    print('Installed: starts at sign-in and restarts automatically.\n' + URL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('install', 'open', 'status'))
    parser.add_argument('--shortcut-dir', type=Path, help='Also install an Open Project Tracker shortcut in this folder.')
    parser.add_argument('--no-browser', action='store_true', help='Start and verify the tracker without opening a browser.')
    args = parser.parse_args()
    try:
        if args.action == 'install':
            install(args.shortcut_dir)
        elif args.action == 'status':
            print(systemctl('is-enabled', SERVICE))
            print(systemctl('is-active', SERVICE))
            wait_ready()
            print(URL)
        else:
            systemctl('start', SERVICE)
            wait_ready()
            if not args.no_browser:
                subprocess.run(['xdg-open', URL], check=True, timeout=15)
            print(URL)
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        text = 'Could not open the offline tracker.\n' + str(error)
        print(text, file=sys.stderr)
        if args.action == 'open' and not args.no_browser and shutil.which('zenity'):
            subprocess.run(['zenity', '--error', '--title=Ashen Courtyard Tracker', '--text=' + text], check=False)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
