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
import re
import shutil
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zipfile

from python_model_installed_case import accept_installed_portable_model
from python_release_cohort import select_release_version, verify_built_cohort

ROOT = Path(__file__).resolve().parents[1]
DUCKDB_URL = 'https://github.com/duckdb/duckdb/releases/download/v1.4.3/libduckdb-osx-universal.zip'
DUCKDB_SHA256 = 'efd0c2424589f0d5743ffdc0de22ce84b99bf307c330752f44277cffa3406e43'
DUCKDB_BYTES = 34189615
LINUX_DUCKDB_URL = 'https://github.com/duckdb/duckdb/releases/download/v1.4.3/libduckdb-linux-amd64.zip'
LINUX_DUCKDB_SHA256 = '3c7bb8d586d39ccce56442c3f6bafa97f53d7b6bb5405dac827442fcb31494aa'
LINUX_DUCKDB_BYTES = 36042490
BUILD_REQUIREMENTS = ('build==1.3.0', 'setuptools==80.10.2', 'wheel==0.45.1',
                      'wasmtime==51.0.0', 'httpx==0.28.1', 'rfc8785==0.1.4')


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
                            destination: Path, *, platform_artifact: Path) -> dict:
    """Reuse this producer's Core for the existing public lifecycle boundary.

    Each control owns fresh SQLite state. Succeeded delivery uses the same
    selected image as the ordinary runtime. Installed wheels are checked later.
    """
    original = json.loads(receipt.read_text())
    artifact_bytes = _read_runtime_evidence(platform_artifact, 'artifact.json', 65536)
    artifact = json.loads(artifact_bytes, object_pairs_hook=_unique_runtime_receipt_pairs)
    image = artifact['compiled_image']
    image_digest = image['sha256']
    if (artifact['source_sha'] != original['source_sha']
            or artifact['module']['sha256'] != original['module_sha256']
            or image['runtime_allocation'] != 'platform'
            or type(image_digest) is not str or re.fullmatch('[0-9a-f]{64}', image_digest) is None):
        raise ValueError('Public lifecycle requires the original platform image')
    def unchanged():
        if (Path(original['module']).resolve() != module.resolve()
                or original['module_sha256'] != hashlib.sha256(module.read_bytes()).hexdigest()):
            raise ValueError('Public lifecycle requires the original Core module')
        if _read_runtime_evidence(platform_artifact, 'artifact.json', 65536) != artifact_bytes:
            raise ValueError('Public lifecycle original platform image selection changed')
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
        succeeded = fixture == 'python-local-public-success-abi.py'
        if succeeded:
            args.extend(('--platform-artifact', platform_artifact))
        observed = json.loads(run(name, args, timeout=timeout))
        unchanged()
        if (observed.get('success') is not True or type(observed.get('actualCases')) is not int
                or observed['actualCases'] != 1 or observed.get('case') != expected
                or observed.get('module_sha256') != original['module_sha256']):
            raise ValueError('Incomplete original public lifecycle component')
        if succeeded:
            if observed.get('atomic_precommit_writer_exclusion') is not True:
                raise ValueError('Incomplete original atomic publication component')
            if (observed.get('image_sha256') != image_digest
                    or observed.get('first_core_closed') is not True
                    or observed.get('saved_first_core_closed') is not True):
                raise ValueError('Incomplete original platform image and Saved close observation')
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
              'image_sha256': image_digest, 'cases': cases,
              'qualification': 'source SDK/SQLite lifecycle and selected platform image components',
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


def accept_installed_saved(run, consumer: Path, destination: Path,
                           source: str, cohort, env: dict[str, str]) -> dict:
    """Qualify the existing continuation and fuel controls in one installed cohort."""
    work = destination / 'saved-read'
    work.mkdir(mode=0o700)
    fuel = work / 'fuel'
    fuel.mkdir(mode=0o700)
    continuation = work / 'python-local-saved-continuation.py'
    interruption = work / 'python-local-saved-read-interruption.py'
    for fixture in (continuation, interruption, work / 'ci-python-installed-fuel.py'):
        shutil.copyfile(ROOT / 'scripts/fixtures' / fixture.name, fixture)
    identity = {'source': source, 'module': cohort['module_sha256'], 'image': cohort['image_sha256']}
    pids: set[int] = set()

    def observed(name, script, args, directory):
        raw = run(name, [consumer, '-I', '-B', script, *args], cwd=directory, env=env, timeout=180)
        lines = raw.splitlines()
        record = json.loads(lines[-1]) if lines else None
        if (type(record) is not dict or any(record.get(key) != value for key, value in identity.items())
                or type(record.get('pid')) is not int or record['pid'] <= 0 or record['pid'] in pids):
            raise ValueError('Missing exact installed Saved process and cohort')
        pids.add(record['pid'])
        return record

    continued = observed('installed-saved-continuation', continuation,
                         [work / 'continuation-state', '--installed-continuation', source], work)
    core, hashed = (continued.get(name) for name in ('core_cancellation', 'hash_cancellation'))
    reads = continued.get('successful_reads')
    if (continued.get('first_close') is not True or continued.get('rows') != 1
            or not core or core[-1].get('phase') != 'core'
            or not hashed or hashed[-1].get('phase') != 'hash'
            or type(reads) is not list or len(reads) != 2
            or any(type(read.get('core_turns')) is not int or read['core_turns'] < 2 for read in reads)):
        raise ValueError('Incomplete installed Saved suspension, cancellation or successful reads')

    warm = observed('installed-saved-fuel-warm', continuation,
                    [fuel, '--warm-interruption', source], fuel)
    if warm.get('phase') != 'warm' or warm.get('first_close') is not True:
        raise ValueError('Missing original Saved fuel fixture and first close')
    stopped = observed('installed-saved-fuel-interruption', interruption,
                       [fuel, source], fuel)
    injections = stopped.get('injections')
    if type(injections) is not list or len(injections) != 1 or type(injections[0]) is not dict:
        raise ValueError('Missing one actual Saved fuel injection under current')
    injection = injections[0]
    if (type(injection.get('before')) is not int or injection['before'] <= 0
            or type(injection.get('after')) is not int or injection['after'] != 0
            or type(injection.get('ticket')) is not int or injection['ticket'] <= 0
            or type(injection.get('operation')) is not int or injection['operation'] <= 0
            or type(injection.get('actualCurrentResult')) is not int
            or injection['actualCurrentResult'] != injection['operation']):
        raise ValueError('Missing one actual Saved fuel injection under current')
    trap_code = stopped.get('originalTrapCode')
    out_of_fuel_code = stopped.get('outOfFuelTrapCode')
    if (stopped.get('passed') is not True or stopped.get('cases') != 1
            or type(trap_code) is not int or not 0 < trap_code <= 255
            or type(out_of_fuel_code) is not int or trap_code != out_of_fuel_code
            or stopped.get('firstClose') is not True
            or stopped.get('normalFenced') is not True or stopped.get('sameStore') is not True
            or stopped.get('newSubmission') is not False or stopped.get('installedSourceOverlay') is not False):
        raise ValueError('Incomplete same-original Saved fuel stop and first close')
    recovery = observed('installed-saved-fuel-recovery', continuation,
                        [fuel, '--recover-interruption', source], fuel)
    if (recovery.get('phase') != 'recover' or recovery.get('first_close') is not True
            or recovery.get('same_saved') is not True or recovery.get('replayed') is not False):
        raise ValueError('Incomplete original Saved recovery after fuel interruption')
    return {**identity, 'continuation_pid': continued['pid'], 'fuel_warm_pid': warm['pid'],
            'fuel_stop_pid': stopped['pid'], 'fuel_recovery_pid': recovery['pid'],
            'original_first_closes_returned': True}


def accept_installed_numeric_reductions(run, consumer: Path, destination: Path,
                                        source: str, module: str, env: dict[str, str]) -> None:
    work = destination / 'numeric-reductions'
    work.mkdir(mode=0o700)
    fixture = work / 'installed_numeric_reductions.py'
    shutil.copyfile(ROOT / 'packages/python-sdk/tests' / fixture.name, fixture)
    previous_pid = None
    for phase in ('initial', 'saved'):
        observed = json.loads(run('installed-linux-numeric-' + phase, [
            consumer, '-I', '-B', destination / 'ci-python-installed-run.py',
            fixture, phase, source, module,
        ], cwd=work, env=env, timeout=180))
        if type(observed) is not dict:
            raise ValueError('Invalid installed numeric reductions receipt')
        pid = observed.get('pid')
        if (observed.get('phase') != phase or observed.get('source') != source
                or observed.get('module') != module
                or observed.get('cases') != ['pivot', 'sum', 'count', 'parse-timestamp']
                or observed.get('first_close') is not True
                or type(pid) is not int or pid <= 0 or pid == previous_pid):
            raise ValueError('Incomplete installed Local profile cases or original Saved')
        previous_pid = pid


def accept_installed_csv_projects(run, consumer: Path, destination: Path, cohort: Path,
                                  source: str, env: dict[str, str]) -> dict:
    fixtures = ROOT / 'scripts/fixtures'
    work = destination / 'csv-projects'
    work.mkdir()
    for filename in ('python-product-csv-installed.py', 'python_csv_publication.py', 'python-csv-project-cases.json'):
        shutil.copyfile(fixtures / filename, work / filename)
    cases = json.loads((work / 'python-csv-project-cases.json').read_bytes())['cases']
    receipts = []
    for facade in ('sync', 'async'):
        for case in cases:
            selections = tuple(command['file'] for command in case['sql']) or (None,)
            for command in selections:
                branch = work / facade / case['id'] / (command or 'invalid')
                project = branch / 'project'
                project.mkdir(parents=True)
                for file, value in case['files'].items():
                    path = project / file
                    path.parent.mkdir(exist_ok=True, parents=True)
                    path.write_bytes(value['wire'].encode('utf-8'))
                prefix = [consumer, '-I', '-B', destination / 'ci-python-installed-run.py',
                          work / 'python-product-csv-installed.py', '--case', case['id'],
                          '--facade', facade, '--source', source, '--cohort', cohort / 'cohort.json']
                phases = ('refuse',) if command is None else ('initial', 'saved')
                if command is not None:
                    prefix.extend(('--command', command))
                original = branch / 'initial.json'
                for phase in phases:
                    arguments = [*prefix, '--phase', phase]
                    if phase == 'saved':
                        arguments.extend(('--prior', original))
                    name = '-'.join(('installed-csv', facade, case['id'], command or 'invalid', phase))
                    observed = json.loads(run(name, arguments, cwd=project, env=env, timeout=180))
                    if (type(observed['pid']) is not int or observed['pid'] <= 0
                            or not observed['first_close'] or observed['phase'] != phase
                            or observed['case'] != case['id'] or observed['facade'] != facade
                            or observed['command'] != command or observed['source']['source_sha'] != source):
                        raise ValueError('Missing first close from the installed CSV original')
                    if phase == 'initial':
                        with original.open('x') as retained:
                            json.dump(observed, retained)
                    receipts.append(observed)
    if len(receipts) != 14 or len({receipt['pid'] for receipt in receipts}) != len(receipts):
        raise ValueError('Installed CSV phases require distinct original processes')
    return {'fixture_index_sha256': hashlib.sha256((work / 'python-csv-project-cases.json').read_bytes()).hexdigest(),
            'phases': receipts}


def accept_installed_named_results(run, consumer: Path, destination: Path,
                                   version: str, env: dict[str, str]) -> None:
    work = destination / 'named-results'
    work.mkdir(mode=0o700)
    fixture = work / 'named-result-publication.json'
    shutil.copyfile(ROOT / 'scripts/fixtures' / fixture.name, fixture)
    pids = set()
    for facade in ('sync', 'async'):
        selected = work / facade
        selected.mkdir(mode=0o700)
        receipt = selected / 'original.json'
        for phase in ('initial', 'resume'):
            observed = json.loads(run('installed-named-results-' + facade + '-' + phase, [
                consumer, '-I', '-B', destination / 'ci-python-installed-run.py',
                destination / 'python-product-installed.py', '--mode', 'local', '--facade', facade,
                '--version', version, '--phase', phase, '--case', 'named-results',
                '--named-results-fixture', fixture, '--receipt', receipt,
            ], cwd=selected, env=env, timeout=180))
            if type(observed) is not dict:
                raise ValueError('Invalid installed named Results receipt')
            pid = observed.get('pid')
            names = observed.get('results')
            if (observed.get('mode') != 'local' or observed.get('version') != version
                    or observed.get('case') != 'named-results' or observed.get('phase') != phase
                    or observed.get('facade') != facade
                    or type(names) is not list or len(names) != 2
                    or 'before_change' not in names or 'after_change' not in names
                    or observed.get('named_submission') is not True
                    or observed.get('same_name_reused') is not (phase == 'initial')
                    or observed.get('changed_intent_refused') is not (phase == 'initial')
                    or observed.get('submitted') is not (phase == 'initial')
                    or observed.get('original_run_reused') is not (phase == 'resume')
                    or observed.get('first_close') is not True
                    or type(pid) is not int or pid <= 0 or pid in pids):
                raise ValueError('Incomplete installed named Results or original Saved')
            pids.add(pid)


def prepare_normal_runtime(run, python: Path, destination: Path, source: str,
                           target_platform: str, model_crypto_preparation: Path | None) -> Path:
    _, _, archive_bytes, library_name = duckdb_release(target_platform)
    run('platform-vm-original', [python, ROOT / 'scripts/fixtures/python-local-platform-vm-original.py'])
    run('closed-wasm-sql', [python, '-I', '-B', ROOT / 'packages/python-sdk/tests/run.py',
                           '--pattern', 'test_local_closed_wasm_sql.py'])
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
    image = destination / 'image'
    run('image', [python, ROOT / 'scripts/compile-python-local-image.py', '--compile-platform',
                  '--source', source, '--core-receipt', receipt, '--destination', image])
    artifact = destination / 'artifact'
    runtime_arguments = [python, producer, '--platform-runtime', '--core-receipt', receipt,
                         '--duckdb-receipt', destination / 'duckdb-physical.stdout',
                         '--image-receipt', image / 'image-receipt.json', '--destination', artifact]
    if model_crypto_preparation is not None:
        runtime_arguments.extend(('--model-crypto-preparation', model_crypto_preparation))
    run('runtime', runtime_arguments)
    accept_public_lifecycle(run, python, module, receipt, destination, platform_artifact=artifact)
    if model_crypto_preparation is not None:
        retained_crypto = destination / 'model-crypto'
        retained_crypto.mkdir()
        (artifact / 'model-crypto-producer.json').rename(retained_crypto / 'producer.json')
    return artifact


def _read_runtime_evidence(root: Path, relative: str, maximum: int) -> bytes:
    path = root / relative
    if path.resolve(strict=True) != path:
        raise ValueError('Ordinary runtime evidence uses an indirect path')
    def generation(info):
        return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns

    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= maximum:
            raise ValueError('Invalid ordinary runtime evidence extent')
        raw = stream.read(maximum + 1)
        after = os.fstat(stream.fileno())
        if len(raw) != before.st_size or generation(before) != generation(after):
            raise ValueError('Ordinary runtime evidence changed during read')
    current = path.stat(follow_symlinks=False)
    if generation(current) != generation(after):
        raise ValueError('Ordinary runtime evidence was replaced')
    return raw


def _unique_runtime_receipt_pairs(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError('Duplicate ordinary runtime evidence field')
    return result


def select_normal_runtime(preparation: Path, source: str, target_platform: str
                          ) -> tuple[Path, dict[str, bytes]]:
    root = preparation.resolve(strict=True)
    if not root.is_dir() or root == ROOT or ROOT in root.parents:
        raise ValueError('Select an ordinary runtime preparation outside the checkout')
    paths = {'artifact/artifact.json': 65536, 'artifact/producer.json': 65536,
             'image/image-receipt.json': 65536, 'module-receipt.json': 65536,
             'duckdb-physical.stdout': 65536}
    evidence = {name: _read_runtime_evidence(root, name, maximum) for name, maximum in paths.items()}
    artifact = json.loads(evidence['artifact/artifact.json'], object_pairs_hook=_unique_runtime_receipt_pairs)
    producer = json.loads(evidence['artifact/producer.json'], object_pairs_hook=_unique_runtime_receipt_pairs)
    if (type(artifact) is not dict or type(producer) is not dict
            or artifact.get('source_sha') != source or artifact.get('platform') != target_platform
            or type(artifact.get('compiled_image')) is not dict
            or artifact['compiled_image'].get('runtime_allocation') != 'platform'
            or producer.get('scope') != 'ordinary_platform_components_only'
            or producer.get('source_sha') != source or producer.get('artifact') != artifact
            or producer.get('wheel_built') is not False or producer.get('runtime_executed') is not False
            or producer.get('public_local_accepted') is not False):
        raise ValueError('Foreign ordinary runtime preparation')
    references = {'artifact/artifact.json': 'artifact_sha256', 'image/image-receipt.json': 'image_receipt_sha256',
                  'module-receipt.json': 'core_receipt_sha256', 'duckdb-physical.stdout': 'duckdb_receipt_sha256'}
    if 'model_crypto' in artifact:
        name = 'model-crypto/producer.json'
        evidence[name] = _read_runtime_evidence(root, name, 2 * 1024 * 1024)
        references[name] = 'model_crypto_receipt_sha256'
    elif 'model_crypto_receipt_sha256' in producer:
        raise ValueError('Ordinary runtime Model component evidence is inconsistent')
    if any(hashlib.sha256(evidence[name]).hexdigest() != producer.get(pin)
           for name, pin in references.items()):
        raise ValueError('Ordinary runtime preparation evidence differs from its producer')
    return root / 'artifact', evidence


def run_acceptance(destination: Path, *, model_crypto_preparation: Path | None = None,
                   runtime_preparation: Path | None = None, shared_wheels: Path | None = None,
                   prepare_runtime_only: bool = False,
                   pair_runtime_preparations: dict[str, Path] | None = None,
                   expected_source: str | None = None) -> None:
    target_platform = normal_target()
    if ((runtime_preparation is None) != (shared_wheels is None)
            or runtime_preparation is not None and (prepare_runtime_only or model_crypto_preparation is not None)):
        raise ValueError('Select one runtime preparation or consume one with the paired shared wheels')
    if pair_runtime_preparations is not None and (
            set(pair_runtime_preparations) != {'linux-x64', 'darwin-arm64'}
            or expected_source is None or re.fullmatch('[0-9a-f]{40}', expected_source) is None
            or any(value is not None for value in (model_crypto_preparation, runtime_preparation, shared_wheels))
            or prepare_runtime_only):
        raise ValueError('Select both original runtime preparations and the exact shared Python source')
    destination = external_destination(destination)
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if expected_source is not None and expected_source != source:
        raise ValueError('Foreign ordinary Python source')
    def clean():
        if (subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip()
                or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source):
            raise ValueError('Acceptance requires the unchanged clean selected commit')
    clean()
    original_runtime = (select_normal_runtime(runtime_preparation, source, target_platform)
                        if runtime_preparation is not None else None)
    pair_originals = {}
    if pair_runtime_preparations is not None:
        pair_originals = {
            platform: select_normal_runtime(preparation, source, platform)
            for platform, preparation in sorted(pair_runtime_preparations.items())
        }
        model_roles = {'model-crypto/producer.json' in evidence for _, evidence in pair_originals.values()}
        if len(model_roles) != 1:
            raise ValueError('Original Python platform runtimes select different Model variants')
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
    if pair_runtime_preparations is not None:
        semver = json.loads((ROOT / 'package.json').read_text())['version']
        command = [python, ROOT / 'scripts/build-python-product-wheels.py',
                   '--destination', destination / 'shared', '--version', semver]
        for platform, (artifact, _) in pair_originals.items():
            command.extend(('--paired-runtime-artifact', platform, artifact))
        run('shared-wheels', command)
        if any(select_normal_runtime(preparation, source, platform) != pair_originals[platform]
               for platform, preparation in pair_runtime_preparations.items()):
            raise ValueError('Original Python platform runtime changed during shared wheel construction')
        clean()
        return
    if runtime_preparation is None:
        artifact = prepare_normal_runtime(run, python, destination, source, target_platform, model_crypto_preparation)
        model_enabled = model_crypto_preparation is not None
    else:
        assert original_runtime is not None
        artifact, evidence = original_runtime
        for name, raw in evidence.items():
            retained = destination / name
            retained.parent.mkdir(parents=True, exist_ok=True)
            with retained.open('xb') as stream:
                stream.write(raw)
        model_enabled = 'model-crypto/producer.json' in evidence
    clean()
    if prepare_runtime_only:
        return
    semver = json.loads((ROOT / 'package.json').read_text())['version']
    version = select_release_version(semver)['pythonVersion']
    cohort_directory = destination / 'cohort'
    wheels_arguments = [python, ROOT / 'scripts/build-python-product-wheels.py', '--artifact-directory', artifact,
                        '--destination', cohort_directory, '--version', semver, '--target-platform', target_platform]
    if shared_wheels is not None:
        wheels_arguments.extend(('--shared-wheels', shared_wheels.resolve(strict=True)))
    run('wheels', wheels_arguments)
    cohort = verify_built_cohort(cohort_directory, source, version)['cohort']
    if original_runtime is not None:
        assert runtime_preparation is not None
        source_artifact = hashlib.sha256(original_runtime[1]['artifact/artifact.json']).hexdigest()
        if (cohort['release_metadata']['source_artifact_sha256'] != source_artifact
                or select_normal_runtime(runtime_preparation, source, target_platform) != original_runtime):
            raise ValueError('Ordinary runtime preparation changed during wheel construction')
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
    accept_installed_cancellation(run, consumer, destination, version, env)
    retained_store = destination / 'retained-store'
    retained_store.mkdir()
    retained_consumer = destination / 'ci-python-retained-store.py'
    shutil.copyfile(ROOT / 'scripts/fixtures' / retained_consumer.name, retained_consumer)
    run('installed-retained-store', [consumer, '-I', '-B', retained_consumer,
        'verify', retained_store, version], cwd=retained_store, env=env, timeout=360)
    if target_platform == 'linux-x64':
        accept_installed_numeric_reductions(
            run, consumer, destination, source, cohort['module_sha256'], env)
    csv_projects = accept_installed_csv_projects(run, consumer, destination, cohort_directory, source, env)
    accept_installed_named_results(run, consumer, destination, version, env)
    repeated_host = accept_installed_repeated_host(run, consumer, destination, env)
    accept_installed_fuel(run, consumer, destination, source, cohort, env)
    saved_read = accept_installed_saved(run, consumer, destination, source, cohort, env)
    portable_model = None
    if model_enabled:
        portable_model = accept_installed_portable_model(
            run, consumer, destination, version, env, cohort['image_sha256'], source=True)
    audit('installed-after')
    verify_built_cohort(cohort_directory, source, version)
    clean()
    (destination / 'acceptance.json').write_text(json.dumps({
        'source_sha': source, 'platform': target_platform, 'package_version': version,
        'csv_projects': csv_projects,
        **({'portable_model': portable_model} if portable_model is not None else {}),
        'cohort_sha256': hashlib.sha256((cohort_directory / 'cohort.json').read_bytes()).hexdigest(),
        'normal_wheel_install': True, 'public_local_accepted': True,
        'separate_process_saved': True, 'typed_refusal_and_health': True,
        'context_close': True, 'installed_active_cancellation': True,
        'ordinary_repeated_host': repeated_host, 'installed_saved_read': saved_read,
        'cancelled_saved_recovery': True, 'first_cancel_case_close': True,
        'physical_release_observed': False,
        'published': False, 'steps': steps}, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--model-crypto-preparation', type=Path)
    parser.add_argument('--prepare-runtime-only', action='store_true')
    parser.add_argument('--runtime-preparation', type=Path)
    parser.add_argument('--shared-wheels', type=Path)
    parser.add_argument('--pair-runtime-preparation', nargs=2, action='append', metavar=('PLATFORM', 'DIRECTORY'))
    parser.add_argument('--source', help='Exact clean source SHA selected by the ordinary job')
    arguments = parser.parse_args()
    preparation = arguments.model_crypto_preparation
    pair = None
    if arguments.pair_runtime_preparation is not None:
        pair = {platform: Path(directory) for platform, directory in arguments.pair_runtime_preparation}
        if len(pair) != len(arguments.pair_runtime_preparation):
            parser.error('Select each original runtime platform once')
    run_acceptance(arguments.destination,
                   model_crypto_preparation=preparation.resolve(strict=True) if preparation is not None else None,
                   runtime_preparation=arguments.runtime_preparation, shared_wheels=arguments.shared_wheels,
                   prepare_runtime_only=arguments.prepare_runtime_only,
                   pair_runtime_preparations=pair, expected_source=arguments.source)
