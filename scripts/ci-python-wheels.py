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
         'public_default_cancel_separate_process_saved_without_reprepare', 300),
        ('cancellation-precommit', 'python-local-public-cancellation-abi.py', 'precommit-state',
         'public_cancel_before_original_publication_commit_refuses_write_and_retires_same_work', 300),
        ('state-unknown', 'python-local-public-cancellation-abi.py', 'fault-state',
         'public_state_commit_reply_loss_original_readback_without_rewrite', 300),
        ('state-partial-close', 'python-local-public-cancellation-abi.py', 'partial-state',
         'public_state_partial_input_close_same_original_retirement', 300),
        ('succeeded-result-saved', 'python-local-public-success-abi.py', None,
         'public_succeeded_execute_typed_result_same_saved_and_close', 300),
        ('publication-unknown', 'python-local-public-success-abi.py', 'commit-unknown',
         'public_commit_reply_loss_original_lookup_same_result_without_reexecution', 300),
        ('task-drive-mixed', 'python-local-public-success-abi.py', 'task-drive-mixed',
         'public_core_derived_task_drive_mixed_quanta_joined_result_same_saved', 300),
        ('cancellation-drive-start', 'python-local-public-cancellation-abi.py', 'drive-start-state',
         'public_cancel_between_derived_drives_before_first_input_feed', 120),
    )
    for name, fixture, selection, expected, timeout in controls:
        args = [python, ROOT / 'scripts/fixtures' / fixture, module,
                destination / (name + '-state')]
        if selection is not None:
            args.append(selection)
        observed = json.loads(run(name, args, timeout=timeout))
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
        if selection == 'task-drive-mixed':
            if (observed.get('core_owned_lifecycle') is not True
                    or type(observed.get('original_tasks')) is not int or observed['original_tasks'] < 2
                    or observed.get('monotonic_progress') is not True):
                raise ValueError('Incomplete original task-drive component')
            expected = {'initial_quantum': 1, 'initial_drives_per_task': 8,
                        'continuation_quantum': 256,
                        'actual_initial_quantum_drives': 8 * observed['original_tasks'],
                        'observed_phase_transitions': observed['original_tasks']}
            if any(type(observed.get(key)) is not int or observed[key] != value
                   for key, value in expected.items()):
                raise ValueError('Incomplete original task-drive component')
        cases.append(observed)
    result = {'source_sha': original['source_sha'], 'module_sha256': original['module_sha256'],
              'cases': cases, 'qualification': 'actual source SDK/raw ABI/SQLite components only',
              'normal_image_acceptance': False, 'installed_wheel_acceptance': False}
    with (destination / 'public-lifecycle.json').open('x') as output:
        json.dump(result, output, indent=2)
        output.write('\n')
    return result


def accept_installed_cancellation(run, consumer: Path, destination: Path,
                                  version: str, env: dict[str, str]) -> None:
    """Use this same normal install for public cancellation and saved reads.

    Each facade owns one fresh public state directory. The consumer refuses a
    missed active window instead of retrying work or accepting already_terminal.
    """
    for facade in ('sync', 'async'):
        work = destination / (facade + '-cancellation')
        work.mkdir()
        previous_pid = None
        for phase in ('initial', 'resume'):
            observed = json.loads(run(f'{facade}-cancellation-{phase}',
                [consumer, '-I', '-B', destination / 'ci-python-installed-run.py',
                 destination / 'python-product-installed.py',
                 '--version', version, '--mode', 'local', '--facade', facade,
                 '--phase', phase, '--case', 'cancellation', '--receipt', work / 'original.json'],
                cwd=work, env=env, timeout=180))
            if (observed.get('mode') != 'local' or observed.get('version') != version
                    or observed.get('case') != 'cancellation' or observed.get('facade') != facade
                    or observed.get('phase') != phase or type(observed.get('actualCases')) is not int
                    or observed['actualCases'] != 1 or type(observed.get('pid')) is not int
                    or observed['pid'] <= 0 or observed['pid'] == previous_pid
                    or observed.get('reported_physical_stop') not in ('unknown', 'confirmed')):
                raise ValueError('Incomplete installed cancellation consumer')
            expected = {'admitted_inflight': phase == 'initial', 'original_cancel_accepted': True,
                        'cancel_lookup_same': True, 'original_run_reused': phase == 'resume',
                        'same_host_healthy_after_cancel': phase == 'initial',
                        'saved_read_only': phase == 'resume', 'first_close': True, 'closed': True}
            if any(observed.get(key) is not value for key, value in expected.items()):
                raise ValueError('Incomplete installed cancellation consumer')
            previous_pid = observed['pid']


def require_installed_fuel_fault(observed, phase: str, previous_pid: int | None) -> None:
    """Require the explicit negative control, never a normal-budget override."""
    if (type(observed) is not dict or observed.get('phase') != phase
            or type(observed.get('pid')) is not int or observed['pid'] <= 0
            or observed['pid'] == previous_pid or observed.get('firstClose') is not True
            or observed.get('replayed') is not False):
        raise ValueError('Incomplete installed fuel-stop control')
    if phase == 'initial':
        if (observed.get('intentionalFuel') != 1_000
                or observed.get('defaultFuel') != 64_000_000_000
                or type(observed.get('actualAttempts')) is not int or observed['actualAttempts'] != 1
                or any(observed.get(key) is not True for key in ('outOfFuel', 'normalFenced', 'sameStore'))):
            raise ValueError('Incomplete installed original fuel exhaustion')
    elif phase != 'resume' or any(observed.get(key) is not True for key in ('sameSaved', 'failedAdmissionAbsent')):
        raise ValueError('Incomplete installed fuel-stop Saved recovery')


def require_installed_repeated_host(events, phase: str, previous_pid: int | None) -> int:
    """Read only the maintained public consumer's bounded phase/close events."""
    if (phase not in ('warm', 'saved') or type(events) is not list
            or not 0 < len(events) <= 256 or any(type(event) is not dict for event in events)):
        raise ValueError('Incomplete ordinary repeated-Host event record')
    opened = [event for event in events if event.get('phase') == 'opened' and event.get('mode') == phase]
    if len(opened) != 1:
        raise ValueError('Missing unique ordinary owning factory')
    pid = opened[0].get('pid')
    if type(pid) is not int or pid <= 0 or pid == previous_pid:
        raise ValueError('Ordinary Saved requires a distinct consumer process')
    current = [event for event in events if type(event.get('pid')) is int and event['pid'] == pid]
    names = [event.get('phase') for event in current]
    complete = [event for event in current if event.get('phase') == phase + '-complete']
    result_phase = 'result-complete' if phase == 'warm' else 'saved-result-complete'
    ordinals = [event.get('ordinal') for event in current if event.get('phase') == result_phase]
    if (len(complete) != 1 or type(complete[0].get('runs')) is not int or complete[0]['runs'] != 10
            or any(type(ordinal) is not int for ordinal in ordinals) or ordinals != list(range(1, 11))
            or names.count('first-close-attempted') != 1 or names.count('first-close-returned') != 1
            or 'primary-failure' in names or 'first-close-failed' in names
            or names[-1] != 'first-close-returned'):
        raise ValueError('Incomplete ordinary Run/Result or original first close')
    checkpoints = [event for event in current if event.get('phase') == 'checkpoint-complete']
    if phase == 'warm':
        if ([event.get('ordinal') for event in checkpoints] != [1, 3, 10]
                or any(type(event.get('ordinal')) is not int
                       or event.get('retirement_checked') is not True for event in checkpoints)):
            raise ValueError('Missing original ordinary reread/attach and retirement checkpoints')
    elif complete[0].get('retirement_checked') is not True:
        raise ValueError('Missing original Saved reader retirement checkpoint')
    return pid


def accept_installed_repeated_host(run, consumer: Path, destination: Path, env: dict[str, str]) -> dict:
    """The same original public fixture, fresh owning Home and separate Saved."""
    work = destination / 'ordinary-repeated-host'
    work.mkdir(mode=0o700)
    fixture = work / 'python-local-repeated-host.py'
    shutil.copyfile(ROOT / 'scripts/fixtures' / fixture.name, fixture)
    home, temporary, workspace = (work / name for name in ('home', 'tmp', 'workspace'))
    for directory in (home, temporary, workspace):
        directory.mkdir(mode=0o700)
    ordinary_env = dict(env, HOME=str(home), TMPDIR=str(temporary))
    previous_pid = None
    pids = []
    for phase, timeout in (('warm', 900), ('saved', 180)):
        run('installed-ordinary-repeated-' + phase, [consumer, '-I', '-B', fixture, phase],
            cwd=workspace, env=ordinary_env, timeout=timeout)
        events = work / 'events.jsonl'
        if not events.is_file() or events.stat().st_size > 262144:
            raise ValueError('Missing bounded ordinary repeated-Host events')
        previous_pid = require_installed_repeated_host(
            [json.loads(line) for line in events.read_bytes().splitlines()], phase, previous_pid)
        pids.append(previous_pid)
    return {'runs': 10, 'warm_pid': pids[0], 'saved_pid': pids[1],
            'successful_retirement_checkpoints': [1, 3, 10],
            'closed_saved_read_retirement_checked': True,
            'original_first_closes_returned': True}


def accept_installed_fuel(run, consumer: Path, destination: Path,
                          source: str, cohort, env: dict[str, str]) -> None:
    """One changed-default regression and one deliberate fail-closed operation.

    The pending-history case is explicitly a private-parent-retirement fixture,
    separate from ordinary repeated public Runs. It forwards the original
    production quantum; independent current/refusal tests retain quantum one.
    Forty crosses the former admission failure, not a supported-history threshold.
    """
    for name in ('python-local-sdk-current-history.py', 'ci-python-installed-fuel.py'):
        shutil.copyfile(ROOT / 'scripts/fixtures' / name, destination / name)
    work = destination / 'fuel-default'
    work.mkdir()
    raw = run('installed-default-fuel-admission', [consumer, '-I', '-B',
        destination / 'python-local-sdk-current-history.py', '--installed', source,
        work, 'fuel-pending:40'], cwd=work, env=env, timeout=900)
    observed = json.loads(raw.splitlines()[-1])
    histories = observed.get('histories')
    if (observed.get('fuelMode', {}).get('sourceDeclaredLimit') != 64_000_000_000
            or observed.get('installedCohort', {}).get('sourceSha') != source
            or observed.get('installedCohort', {}).get('moduleSha256') != cohort['module_sha256']
            or observed.get('installedCohort', {}).get('imageSha256') != cohort['image_sha256']
            or type(histories) is not list or len(histories) != 1
            or histories[0].get('taskQuantumMode') != 'production-original'
            or histories[0].get('acceptedPendingHistory') != 40
            or histories[0].get('retiredPendingParentLoans') != 40
            or histories[0].get('firstCloseReturned') is not True
            or histories[0].get('cleanupFailures') != []):
        raise ValueError('Incomplete installed default-fuel admission')
    work = destination / 'fuel-stop'
    work.mkdir()
    previous_pid = None
    for phase in ('initial', 'resume'):
        observed = json.loads(run('installed-fuel-stop-' + phase, [consumer, '-I', '-B',
            destination / 'ci-python-installed-fuel.py', '--phase', phase,
            '--state', work / 'state', '--receipt', work / 'original.json'],
            cwd=work, env=env, timeout=180))
        require_installed_fuel_fault(observed, phase, previous_pid)
        previous_pid = observed['pid']


def require_closed_task_drive(observed) -> None:
    """Require the existing installed initial case's same-Core call witness."""
    witness = observed.get('closed_task_drive') if type(observed) is dict else None
    counts = ('drive_calls', 'drive_returns', 'wasm_entries', 'wasm_returns', 'retained_holder_checks')
    flags = ('actual_closed_task_drive', 'methods_unchanged', 'profilers_restored')
    absent = ('per_drive_fuel_observed', 'hash_count_observed')
    if (type(witness) is not dict or set(witness) != set(counts + flags + absent)
            or any(witness.get(key) is not True for key in flags)
            or any(witness.get(key) is not False for key in absent)
            or any(type(witness.get(key)) is not int or not 0 < witness[key] <= 1024 for key in counts)
            or len({witness[key] for key in counts}) != 1):
        raise ValueError('Incomplete installed closed task drive control')


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
            observed = run(f'{facade}-{phase}', [consumer, '-I', '-B', destination / 'ci-python-installed-run.py',
                destination / 'python-product-installed.py',
                '--version', version, '--mode', 'local', '--facade', facade, '--phase', phase,
                '--receipt', work / 'original.json'], cwd=work, env=env, timeout=180)
            if facade == 'sync' and phase == 'initial':
                require_closed_task_drive(json.loads(observed))
    health = destination / 'health'
    health.mkdir()
    run('health', [consumer, '-I', '-B', destination / 'ci-python-installed-run.py',
                   destination / 'ci-python-installed-health.py'], cwd=health, env=env, timeout=180)
    accept_installed_cancellation(run, consumer, destination, version, env)
    repeated_host = accept_installed_repeated_host(run, consumer, destination, env)
    accept_installed_fuel(run, consumer, destination, source, cohort, env)
    audit('installed-after')
    verify_built_cohort(cohort_directory, source, version)
    clean()
    (destination / 'acceptance.json').write_text(json.dumps({
        'source_sha': source, 'platform': target_platform, 'package_version': version,
        'cohort_sha256': hashlib.sha256((cohort_directory / 'cohort.json').read_bytes()).hexdigest(),
        'normal_wheel_install': True, 'public_local_accepted': True,
        'separate_process_saved': True, 'typed_refusal_and_health': True,
        'context_close': True, 'installed_active_cancellation': True,
        'ordinary_repeated_host': repeated_host,
        'cancelled_saved_recovery': True, 'first_cancel_case_close': True,
        'physical_release_observed': False,
        'published': False, 'steps': steps}, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    run_acceptance(parser.parse_args().destination)
