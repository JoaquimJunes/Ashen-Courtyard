#!/usr/bin/env python3
"""Validate a clean import, all regressions, and optionally the actual Linux release."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / 'tools/godot-toolchain.json').read_text())
IGNORED = {'.git', '.godot', '.artifacts', 'graphify-out', '__pycache__'}
ENGINE_ERRORS = re.compile(r'^(?:SCRIPT ERROR:|ERROR:|FAIL\b).*', re.MULTILINE)


def validate_version(version):
    if not version.strip().startswith(LOCK['engine_version_prefix']):
        raise ValueError(f"Expected Godot {LOCK['version']}, received {version.strip()!r}")


def copy_source(source, destination):
    shutil.copytree(source, destination, ignore=lambda _path, names: IGNORED.intersection(names))


def package_release(build, project):
    """Preserve executable permissions when the build passes through CI artifacts."""
    files = [build / 'ashen-courtyard.x86_64', build / 'ashen-courtyard.pck']
    for file in files:
        if not file.is_file() or file.stat().st_size == 0:
            raise RuntimeError(f'Missing or empty exported file: {file}')
    archive = build / 'ashen-courtyard-linux-x86_64.tar.gz'
    with tarfile.open(archive, 'w:gz') as package:
        for file in files:
            package.add(file, arcname='ashen-courtyard/' + file.name)
        package.add(project / 'CREDITS.md', arcname='ashen-courtyard/CREDITS.md')
        package.add(project / 'licenses', arcname='ashen-courtyard/licenses')
    with archive.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    (build / 'SHA256SUMS').write_text(f'{digest}  {archive.name}\n')


def run_step(name, command, cwd, env, report_dir, records, timeout=300, required_output=None):
    print(f'Checking {name}...', flush=True)
    try:
        result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
        output, code = result.stdout + result.stderr, result.returncode
    except subprocess.TimeoutExpired as error:
        def decode(value):
            return value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
        output, code = decode(error.stdout) + decode(error.stderr) + '\nERROR: Check timed out\n', -1
    errors = ENGINE_ERRORS.findall(output)
    passed = code == 0 and not errors and (required_output is None or required_output in output)
    log = report_dir / f'{name}.log'
    log.write_text(output)
    records.append({'step': name, 'passed': passed, 'exit_code': code, 'errors': errors, 'log': str(log)})
    if not passed:
        print(output[-6000:], file=sys.stderr)
        raise RuntimeError(f'{name} failed; see {log}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', str(ROOT / '.artifacts/toolchain/godot')))
    parser.add_argument('--clean', action='store_true', help='Validate a temporary source copy without import caches')
    parser.add_argument('--release', action='store_true', help='Export and smoke-test the Linux release, using installed templates')
    parser.add_argument('--toolchain', type=Path, default=ROOT / '.artifacts/toolchain')
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--test-timeout', type=int, default=120,
                        help='Per-suite timeout; long movement matrices need headroom during parallel clean checks')
    args = parser.parse_args()
    engine = shutil.which(args.godot) or str(Path(args.godot).expanduser().resolve())
    if not Path(engine).is_file():
        parser.error('Godot is missing. Run tools/install_toolchain.py or supply --godot.')
    version = subprocess.check_output([engine, '--version'], text=True, timeout=30).strip()
    validate_version(version)
    report_dir = ROOT / '.artifacts/ci'
    report_dir.mkdir(parents=True, exist_ok=True)
    records = []
    passed = False
    try:
        with tempfile.TemporaryDirectory(prefix='ashen-check-') as temporary:
            temporary = Path(temporary)
            project = ROOT
            if args.clean:
                project = temporary / 'project'
                copy_source(ROOT, project)
            env = dict(os.environ, XDG_DATA_HOME=str(temporary / 'user-data'), XDG_CONFIG_HOME=str(temporary / 'user-config'))
            run_step('import', [engine, '--headless', '--path', str(project), '--import'], project, env, report_dir, records, timeout=900)
            run_step('python-tests', [sys.executable, '-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_*.py'], project, env, report_dir, records)
            run_step('runner-self-test', [sys.executable, 'tools/run_tests.py', '--self-test'], project, env, report_dir, records)
            run_step('game-tests', [sys.executable, 'tools/run_tests.py', '--godot', engine, '--jobs', str(args.jobs), '--timeout', str(args.test_timeout), '--report', str(report_dir / 'regression.json')], project, env, report_dir, records, timeout=1800)
            if args.release:
                build = ROOT / '.artifacts/build'
                build.mkdir(parents=True, exist_ok=True)
                binary = build / 'ashen-courtyard.x86_64'
                export_env = dict(env, XDG_DATA_HOME=str(args.toolchain.resolve() / 'data'))
                run_step('release-export', [engine, '--headless', '--path', str(project), '--export-release', 'Linux', str(binary)], project, export_env, report_dir, records, timeout=900)
                run_step('release-smoke', [str(binary), '--headless', '--fixed-fps', '60', '--', '--smoke-test'], build, env, report_dir, records, timeout=90, required_output='RELEASE SMOKE: PASS')
                run_step('release-animation-smoke', [str(binary), '--headless', '--', '--animation-benchmark', '--quick', '--output=' + str(temporary / 'animation-smoke.json')], build, env, report_dir, records, timeout=90, required_output='ANIMATION BENCHMARK COMPLETE:')
                package_release(build, project)
            passed = True
    except (OSError, RuntimeError, ValueError) as error:
        print(str(error), file=sys.stderr)
    finally:
        (report_dir / 'checks.json').write_text(json.dumps({'passed': passed, 'engine': version, 'clean': args.clean, 'release': args.release, 'steps': records}, indent=2) + '\n')
    print(f"{'PASS' if passed else 'FAIL'}: project checks; report {report_dir / 'checks.json'}")
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
