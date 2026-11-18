"""Build the selected normal macOS arm64 or Linux x64 cohort and accept it in an external fresh venv.

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
LINUX_DUCKDB_URL = 'https://github.com/duckdb/duckdb/releases/download/v1.4.3/libduckdb-linux-amd64.zip'
LINUX_DUCKDB_SHA256 = '3c7bb8d586d39ccce56442c3f6bafa97f53d7b6bb5405dac827442fcb31494aa'
LINUX_DUCKDB_BYTES = 36042490
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


def normal_target() -> str:
    """Select only a physical packaging/consumer route, never a Run authority.

    The original component/image owners still admit libc, exact dependencies,
    Engine settings and source before loading or construction.
    """
    selected = {('darwin', 'arm64'): 'darwin-arm64',
                ('linux', 'x86_64'): 'linux-x64'}.get((sys.platform, platform.machine()))
    if selected is None:
        raise ValueError('Normal Python Local wheels require darwin-arm64 or linux-x64')
    return selected


def duckdb_release(target_platform: str) -> tuple[str, str, int, str]:
    if target_platform == 'darwin-arm64':
        return DUCKDB_URL, DUCKDB_SHA256, DUCKDB_BYTES, 'libduckdb.dylib'
    if target_platform == 'linux-x64':
        return LINUX_DUCKDB_URL, LINUX_DUCKDB_SHA256, LINUX_DUCKDB_BYTES, 'libduckdb.so'
    raise ValueError('No selected normal DuckDB release target')


def open_duckdb_release(target_platform: str = 'darwin-arm64'):
    # Retry only transient HTTP rejection of this same pinned, read-only GET.
    # Size/digest validation below remains mandatory; no alternate release or
    # partially read archive is accepted or retried here.
    url, _, _, _ = duckdb_release(target_platform)
    for attempt in range(3):
        try:
            return urllib.request.urlopen(url, timeout=120)
        except urllib.error.HTTPError as error:
            if error.code not in (408, 429, 500, 502, 503, 504) or attempt == 2:
                raise
            error.close()
            time.sleep(2 ** (attempt + 1))


def extract_duckdb(archive: Path, destination: Path, *, target_platform: str = 'darwin-arm64') -> Path:
    _, digest, size, member = duckdb_release(target_platform)
    if archive.stat().st_size != size or hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
        raise ValueError('DuckDB release archive differs from the pinned official release')
    with zipfile.ZipFile(archive) as zipped:
        matches = [item for item in zipped.infolist() if item.filename == member]
        if len(matches) != 1 or not 0 < matches[0].file_size <= 200_000_000:
            raise ValueError('Unavailable unique bounded DuckDB library')
        body = zipped.read(matches[0])
    destination.write_bytes(body)
    return destination


def accept_submission_observation(run, python: Path, module: Path, receipt: Path,
                                  destination: Path) -> dict:
    """Consume this producer's original Core once; never build a second module.

    The result remains a raw ABI/physical-caller component. Normal installed
    execution and Saved acceptance retain their existing separate consumers.
    """
    original = json.loads(receipt.read_text())
    if (Path(original['module']).resolve() != module.resolve()
            or original['module_sha256'] != hashlib.sha256(module.read_bytes()).hexdigest()):
        raise ValueError('Submission observation requires the original Core module')
    observed = json.loads(run('submission-observation', [python,
        ROOT / 'scripts/fixtures/python-local-submission-observation-abi.py', module,
        destination / 'submission-observation-state'], timeout=180))
    cases = observed.get('cases')
    if (observed.get('success') is not True or observed.get('module_sha256') != original['module_sha256']
            or not isinstance(cases, list) or len(cases) != 6
            or any(not isinstance(case, str) or not case for case in cases)
            or len(set(cases)) != len(cases) or type(observed.get('fuel_refills')) is not int
            or observed['fuel_refills'] != 0
            or type(observed.get('initial_diagnostic_fuel')) is not int
            or not 0 < observed['initial_diagnostic_fuel'] < 2**64):
        raise ValueError('Incomplete original Submission observation component')
    result = {'source_sha': original['source_sha'],
              'module_sha256': original['module_sha256'], 'component': observed,
              'qualification': 'actual raw ABI/Python/SQLite component only',
              'normal_image_acceptance': False, 'public_run_acceptance': False}
    with (destination / 'submission-observation.json').open('x') as output:
        json.dump(result, output, indent=2)
        output.write('\n')
    return result


def accept_public_lifecycle(run, python: Path, module: Path, receipt: Path,
                            destination: Path) -> dict:
    """Reuse this producer's Core for the existing public lifecycle boundary.

    Each control owns fresh SQLite state. These source SDK/raw ABI checks do
    not replace the later normal wheel install or promote physical ACK scope.
    """
    original = json.loads(receipt.read_text())
    def unchanged():
        if (Path(original['module']).resolve() != module.resolve()
                or original['module_sha256'] != hashlib.sha256(module.read_bytes()).hexdigest()):
            raise ValueError('Public lifecycle requires the original Core module')
    unchanged()
    cases = []
    controls = (
        ('cancellation-saved', 'python-local-public-cancellation-abi.py', 'process-state',
         'public_default_cancel_separate_process_saved_without_reprepare'),
        ('cancellation-precommit', 'python-local-public-cancellation-abi.py', 'precommit-state',
         'public_cancel_before_original_publication_commit_refuses_write_and_retires_same_work'),
        ('state-unknown', 'python-local-public-cancellation-abi.py', 'fault-state',
         'public_state_commit_reply_loss_original_readback_without_rewrite'),
        ('state-partial-close', 'python-local-public-cancellation-abi.py', 'partial-state',
         'public_state_partial_input_close_same_original_retirement'),
        ('succeeded-result-saved', 'python-local-public-success-abi.py', None,
         'public_succeeded_execute_typed_result_same_saved_and_close'),
        ('publication-unknown', 'python-local-public-success-abi.py', 'commit-unknown',
         'public_commit_reply_loss_original_lookup_same_result_without_reexecution'),
    )
    for name, fixture, selection, expected in controls:
        args = [python, ROOT / 'scripts/fixtures' / fixture, module,
                destination / (name + '-state')]
        if selection is not None:
            args.append(selection)
        observed = json.loads(run(name, args, timeout=300))
        unchanged()
        if (observed.get('success') is not True or type(observed.get('actualCases')) is not int
                or observed['actualCases'] != 1 or observed.get('case') != expected
                or observed.get('module_sha256') != original['module_sha256']):
            raise ValueError('Incomplete original public lifecycle component')
        if (fixture == 'python-local-public-success-abi.py'
                and observed.get('atomic_precommit_writer_exclusion') is not True):
            raise ValueError('Incomplete original atomic publication component')
        if (selection == 'commit-unknown'
                and observed.get('commit_reply_loss_readback_without_reexecution') is not True):
            raise ValueError('Incomplete original publication recovery component')
        cases.append(observed)
    result = {'source_sha': original['source_sha'], 'module_sha256': original['module_sha256'],
              'cases': cases, 'qualification': 'actual source SDK/raw ABI/SQLite components only',
              'normal_image_acceptance': False, 'installed_wheel_acceptance': False}
    with (destination / 'public-lifecycle.json').open('x') as output:
        json.dump(result, output, indent=2)
        output.write('\n')
    return result


def run_acceptance(destination: Path) -> None:
    target_platform = normal_target()
    _, _, archive_bytes, library_name = duckdb_release(target_platform)
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
    with open_duckdb_release(target_platform) as response, archive.open('xb') as target:
        body = response.read(archive_bytes + 1)
        target.write(body)
    library = extract_duckdb(archive, destination / library_name, target_platform=target_platform)
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
    accept_submission_observation(run, python, module, receipt, destination)
    accept_public_lifecycle(run, python, module, receipt, destination)
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
                   '--destination', cohort_directory, '--version', semver, '--target-platform', target_platform])
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
        'source_sha': source, 'platform': target_platform, 'package_version': version,
        'cohort_sha256': hashlib.sha256((cohort_directory / 'cohort.json').read_bytes()).hexdigest(),
        'normal_wheel_install': True, 'public_local_accepted': True,
        'separate_process_saved': True, 'typed_refusal_and_health': True,
        'context_close': True, 'physical_release_observed': False,
        'published': False, 'steps': steps}, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    run_acceptance(parser.parse_args().destination)
