"""Build the normal macOS arm64 cohort and accept it in an external fresh venv.

This is CI acceptance, not publication. Component receipts remain component-only;
only a successful installed consumer produces acceptance.json.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zipfile

from python_release_cohort import select_release_version, verify_built_cohort

ROOT = Path(__file__).resolve().parents[1]
DUCKDB_URL = 'https://github.com/duckdb/duckdb/releases/download/v1.4.3/libduckdb-osx-universal.zip'
DUCKDB_SHA256 = 'efd0c2424589f0d5743ffdc0de22ce84b99bf307c330752f44277cffa3406e43'
DUCKDB_BYTES = 34189615
BUILD_REQUIREMENTS = ('build==1.3.0', 'setuptools==80.10.2', 'wheel==0.45.1',
                      'wasmtime==38.0.0', 'httpx==0.28.1', 'rfc8785==0.1.4')


def consumer_environment(venv: Path, home: Path) -> dict[str, str]:
    # No caller credentials, Python paths, Node, user pip configuration or startup hooks.
    return {'PATH': str(venv / 'bin'), 'HOME': str(home), 'TMPDIR': str(home / 'tmp'),
            'LANG': 'en_US.UTF-8', 'PYTHONNOUSERSITE': '1',
            'PIP_CONFIG_FILE': os.devnull, 'PIP_DISABLE_PIP_VERSION_CHECK': '1'}


def external_destination(value: Path) -> Path:
    path = value.resolve()
    if path == ROOT or ROOT in path.parents or path.exists():
        raise ValueError('Destination must be a fresh directory outside the checkout')
    return path


def open_duckdb_release():
    # Retry only transient HTTP rejection of this same pinned, read-only GET.
    # Size/digest validation below remains mandatory; no alternate release or
    # partially read archive is accepted or retried here.
    for attempt in range(3):
        try:
            return urllib.request.urlopen(DUCKDB_URL, timeout=120)
        except urllib.error.HTTPError as error:
            if error.code not in (408, 429, 500, 502, 503, 504) or attempt == 2:
                raise
            error.close()
            time.sleep(2 ** (attempt + 1))


def extract_duckdb(archive: Path, destination: Path) -> Path:
    if archive.stat().st_size != DUCKDB_BYTES or hashlib.sha256(archive.read_bytes()).hexdigest() != DUCKDB_SHA256:
        raise ValueError('DuckDB release archive differs from the pinned official release')
    with zipfile.ZipFile(archive) as zipped:
        matches = [item for item in zipped.infolist() if item.filename == 'libduckdb.dylib']
        if len(matches) != 1 or not 0 < matches[0].file_size <= 200_000_000:
            raise ValueError('Unavailable unique bounded DuckDB library')
        body = zipped.read(matches[0])
    destination.write_bytes(body)
    return destination


def run_acceptance(destination: Path) -> None:
    if (sys.platform, platform.machine()) != ('darwin', 'arm64'):
        raise ValueError('Normal Python Local wheels currently support darwin-arm64 only')
    destination = external_destination(destination)
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    def clean():
        if (subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip()
                or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source):
            raise ValueError('Acceptance requires the unchanged clean selected commit')
    clean()
    destination.mkdir(parents=True)
    steps = []
    def run(name, args, *, cwd=ROOT, env=None, timeout=600):
        started = time.monotonic()
        timed_out = False
        try:
            result = subprocess.run([str(arg) for arg in args], cwd=cwd, env=env,
                                    capture_output=True, timeout=timeout)
            stdout, stderr, code = result.stdout, result.stderr, result.returncode
        except subprocess.TimeoutExpired as error:
            stdout, stderr, code = error.stdout or b'', error.stderr or b'', None
            timed_out = True
        (destination / (name + '.stdout')).write_bytes(stdout)
        (destination / (name + '.stderr')).write_bytes(stderr)
        steps.append({'name': name, 'seconds': round(time.monotonic() - started, 3),
                      'exit_code': code, 'timed_out': timed_out})
        (destination / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        if timed_out or code:
            raise RuntimeError(f'{name} failed ({"timeout" if timed_out else code}); see {destination}/{name}.stderr')
        return stdout
    builder = destination / 'builder'
    run('builder-venv', [sys.executable, '-m', 'venv', builder])
    python = builder / 'bin/python'
    run('builder-dependencies', [python, '-m', 'pip', '--isolated', 'install', '--only-binary=:all:',
                                '--index-url', 'https://pypi.org/simple', *BUILD_REQUIREMENTS])
    run('platform-vm-original', [python, ROOT / 'scripts/fixtures/python-local-platform-vm-original.py'])
    archive = destination / 'duckdb.zip'
    with open_duckdb_release() as response, archive.open('xb') as target:
        body = response.read(DUCKDB_BYTES + 1)
        target.write(body)
    library = extract_duckdb(archive, destination / 'libduckdb.dylib')
    run('duckdb-physical', [python, ROOT / 'scripts/fixtures/python-local-duckdb-physical.py', library,
                          '--digest', hashlib.sha256(library.read_bytes()).hexdigest(), '--version', 'v1.4.3'])
    moon = destination / 'moon'
    run('core-build', ['moon', 'build', '--target', 'wasm', '--release', 'src/client_host_wasm', '--target-dir', moon])
    module = moon / 'wasm/release/build/client_host_wasm/client_host_wasm.wasm'
    receipt = destination / 'module-receipt.json'
    producer = ROOT / 'scripts/produce-python-local-runtime.py'
    run('core-receipt', [python, producer, '--record-module-original', '--source', source,
                        '--compiled-source', source, '--module', module, '--link-response', str(module) + '.rsp',
                        '--moon-home', os.environ['MOON_HOME'], '--destination', receipt])
    image = destination / 'image'
    run('image', [python, ROOT / 'scripts/compile-python-local-image.py', '--compile-platform',
                  '--source', source, '--core-receipt', receipt, '--destination', image])
    artifact = destination / 'artifact'
    run('runtime', [python, producer, '--platform-runtime', '--core-receipt', receipt,
                    '--duckdb-receipt', destination / 'duckdb-physical.stdout',
                    '--image-receipt', image / 'image-receipt.json', '--destination', artifact])
    semver = json.loads((ROOT / 'package.json').read_text())['version']
    version = select_release_version(semver)['pythonVersion']
    cohort_directory = destination / 'cohort'
    run('wheels', [python, ROOT / 'scripts/build-python-product-wheels.py', '--artifact-directory', artifact,
                   '--destination', cohort_directory, '--version', semver])
    cohort = verify_built_cohort(cohort_directory, source, version)['cohort']
    venv = destination / 'consumer'
    run('consumer-venv', [sys.executable, '-m', 'venv', venv])
    home = destination / 'home'
    (home / 'tmp').mkdir(parents=True)
    env = consumer_environment(venv, home)
    consumer = venv / 'bin/python'
    wheels = [cohort_directory / 'wheels' / item['file'] for item in cohort['wheels']]
    constraints = destination / 'constraints.txt'
    constraints.write_text(''.join(f"{item['distribution']} @ {wheel.as_uri()}\n"
                                  for item, wheel in zip(cohort['wheels'], wheels)))
    run('install', [consumer, '-I', '-m', 'pip', '--isolated', 'install', '--only-binary=:all:',
                    '--index-url', 'https://pypi.org/simple', '--no-cache-dir', '--no-compile',
                    '--constraint', constraints, '--report', destination / 'pip-report.json', wheels[-1]],
        cwd=destination, env=env)
    for name in ('python-product-installed.py', 'ci-python-installed-audit.py', 'ci-python-installed-health.py',
                 'ci-python-installed-run.py'):
        shutil.copyfile(ROOT / 'scripts/fixtures' / name, destination / name)
    def audit(name):
        run(name, [consumer, '-I', '-B', destination / 'ci-python-installed-audit.py',
                   '--cohort', cohort_directory, '--report', destination / 'pip-report.json'], cwd=destination, env=env)
    audit('installed-before')
    for facade in ('sync', 'async'):
        work = destination / facade
        work.mkdir()
        for phase in ('initial', 'resume'):
            run(f'{facade}-{phase}', [consumer, '-I', '-B', destination / 'ci-python-installed-run.py',
                destination / 'python-product-installed.py',
                '--version', version, '--mode', 'local', '--facade', facade, '--phase', phase,
                '--receipt', work / 'original.json'], cwd=work, env=env, timeout=180)
    health = destination / 'health'
    health.mkdir()
    run('health', [consumer, '-I', '-B', destination / 'ci-python-installed-run.py',
                   destination / 'ci-python-installed-health.py'], cwd=health, env=env, timeout=180)
    audit('installed-after')
    verify_built_cohort(cohort_directory, source, version)
    clean()
    (destination / 'acceptance.json').write_text(json.dumps({
        'source_sha': source, 'platform': 'darwin-arm64', 'package_version': version,
        'cohort_sha256': hashlib.sha256((cohort_directory / 'cohort.json').read_bytes()).hexdigest(),
        'normal_wheel_install': True, 'public_local_accepted': True,
        'separate_process_saved': True, 'typed_refusal_and_health': True,
        'context_close': True, 'physical_release_observed': False,
        'published': False, 'steps': steps}, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    run_acceptance(parser.parse_args().destination)
