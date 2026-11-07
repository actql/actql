"""Consume the SAME normal darwin-arm64 wheels on a selected interpreter.

No builder, source path resolution, wheel repair, ABI override or fallback.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from python_release_cohort import verify_built_cohort

ROOT = Path(__file__).resolve().parents[1]
# Official PyPI pip26.3 supports Python>=3.10 and the stable report-v1 schema.
PIP_VERSION = '26.3'
PIP_SHA256 = 'f3b60b20ffaadd4415ed7957212a38ac63fa4c5fa375bd0f4a797777940fad13'
SPEC = importlib.util.spec_from_file_location('existing_python_wheel_acceptance', ROOT / 'scripts/ci-python-wheels.py')
EXISTING = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXISTING)


def accept(cohort_directory: Path, destination: Path, version: str) -> None:
    if version not in ('3.11.0', '3.15.2') or platform.python_version() != version:
        raise ValueError('Select the exact supported Python interpreter')
    if (sys.platform, platform.machine()) != ('darwin', 'arm64'):
        raise ValueError('Normal Python Local wheels support darwin-arm64 only')
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip():
        raise ValueError('Supported Python acceptance requires clean source')
    cohort_directory = cohort_directory.resolve()
    original = (cohort_directory / 'cohort.json').read_bytes()
    declared = json.loads(original)
    cohort = verify_built_cohort(cohort_directory, source, declared['package_version'])['cohort']
    destination = EXISTING.external_destination(destination)
    destination.mkdir(parents=True)
    venv = destination / 'venv'
    subprocess.run([sys.executable, '-m', 'venv', str(venv)], check=True, timeout=60)
    home = destination / 'home'
    (home / 'tmp').mkdir(parents=True)
    env = EXISTING.consumer_environment(venv, home)
    python = venv / 'bin/python'
    # Python3.11.0 ensurepip ships pip22.3's experimental report-v0. Keep the
    # interpreter and strict existing auditor; pin only the installer tooling.
    pip_requirements = destination / 'pip-requirements.txt'
    pip_requirements.write_text(f'pip=={PIP_VERSION} --hash=sha256:{PIP_SHA256}\n')
    subprocess.run([str(python), '-I', '-m', 'pip', '--isolated', 'install',
                    '--index-url', 'https://pypi.org/simple', '--only-binary=:all:',
                    '--require-hashes', '--no-deps', '--no-cache-dir', '-r', str(pip_requirements)],
                   cwd=destination, env=env, check=True, timeout=120)
    wheels = [cohort_directory / 'wheels' / item['file'] for item in cohort['wheels']]
    constraints = destination / 'constraints.txt'
    constraints.write_text(''.join(f"{item['distribution']} @ {wheel.as_uri()}\n"
                                  for item, wheel in zip(cohort['wheels'], wheels)))
    report = destination / 'pip-report.json'
    subprocess.run([str(python), '-I', '-m', 'pip', '--isolated', 'install', '--only-binary=:all:',
                    '--index-url', 'https://pypi.org/simple', '--no-cache-dir', '--no-compile',
                    '--constraint', str(constraints), '--report', str(report), str(wheels[-1])],
                   cwd=destination, env=env, check=True, timeout=180)
    for name in ('ci-python-installed-audit.py', 'ci-python-installed-health.py', 'ci-python-installed-run.py'):
        shutil.copyfile(ROOT / 'scripts/fixtures' / name, destination / name)
    def audit():
        subprocess.run([str(python), '-I', '-B', str(destination / 'ci-python-installed-audit.py'),
                        '--cohort', str(cohort_directory), '--report', str(report)],
                       cwd=destination, env=env, check=True, timeout=60)
    audit()
    subprocess.run([str(python), '-I', '-B', str(destination / 'ci-python-installed-run.py'),
                    str(destination / 'ci-python-installed-health.py')], cwd=destination, env=env,
                   check=True, timeout=180)
    audit()
    verify_built_cohort(cohort_directory, source, declared['package_version'])
    if (cohort_directory / 'cohort.json').read_bytes() != original:
        raise ValueError('Original producer manifest changed')
    if (subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip()
            or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source):
        raise ValueError('Source changed during supported Python acceptance')
    (destination / 'acceptance.json').write_text(json.dumps({'python': version, 'source': source,
        'cohort_sha256': hashlib.sha256(original).hexdigest(), 'platform': 'darwin-arm64',
        'installer': PIP_VERSION, 'installer_sha256': PIP_SHA256,
        'fresh_wheel_install': True, 'local_open_query_close': True, 'published': False}, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cohort', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    accept(args.cohort, args.destination, args.version)
