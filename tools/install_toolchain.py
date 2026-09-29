#!/usr/bin/env python3
"""Install the checksum-pinned Linux build tools inside the project artifacts folder."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'tools/godot-toolchain.json'
DEFAULT_DIRECTORY = ROOT / '.artifacts/toolchain'


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def download_verified(url, destination, expected):
    if destination.exists() and sha256(destination) == expected:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Never replace a cached archive until the complete download has been verified.
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                shutil.copyfileobj(response, stream)
            stream.close()
            if sha256(temporary) != expected:
                raise ValueError(f'Checksum mismatch for {destination.name}')
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)


def extract_member(archive, member, destination, executable=False):
    # Extract explicit known members, never arbitrary paths from a ZIP archive.
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as package, package.open(member) as source:
        with destination.open('wb') as target:
            shutil.copyfileobj(source, target)
    if executable:
        destination.chmod(0o755)


def install(directory, templates_only=False):
    lock = json.loads(LOCK.read_text())
    directory = directory.resolve()
    archives = directory / 'archives'
    if not templates_only:
        editor = lock['editor']
        archive = archives / editor['filename']
        print('Downloading/verifying pinned Godot editor...', flush=True)
        download_verified(lock['base_url'] + editor['filename'], archive, editor['sha256'])
        extract_member(archive, editor['member'], directory / 'godot', executable=True)
    templates = lock['templates']
    archive = archives / templates['filename']
    print('Downloading/verifying pinned export templates (about 1.25 GB)...', flush=True)
    download_verified(lock['base_url'] + templates['filename'], archive, templates['sha256'])
    template_dir = directory / 'data/godot/export_templates' / lock['template_version']
    for name in ('linux_debug.x86_64', 'linux_release.x86_64', 'version.txt'):
        extract_member(archive, 'templates/' + name, template_dir / name, executable=name != 'version.txt')
    print(f'Toolchain ready: {directory}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=DEFAULT_DIRECTORY)
    parser.add_argument('--templates-only', action='store_true', help='Use an existing editor; install just Linux templates')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'AMD64'):
        parser.error('This pinned distribution is Linux x86_64 only.')
    install(args.directory, args.templates_only)


if __name__ == '__main__':
    main()
