#!/usr/bin/env python3
"""Run Godot suites in isolated user-data directories; fail on script errors too."""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
LOCAL_ENGINE = ROOT / '.artifacts/toolchain/godot'
DEFAULT_ENGINE = LOCAL_ENGINE if LOCAL_ENGINE.is_file() else Path('<USER_HOME>/Desktop/Ashen Courtyard/Godot_v4.6.2-stable_linux.x86_64')


def classify(code, output):
    summaries = re.findall(r'(\d+) checks,\s*(\d+) failures', output)
    errors = re.findall(r'^(?:SCRIPT ERROR:|ERROR:|FAIL\b).*', output, re.M)
    checks, failures = map(int, summaries[-1]) if summaries else (0, 0)
    passed = code == 0 and bool(summaries) and failures == 0 and not errors
    return {'passed': passed, 'checks': checks, 'failures': failures,
            'exit_code': code, 'errors': errors, 'missing_summary': not summaries}


def timeout_output(error):
    # TimeoutExpired retains bytes even when subprocess.run uses text=True.
    def decode(value):
        return value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
    return decode(error.stdout) + decode(error.stderr) + '\nERROR: Test timed out\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', str(LOCAL_ENGINE) if LOCAL_ENGINE.is_file() else (shutil.which('godot') or str(DEFAULT_ENGINE))))
    parser.add_argument('--suite', action='append', help='Suite stem, e.g. run_camera; repeat to select several')
    parser.add_argument('--render-fps', type=int, default=60, help='Fixed render rate, independent of each suite physics rate')
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--timeout', type=int, default=60)
    parser.add_argument('--report', type=Path, default=ROOT / '.artifacts/tests/latest.json')
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--player-model', help='res:// model scene override for player compatibility suites')
    args = parser.parse_args()
    if args.render_fps <= 0:
        parser.error("Render FPS must be positive")
    if args.self_test:
        assert classify(0, 'RESULT: 2 checks, 0 failures')['passed']
        assert not classify(0, 'SCRIPT ERROR: broken\nRESULT: 2 checks, 0 failures')['passed']
        assert not classify(0, 'ERROR: broken\nRESULT: 2 checks, 0 failures')['passed']
        assert not classify(1, 'RESULT: 2 checks, 0 failures')['passed']
        assert not classify(0, 'RESULT: 2 checks, 1 failures')['passed']
        assert not classify(0, 'Godot exited without running its tests')['passed']
        print('Runner self-test: 6 checks, 0 failures')
        return 0
    args.report = args.report.resolve()
    args.godot = shutil.which(args.godot) or str(Path(args.godot).expanduser().resolve())
    suites = [ROOT / 'tests' / f'{s}.gd' for s in args.suite] if args.suite else sorted((ROOT / 'tests').glob('run*.gd'))
    if not Path(args.godot).is_file() or not suites or any(not s.is_file() for s in suites):
        parser.error('Godot executable or selected test suite is missing')
    args.report.parent.mkdir(parents=True, exist_ok=True)
    log_dir = args.report.parent / (args.report.stem + '-logs')
    log_dir.mkdir(exist_ok=True)

    def run(suite):
        started = time.monotonic()
        with tempfile.TemporaryDirectory(prefix='ashen-test-') as user_data:
            env = dict(os.environ, XDG_DATA_HOME=user_data, XDG_CONFIG_HOME=user_data)
            command = [args.godot, '--headless', '--fixed-fps', str(args.render_fps), '--path', str(ROOT),
                       '--log-file', str(log_dir / f'{suite.stem}-engine.log'),
                       '--script', 'res://' + str(suite.relative_to(ROOT))]
            if args.player_model:
                wrapper = Path(user_data) / 'model_suite.gd'
                wrapper.write_text(
                    'extends ' + json.dumps('res://' + str(suite.relative_to(ROOT))) + '\n'
                    'func _initialize() -> void:\n'
                    '\tvar scene = load("res://scenes/player.tscn")\n'
                    '\tvar player = scene.instantiate()\n'
                    '\tplayer.model_scene = load(' + json.dumps(args.player_model) + ')\n'
                    '\tscene.pack(player)\n'
                    '\tplayer.free()\n'
                    '\tsuper._initialize()\n')
                command[-1] = str(wrapper)
            try:
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=args.timeout)
                output, code = result.stdout + result.stderr, result.returncode
            except subprocess.TimeoutExpired as error:
                output = timeout_output(error)
                code = -1
        (log_dir / f'{suite.stem}.log').write_text(output)
        record = dict(suite=suite.stem, seconds=round(time.monotonic()-started, 3), **classify(code, output))
        print(f"{'PASS' if record['passed'] else 'FAIL'} {suite.stem}: {record['checks']} checks", flush=True)
        return record

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        records = list(pool.map(run, suites))
    report = {'engine': args.godot, 'passed': all(r['passed'] for r in records),
              'checks': sum(r['checks'] for r in records), 'suites': records}
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(f"{'PASS' if report['passed'] else 'FAIL'}: {report['checks']} checks across {len(records)} suites; report {args.report}")
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
